# Deployment

## Recommended baseline

- HTTPS (required for passkeys)
- reverse proxy (nginx / Caddy) or platform that terminates TLS
- environment variables set in the host platform (don’t rely on `.env` in production)

## Production checklist

- set a secure `SECRET_KEY`
- set `DEBUG=False`
- set `ALLOWED_HOSTS` to your domains
- consider:
  - `SESSION_COOKIE_SECURE=True`
  - `CSRF_COOKIE_SECURE=True`
  - `SECURE_PROXY_SSL_HEADER` if behind a proxy

## Static and media files

DShare stores uploaded files under `MEDIA_ROOT`.

For most deployments:

- map `/media/` to your `media/` folder
- run `python manage.py collectstatic` before serving in production — the
  homepage renders `{% static %}` tags (logo/favicon), so without this the
  homepage 500s once `DEBUG=False`. The `Procfile` runs this (plus `migrate`)
  automatically on every boot for Procfile-based platforms; other platforms
  need it run manually as part of your deploy steps.

## Railway

DShare deploys to Railway with no extra config — it auto-detects the
`Procfile` + `runtime.txt` via Nixpacks.

1. New Project → Deploy from GitHub repo.
2. Add a **PostgreSQL** plugin (Railway sets `DATABASE_URL`; `dj-database-url`
   in `requirements.txt` picks it up automatically).
3. Set env vars: `DJANGO_SECRET_KEY`, `DJANGO_DEBUG=0`, `DJANGO_ALLOWED_HOSTS`
   (your `*.up.railway.app` domain or custom domain), `DSHARE_RP_ID` (same
   domain, required for passkeys), plus email vars — see `.env.example`.
   `CSRF_TRUSTED_ORIGINS` already whitelists `*.railway.app`/`*.up.railway.app`
   by default.
4. Deploy. The `Procfile`'s `collectstatic && migrate && gunicorn` boot
   sequence handles the rest — including bootstrapping an admin user if
   `DSHARE_SUPERADMIN_USERNAME`/`PASSWORD` are set.
5. Watch the build logs for the `collectstatic`/`migrate` lines to confirm
   they ran before assuming a blank/broken homepage is something else.

## Public mode

If you keep public mode enabled on the open internet:

- set tight limits (`DSHARE_PUBLIC_*`)
- put a WAF in front of it
- be prepared for abuse

## PythonAnywhere notes

PythonAnywhere is workable, but there are a couple of sharp edges:

- Use a virtualenv (Web tab → Virtualenv) and install deps: `pip install -r requirements.txt` (includes `fido2` for passkeys).
- Run DB migrations after every deploy: `python manage.py migrate` (otherwise you’ll see `no such table` / `no such column` errors).
- Free accounts can’t use arbitrary SMTP (so Resend SMTP will fail); use Gmail SMTP (allowed) or an HTTP-based provider like SendGrid/Mailgun, or upgrade for unrestricted internet access.
- Passkeys require HTTPS and `DSHARE_RP_ID` must match your domain (eg `dshare.pythonanywhere.com`).
