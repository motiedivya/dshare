import json
import logging
import os
from urllib.parse import urlencode

from django.conf import settings
from django.contrib.auth import authenticate, get_user_model, login, logout
from django.core.cache import cache
from django.core.exceptions import ValidationError
from django.core.files.storage import default_storage
from django.core.mail import EmailMultiAlternatives
from django.core.validators import validate_email
from django.contrib.auth.hashers import check_password, make_password
from django.http import FileResponse, HttpRequest, HttpResponse, JsonResponse
from django.shortcuts import redirect, render
from django.urls import reverse
from django.utils import timezone
from django.views.decorators.csrf import ensure_csrf_cookie
from django.views.decorators.http import require_GET, require_POST
try:
    from fido2.server import Fido2Server
    from fido2.utils import websafe_decode
    from fido2.webauthn import (
        AttestedCredentialData,
        PublicKeyCredentialRpEntity,
        PublicKeyCredentialUserEntity,
        ResidentKeyRequirement,
        UserVerificationRequirement,
    )

    _FIDO2_AVAILABLE = True
except ModuleNotFoundError:  # pragma: no cover
    Fido2Server = None  # type: ignore[assignment]
    websafe_decode = None  # type: ignore[assignment]
    AttestedCredentialData = None  # type: ignore[assignment]
    PublicKeyCredentialRpEntity = None  # type: ignore[assignment]
    PublicKeyCredentialUserEntity = None  # type: ignore[assignment]
    ResidentKeyRequirement = None  # type: ignore[assignment]
    UserVerificationRequirement = None  # type: ignore[assignment]
    _FIDO2_AVAILABLE = False

from .models import (
    EmailVerificationToken,
    PublicShareState,
    UserProfile,
    UserShareState,
    WebAuthnCredential,
)

User = get_user_model()
logger = logging.getLogger(__name__)


def _parse_json(request: HttpRequest) -> dict:
    try:
        return json.loads(request.body.decode("utf-8") or "{}")
    except (json.JSONDecodeError, UnicodeDecodeError):
        return {}


def _client_ip(request: HttpRequest) -> str:
    # If behind a proxy, configure SECURE_PROXY_SSL_HEADER / USE_X_FORWARDED_HOST.
    return request.META.get("REMOTE_ADDR") or "0.0.0.0"


def _get_rp_id(request: HttpRequest) -> str:
    configured = getattr(settings, "DSHARE_RP_ID", None)
    if configured:
        return configured
    return request.get_host().split(":", 1)[0]


def _get_rp_name() -> str:
    return getattr(settings, "DSHARE_RP_NAME", "DShare")


def _get_fido_server(request: HttpRequest) -> Fido2Server:
    if not _FIDO2_AVAILABLE:  # pragma: no cover
        raise RuntimeError("WebAuthn unavailable (missing fido2)")
    rp = PublicKeyCredentialRpEntity(id=_get_rp_id(request), name=_get_rp_name())
    return Fido2Server(rp)


def _get_or_create_profile(user) -> UserProfile:
    profile, _ = UserProfile.objects.get_or_create(user=user)
    return profile


@require_POST
def api_auth_email_status(request: HttpRequest) -> JsonResponse:
    data = _parse_json(request)
    email = (data.get("email") or "").strip().lower()
    if not email:
        return JsonResponse({"status": "fail"}, status=400)

    try:
        validate_email(email)
    except ValidationError:
        return JsonResponse({"status": "fail"}, status=400)

    ip = _client_ip(request)
    throttle_key = f"dshare:email_status:{ip}"
    attempts = cache.get(throttle_key, 0)
    if attempts >= 120:
        return JsonResponse({"status": "fail"}, status=429)
    cache.set(throttle_key, attempts + 1, timeout=60 * 10)

    can_login = False
    user = User.objects.filter(username=email).first()
    if user and user.is_active:
        profile = _get_or_create_profile(user)
        can_login = profile.email_verified_at is not None

    return JsonResponse({"status": "ok", "can_login": can_login})


