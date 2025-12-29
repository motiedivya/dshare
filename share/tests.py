from django.contrib.auth import get_user_model
from django.test import TestCase
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


class AuthFlowsTests(TestCase):
    def test_register_creates_user_and_token(self):
        res = self.client.post(
            reverse("api_auth_register"),
            data='{"email":"a@example.com","password":"pw"}',
            content_type="application/json",
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "ok")

        user = User.objects.get(username="a@example.com")
        self.assertEqual(user.email, "a@example.com")
        self.assertTrue(EmailVerificationToken.objects.filter(user=user).exists())

    def test_verify_email_marks_verified_and_logs_in(self):
        user = User.objects.create_user(username="v@example.com", email="v@example.com", password="pw")
        UserProfile.objects.get_or_create(user=user)
        token = EmailVerificationToken.objects.create(user=user)

        res = self.client.get(reverse("auth_verify_email", kwargs={"token": token.token}))
        self.assertEqual(res.status_code, 302)

        profile = UserProfile.objects.get(user=user)
        self.assertIsNotNone(profile.email_verified_at)

        self.assertEqual(int(self.client.session["_auth_user_id"]), user.id)

    def test_password_login(self):
        user = User.objects.create_user(
            username="p@example.com", email="p@example.com", password="pw"
        )
        profile, _ = UserProfile.objects.get_or_create(user=user)
        profile.email_verified_at = timezone.now()
        profile.save(update_fields=["email_verified_at"])

        res = self.client.post(
            reverse("api_auth_login"),
            data='{"email":"p@example.com","password":"pw"}',
            content_type="application/json",
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "ok")

    def test_verify_email_rejects_expired_token(self):
        user = User.objects.create_user(username="x@example.com", email="x@example.com", password="pw")
        token = EmailVerificationToken.objects.create(user=user)
        EmailVerificationToken.objects.filter(pk=token.pk).update(
            created_at=timezone.now() - timezone.timedelta(days=2)
        )
        token.refresh_from_db()

        res = self.client.get(reverse("auth_verify_email", kwargs={"token": token.token}))
        self.assertEqual(res.status_code, 302)
        self.assertFalse(UserProfile.objects.filter(user=user, email_verified_at__isnull=False).exists())
