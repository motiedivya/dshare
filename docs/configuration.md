---
title: Configuration
---

# Configuration

## `.env`

For local/dev convenience, DShare loads `.env` automatically (it does not override existing environment variables).

Copy `.env.example` to `.env` and fill in secrets.

## Django basics (production)

At minimum, set:

- `DJANGO_SECRET_KEY`
- `DJANGO_DEBUG=0`
- `DJANGO_ALLOWED_HOSTS=yourdomain.com`

## Email (Resend SMTP)

Example env vars:

```bash
DJANGO_EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST=smtp.resend.com
EMAIL_PORT=587
EMAIL_USE_TLS=1
EMAIL_HOST_USER=resend
EMAIL_HOST_PASSWORD=YOUR_RESEND_API_KEY
DEFAULT_FROM_EMAIL=do-not-reply@divyeshvishwakarma.com
```

## Retention / limits

- `DSHARE_USER_TTL_SECONDS` (default 30 days)
- `DSHARE_PUBLIC_TTL_SECONDS` (default 1 day)
- `DSHARE_USER_MAX_UPLOAD_BYTES` (default 50 MB)
- `DSHARE_PUBLIC_MAX_UPLOAD_BYTES` (default 10 MB)
- `DSHARE_PUBLIC_UPLOAD_LIMIT` (per 10 minutes per IP)
- `DSHARE_PUBLIC_CLEAR_LIMIT` (per 10 minutes per IP)

## Passkeys (WebAuthn)

Passkeys require HTTPS in production.

Set `DSHARE_RP_ID` to your domain:

```bash
DSHARE_RP_ID=yourdomain.com
```

Locally, use `DSHARE_RP_ID=localhost` and open `http://localhost:8000/` (not `127.0.0.1`).

## Admin bootstrap

If you set these env vars, DShare will create a Django superuser on `python manage.py migrate` (only if that username does not already exist):

- `DSHARE_SUPERADMIN_USERNAME`
- `DSHARE_SUPERADMIN_PASSWORD`
- `DSHARE_SUPERADMIN_EMAIL` (optional)