def _send_verification_email(*, request: HttpRequest, user, token: str) -> None:
    verify_url = request.build_absolute_uri(
        reverse("auth_verify_email", kwargs={"token": token})
    )
    subject = "DShare"
    text_body = f"Verify: {verify_url}"
    html_body = f"""
<!doctype html>
<html>
  <head>
    <meta name="color-scheme" content="dark">
    <meta name="supported-color-schemes" content="dark">
  </head>
  <body style="margin:0;padding:0;background:#000;color:#000;font-family:Arial, sans-serif;">
    <a href="{verify_url}" style="display:block;width:100%;padding:24px;background:#000;color:#000;text-decoration:none;">
      Verify
    </a>
  </body>
</html>
""".strip()

    message = EmailMultiAlternatives(
        subject=subject,
        body=text_body,
        from_email=getattr(settings, "DEFAULT_FROM_EMAIL", None),
        to=[user.email],
    )
    message.attach_alternative(html_body, "text/html")
    try:
        logger.info(f"Sending email to {user.email} via {settings.EMAIL_HOST}:{settings.EMAIL_PORT} (SSL={settings.EMAIL_USE_SSL}, TLS={settings.EMAIL_USE_TLS}) Timeout={settings.EMAIL_TIMEOUT}")
        message.send(fail_silently=False)
    except Exception:
        logger.exception("Failed to send verification email")
        raise


@ensure_csrf_cookie
def home_view(request):
    return render(request, "share/home.html")


@require_POST
def api_auth_register(request: HttpRequest) -> JsonResponse:
    data = _parse_json(request)
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    pin = data.get("pin") or ""

    if not email:
        return JsonResponse({"status": "fail"}, status=400)

    try:
        validate_email(email)
    except ValidationError:
        return JsonResponse({"status": "fail"}, status=400)

    if not password:
        return JsonResponse({"status": "fail"}, status=400)

    ip = _client_ip(request)
    throttle_key = f"dshare:register:{ip}"
    attempts = cache.get(throttle_key, 0)
    if attempts >= 10:
        return JsonResponse({"status": "fail"}, status=429)
    cache.set(throttle_key, attempts + 1, timeout=60 * 10)

    user = User.objects.filter(username=email).first()
    if user is None:
        user = User(username=email, email=email)
        user.set_unusable_password()
        user.save()

    _get_or_create_profile(user)

    EmailVerificationToken.objects.filter(user=user, used_at__isnull=True).delete()
    token_obj = EmailVerificationToken.objects.create(
        user=user,
        pending_password_hash=make_password(password),
        pending_pin_hash=make_password(pin) if pin else None,
    )
    try:
        _send_verification_email(request=request, user=user, token=token_obj.token)
    except Exception as exc:
        token_obj.delete()
        payload = {"status": "fail", "code": "email_send_failed"}
        if settings.DEBUG:
            payload["detail"] = str(exc)[:500]
        return JsonResponse(payload, status=502)

    return JsonResponse({"status": "ok"})


@require_GET
def verify_email_view(request: HttpRequest, token: str) -> HttpResponse:
    max_age_seconds = int(getattr(settings, "DSHARE_EMAIL_TOKEN_MAX_AGE_SECONDS", 86400))
    token_obj = (
        EmailVerificationToken.objects.select_related("user")
        .filter(token=token)
        .first()
    )
    if (
        token_obj is None
        or token_obj.used_at is not None
        or token_obj.is_expired(max_age_seconds=max_age_seconds)
    ):
        return redirect("home")

    now = timezone.now()
    token_obj.used_at = now
    token_obj.save(update_fields=["used_at"])

    profile = _get_or_create_profile(token_obj.user)
    if profile.email_verified_at is None:
        profile.email_verified_at = now
        profile.save(update_fields=["email_verified_at"])

    did_apply = False
    if token_obj.pending_password_hash:
        token_obj.user.password = token_obj.pending_password_hash
        token_obj.user.save(update_fields=["password"])
        did_apply = True
    if token_obj.pending_pin_hash:
        profile.pin_hash = token_obj.pending_pin_hash
        profile.save(update_fields=["pin_hash"])
        did_apply = True
    if did_apply:
        token_obj.pending_password_hash = None
        token_obj.pending_pin_hash = None
        token_obj.save(update_fields=["pending_password_hash", "pending_pin_hash"])

    login(request, token_obj.user, backend="django.contrib.auth.backends.ModelBackend")

    url = f'{reverse("home")}?{urlencode({"verified": "1"})}'
    return redirect(url)


