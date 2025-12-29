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
- run `python manage.py collectstatic` if you serve static assets separately

## Public mode

If you keep public mode enabled on the open internet:

- set tight limits (`DSHARE_PUBLIC_*`)
- put a WAF in front of it
- be prepared for abuse

## PythonAnywhere notes

PythonAnywhere is workable, but passkeys require a proper HTTPS domain and stable `DSHARE_RP_ID`.

