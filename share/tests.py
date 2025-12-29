import json

from django.contrib.auth import get_user_model
from django.core import mail
from django.core.cache import cache
from django.test import Client
from django.test import TestCase
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone

from .models import EmailVerificationToken, PublicShareState, UserProfile, UserShareState

User = get_user_model()


class ShareFlowsTests(TestCase):
    def test_public_upload_and_download_text(self):
        res = self.client.post(reverse("upload"), {"text": "hello"})
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "ok")

        public_share = PublicShareState.objects.get(pk=1)
        self.assertEqual(public_share.text, "hello")

        download = self.client.get(reverse("download"))
        self.assertEqual(download.status_code, 200)
        self.assertEqual(download["Content-Type"], "text/plain")
        self.assertEqual(download.content.decode("utf-8"), "hello")

    def test_user_upload_is_private(self):
        user = User.objects.create_user(username="u@example.com", email="u@example.com", password="pw")
        self.client.force_login(user)

        res = self.client.post(reverse("upload"), {"text": "secret"})
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "ok")

        user_share = UserShareState.objects.get(user=user)
        self.assertEqual(user_share.text, "secret")

        self.assertFalse(PublicShareState.objects.exists())

        download = self.client.get(reverse("download"))
        self.assertEqual(download.status_code, 200)
        self.assertEqual(download.content.decode("utf-8"), "secret")

        self.client.logout()
        public_download = self.client.get(reverse("download"))
        self.assertEqual(public_download.status_code, 200)
        self.assertEqual(public_download.json()["status"], "empty")


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class AuthFlowsTests(TestCase):
    def setUp(self):
        super().setUp()
        cache.clear()

    def test_register_without_pin_sends_verification_and_leaves_unusable_password(self):
        res = self.client.post(
            reverse("api_auth_register"),
            data=json.dumps({"email": "a@example.com", "password": ""}),
            content_type="application/json",
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "ok")
        self.assertEqual(len(mail.outbox), 1)

        user = User.objects.get(username="a@example.com")
        self.assertFalse(user.has_usable_password())
        self.assertTrue(EmailVerificationToken.objects.filter(user=user).exists())

        token = EmailVerificationToken.objects.get(user=user)
        verify = self.client.get(
            reverse("auth_verify_email", kwargs={"token": token.token})
        )
        self.assertEqual(verify.status_code, 302)

        profile = UserProfile.objects.get(user=user)
        self.assertIsNotNone(profile.email_verified_at)
        user.refresh_from_db()
        self.assertFalse(user.has_usable_password())

    def test_register_with_pin_sets_password_after_verify_same_session(self):
        res = self.client.post(
            reverse("api_auth_register"),
            data=json.dumps({"email": "p@example.com", "password": "1234"}),
            content_type="application/json",
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "ok")
        self.assertEqual(len(mail.outbox), 1)

        user = User.objects.get(username="p@example.com")
        self.assertFalse(user.has_usable_password())
        token = EmailVerificationToken.objects.get(user=user)

        verify = self.client.get(
            reverse("auth_verify_email", kwargs={"token": token.token})
        )
        self.assertEqual(verify.status_code, 302)

        user.refresh_from_db()
        self.assertTrue(user.has_usable_password())
        self.assertTrue(user.check_password("1234"))

        self.client.post(reverse("api_auth_logout"))
        login_res = self.client.post(
            reverse("api_auth_login"),
            data=json.dumps({"email": "p@example.com", "password": "1234"}),
            content_type="application/json",
        )
        self.assertEqual(login_res.status_code, 200)
        self.assertEqual(login_res.json()["status"], "ok")

    def test_register_with_pin_does_not_set_password_if_verified_elsewhere(self):
        client_a = Client()
        client_b = Client()

        res = client_a.post(
            reverse("api_auth_register"),
            data=json.dumps({"email": "x@example.com", "password": "9999"}),
            content_type="application/json",
        )
        self.assertEqual(res.status_code, 200)

        user = User.objects.get(username="x@example.com")
        token = EmailVerificationToken.objects.get(user=user)

        verify = client_b.get(
            reverse("auth_verify_email", kwargs={"token": token.token})
        )
        self.assertEqual(verify.status_code, 302)

        user.refresh_from_db()
        self.assertFalse(user.has_usable_password())
        self.assertFalse(user.check_password("9999"))

        profile = UserProfile.objects.get(user=user)
        self.assertIsNotNone(profile.email_verified_at)

        login_res = client_b.post(
            reverse("api_auth_login"),
            data=json.dumps({"email": "x@example.com", "password": "9999"}),
            content_type="application/json",
        )
        self.assertEqual(login_res.status_code, 401)

    def test_password_login_requires_verified_email(self):
        user = User.objects.create_user(
            username="u@example.com", email="u@example.com", password="pw"
        )
        UserProfile.objects.get_or_create(user=user)

        res = self.client.post(
            reverse("api_auth_login"),
            data=json.dumps({"email": "u@example.com", "password": "pw"}),
            content_type="application/json",
        )
        self.assertEqual(res.status_code, 403)
        self.assertEqual(res.json()["status"], "fail")

    def test_login_without_pin_sends_magic_link_and_does_not_authenticate(self):
        res = self.client.post(
            reverse("api_auth_login"),
            data=json.dumps({"email": "m@example.com"}),
            content_type="application/json",
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "sent")
        self.assertEqual(len(mail.outbox), 1)

        me = self.client.get(reverse("api_auth_me"))
        self.assertEqual(me.status_code, 200)
        self.assertFalse(me.json()["authenticated"])

        user = User.objects.get(username="m@example.com")
        token = EmailVerificationToken.objects.get(user=user)
        verify = self.client.get(
            reverse("auth_verify_email", kwargs={"token": token.token})
        )
        self.assertEqual(verify.status_code, 302)

        me2 = self.client.get(reverse("api_auth_me"))
        self.assertEqual(me2.status_code, 200)
        self.assertTrue(me2.json()["authenticated"])

    def test_verify_email_rejects_expired_token(self):
        user = User.objects.create_user(username="z@example.com", email="z@example.com", password="pw")
        token = EmailVerificationToken.objects.create(user=user)
        EmailVerificationToken.objects.filter(pk=token.pk).update(
            created_at=timezone.now() - timezone.timedelta(days=2)
        )
        token.refresh_from_db()

        res = self.client.get(reverse("auth_verify_email", kwargs={"token": token.token}))
        self.assertEqual(res.status_code, 302)
        self.assertFalse(UserProfile.objects.filter(user=user, email_verified_at__isnull=False).exists())