@require_POST
def api_auth_password_login(request: HttpRequest) -> JsonResponse:
    data = _parse_json(request)
    email = (data.get("email") or "").strip().lower()
    secret = data.get("secret") or data.get("password") or data.get("pin") or ""
    if not email:
        return JsonResponse({"status": "fail"}, status=400)

    try:
        validate_email(email)
    except ValidationError:
        return JsonResponse({"status": "fail"}, status=400)

    ip = _client_ip(request)
    throttle_key = f"dshare:login_fail:{ip}"
    attempts = cache.get(throttle_key, 0)
    if attempts >= 50:
        return JsonResponse({"status": "fail"}, status=429)

    if not secret:
        return JsonResponse({"status": "fail"}, status=400)

    user = User.objects.filter(username=email).first()
    if user is None or not user.is_active:
        cache.set(throttle_key, attempts + 1, timeout=60 * 10)
        return JsonResponse({"status": "fail"}, status=401)

    auth_user = authenticate(request, username=email, password=secret)
    if auth_user is None:
        profile = _get_or_create_profile(user)
        if not profile.pin_hash or not check_password(secret, profile.pin_hash):
            cache.set(throttle_key, attempts + 1, timeout=60 * 10)
            return JsonResponse({"status": "fail"}, status=401)
        auth_user = user

    profile = _get_or_create_profile(auth_user)
    if profile.email_verified_at is None:
        cache.set(throttle_key, attempts + 1, timeout=60 * 10)
        return JsonResponse({"status": "fail"}, status=403)

    login(request, auth_user)
    cache.delete(throttle_key)
    return JsonResponse({"status": "ok"})


@require_POST
def api_auth_set_credentials(request: HttpRequest) -> JsonResponse:
    if not request.user.is_authenticated:
        return JsonResponse({"status": "fail"}, status=401)

    profile = _get_or_create_profile(request.user)
    if profile.email_verified_at is None:
        return JsonResponse({"status": "fail"}, status=403)

    data = _parse_json(request)
    password = data.get("password") or ""
    pin = data.get("pin") or ""
    if not password:
        return JsonResponse({"status": "fail"}, status=400)

    request.user.password = make_password(password)
    request.user.save(update_fields=["password"])

    profile.pin_hash = make_password(pin) if pin else None
    profile.save(update_fields=["pin_hash"])

    login(
        request,
        request.user,
        backend="django.contrib.auth.backends.ModelBackend",
    )
    return JsonResponse({"status": "ok"})


@require_POST
def api_auth_logout(request: HttpRequest) -> JsonResponse:
    logout(request)
    return JsonResponse({"status": "ok"})


@require_GET
def api_auth_me(request: HttpRequest) -> JsonResponse:
    if not request.user.is_authenticated:
        return JsonResponse({"authenticated": False})

    profile = _get_or_create_profile(request.user)
    return JsonResponse(
        {
            "authenticated": True,
            "email_verified": profile.email_verified_at is not None,
            "has_passkey": request.user.webauthn_credentials.exists(),
            "has_password": request.user.has_usable_password(),
            "has_pin": bool(profile.pin_hash),
        }
    )


@require_POST
def api_webauthn_register_begin(request: HttpRequest) -> JsonResponse:
    if not _FIDO2_AVAILABLE:
        return JsonResponse({"status": "fail", "code": "webauthn_unavailable"}, status=503)

    if not request.user.is_authenticated:
        return JsonResponse({"status": "fail"}, status=401)

    profile = _get_or_create_profile(request.user)
    if profile.email_verified_at is None:
        return JsonResponse({"status": "fail"}, status=403)

    server = _get_fido_server(request)
    user_handle = profile.ensure_webauthn_user_id()
    user_entity = PublicKeyCredentialUserEntity(
        id=user_handle, name=request.user.username, display_name=request.user.username
    )
    existing = [
        AttestedCredentialData(bytes(c.credential_data))
        for c in request.user.webauthn_credentials.all()
    ]
    options, state = server.register_begin(
        user_entity,
        credentials=existing,
        resident_key_requirement=ResidentKeyRequirement.PREFERRED,
        user_verification=UserVerificationRequirement.PREFERRED,
    )
    request.session["webauthn_register_state"] = state
    return JsonResponse(dict(options))


@require_POST
def api_webauthn_register_complete(request: HttpRequest) -> JsonResponse:
    if not _FIDO2_AVAILABLE:
        return JsonResponse({"status": "fail", "code": "webauthn_unavailable"}, status=503)

    if not request.user.is_authenticated:
        return JsonResponse({"status": "fail"}, status=401)

    state = request.session.pop("webauthn_register_state", None)
    if not state:
        return JsonResponse({"status": "fail"}, status=400)

    data = _parse_json(request)
    server = _get_fido_server(request)
    try:
        auth_data = server.register_complete(state, data)
    except Exception:
        return JsonResponse({"status": "fail"}, status=400)

    if auth_data.credential_data is None:
        return JsonResponse({"status": "fail"}, status=400)

    credential_id = auth_data.credential_data.credential_id
    credential_data = bytes(auth_data.credential_data)
    existing = WebAuthnCredential.objects.filter(credential_id=credential_id).first()
    if existing and existing.user_id != request.user.id:
        return JsonResponse({"status": "fail"}, status=400)
    if not existing:
        WebAuthnCredential.objects.create(
            user=request.user,
            credential_id=credential_id,
            credential_data=credential_data,
        )
    return JsonResponse({"status": "ok"})


@require_POST
def api_webauthn_auth_begin(request: HttpRequest) -> JsonResponse:
    if not _FIDO2_AVAILABLE:
        return JsonResponse({"status": "fail", "code": "webauthn_unavailable"}, status=503)

    server = _get_fido_server(request)
    options, state = server.authenticate_begin(
        user_verification=UserVerificationRequirement.PREFERRED
    )
    request.session["webauthn_auth_state"] = state
    return JsonResponse(dict(options))


@require_POST
def api_webauthn_auth_complete(request: HttpRequest) -> JsonResponse:
    if not _FIDO2_AVAILABLE:
        return JsonResponse({"status": "fail", "code": "webauthn_unavailable"}, status=503)

    state = request.session.pop("webauthn_auth_state", None)
    if not state:
        return JsonResponse({"status": "fail"}, status=400)

    data = _parse_json(request)
    raw_id = data.get("rawId") or data.get("id")
    if not raw_id:
        return JsonResponse({"status": "fail"}, status=400)

    try:
        credential_id = websafe_decode(raw_id)
    except Exception:
        return JsonResponse({"status": "fail"}, status=400)

    credential = (
        WebAuthnCredential.objects.select_related("user")
        .filter(credential_id=credential_id)
        .first()
    )
    if credential is None or not credential.user.is_active:
        return JsonResponse({"status": "fail"}, status=401)

    server = _get_fido_server(request)
    stored = AttestedCredentialData(bytes(credential.credential_data))
    try:
        server.authenticate_complete(state, [stored], data)
    except Exception:
        return JsonResponse({"status": "fail"}, status=401)

    login(
        request,
        credential.user,
        backend="django.contrib.auth.backends.ModelBackend",
    )
    credential.last_used_at = timezone.now()
    credential.save(update_fields=["last_used_at"])
    return JsonResponse({"status": "ok"})


def _file_size(uploaded_file) -> int:
    try:
        return int(uploaded_file.size)
    except Exception:
        return 0


def _delete_field_file(field_file) -> None:
    if not field_file:
        return
    try:
        logger.info(f"Deleting old file: {field_file.name}")
        field_file.delete(save=False)
    except Exception as e:
        logger.error(f"Failed to delete file {field_file.name}: {e}")


def _get_or_create_user_share(user) -> UserShareState:
    share, _ = UserShareState.objects.get_or_create(user=user)
    return share


def _get_or_create_public_share() -> PublicShareState:
    share, _ = PublicShareState.objects.get_or_create(pk=1)
    return share


def _maybe_expire_share(*, share, ttl_seconds: int) -> None:
    if ttl_seconds <= 0:
        return
    if share.updated_at >= timezone.now() - timezone.timedelta(seconds=ttl_seconds):
        return

    if share.file:
        _delete_field_file(share.file)
    share.file = None
    share.text = None
    share.save(update_fields=["file", "text", "updated_at"])


@require_POST
def upload_view(request: HttpRequest) -> JsonResponse:
    is_public = not request.user.is_authenticated
    if is_public:
        ip = _client_ip(request)
        throttle_key = f"dshare:public_upload:{ip}"
        attempts = cache.get(throttle_key, 0)
        if attempts >= int(getattr(settings, "DSHARE_PUBLIC_UPLOAD_LIMIT", 100)):
            return JsonResponse({"status": "fail"}, status=429)
        cache.set(throttle_key, attempts + 1, timeout=60 * 10)

    max_bytes = int(
        getattr(
            settings,
            "DSHARE_PUBLIC_MAX_UPLOAD_BYTES" if is_public else "DSHARE_USER_MAX_UPLOAD_BYTES",
            10 * 1024 * 1024,
        )
    )
    ttl_seconds = int(
        getattr(
            settings,
            "DSHARE_PUBLIC_TTL_SECONDS" if is_public else "DSHARE_USER_TTL_SECONDS",
            86400 if is_public else 86400 * 30,
        )
    )

    share = _get_or_create_public_share() if is_public else _get_or_create_user_share(request.user)
    _maybe_expire_share(share=share, ttl_seconds=ttl_seconds)

    if "file" in request.FILES:
        uploaded_file = request.FILES["file"]
        if _file_size(uploaded_file) > max_bytes:
            return JsonResponse({"status": "fail"}, status=413)

        if share.file:
            _delete_field_file(share.file)
        share.file = uploaded_file
        share.text = None
        share.save(update_fields=["file", "text", "updated_at"])
        return JsonResponse({"status": "ok"})

    text = request.POST.get("text")
    if text is not None:
        share.text = text
        if share.file:
            _delete_field_file(share.file)
        share.file = None
        share.save(update_fields=["file", "text", "updated_at"])
        return JsonResponse({"status": "ok"})

    return JsonResponse({"status": "fail"}, status=400)


@require_GET
def download_view(request: HttpRequest) -> HttpResponse:
    is_public = not request.user.is_authenticated
    ttl_seconds = int(
        getattr(
            settings,
            "DSHARE_PUBLIC_TTL_SECONDS" if is_public else "DSHARE_USER_TTL_SECONDS",
            86400 if is_public else 86400 * 30,
        )
    )
    share = _get_or_create_public_share() if is_public else _get_or_create_user_share(request.user)
    _maybe_expire_share(share=share, ttl_seconds=ttl_seconds)

    if share.file:
        return redirect(share.file.url)

    if share.text:
        return HttpResponse(share.text, content_type="text/plain")

    return JsonResponse({"status": "empty"})


@require_GET
def api_share_text(request: HttpRequest) -> JsonResponse:
    is_public = not request.user.is_authenticated
    ttl_seconds = int(
        getattr(
            settings,
            "DSHARE_PUBLIC_TTL_SECONDS" if is_public else "DSHARE_USER_TTL_SECONDS",
            86400 if is_public else 86400 * 30,
        )
    )
    share = _get_or_create_public_share() if is_public else _get_or_create_user_share(request.user)
    _maybe_expire_share(share=share, ttl_seconds=ttl_seconds)
    return JsonResponse({"text": share.text or ""})


@require_POST
def api_share_clear(request: HttpRequest) -> JsonResponse:
    is_public = not request.user.is_authenticated
    if is_public:
        ip = _client_ip(request)
        throttle_key = f"dshare:public_clear:{ip}"
        attempts = cache.get(throttle_key, 0)
        if attempts >= int(getattr(settings, "DSHARE_PUBLIC_CLEAR_LIMIT", 100)):
            return JsonResponse({"status": "fail"}, status=429)
        cache.set(throttle_key, attempts + 1, timeout=60 * 10)

    share = _get_or_create_public_share() if is_public else _get_or_create_user_share(request.user)
    if share.file:
        _delete_field_file(share.file)
    share.file = None
    share.text = None
    share.save(update_fields=["file", "text", "updated_at"])
    return JsonResponse({"status": "ok"})
