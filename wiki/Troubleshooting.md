# Troubleshooting

## “I don’t know if I’m logged in”

Type `/status` (or `/me`):

- `private` means logged in
- `public` means logged out

Also, the faint `PUBLIC` watermark indicates public mode.

## `/register` says `sent` but no email arrives

- Ensure you are using the SMTP backend (`DJANGO_EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend`).
- Check Resend dashboard logs and spam folder.
- Ensure your domain and sender are verified.

## `/register` says `fail`

Check server logs: usually SMTP auth/TLS/port issues.

## Passkeys fail or don’t prompt

- Use HTTPS in production.
- Locally use `http://localhost:8000/` and set `DSHARE_RP_ID=localhost`.
- Don’t use `127.0.0.1` for passkeys.

## Building your own API client and every POST gets 403

Django's CSRF middleware requires an `Origin`/`Referer` header on HTTPS POST
requests (it only skips that check over plain HTTP, which is why it's easy
to miss in local testing). To POST to `/upload/`, `/api/share/clear/`, etc.
from a script:

1. `GET /` first and keep the `csrftoken` cookie (set via a session/cookie jar).
2. Send it back as an `X-CSRFToken` header on POSTs.
3. Also set `Origin`/`Referer` to your target server's own URL.

[`dshare-cli`](CLI) does all three — its [`client.py`](https://github.com/motiedivya/dshare/blob/main/cli/src/dshare_cli/client.py)
is a working reference if you're implementing this yourself.

## “Public mode is getting abused”

If you must stay public:

- reduce `DSHARE_PUBLIC_MAX_UPLOAD_BYTES`
- reduce `DSHARE_PUBLIC_TTL_SECONDS`
- reduce `DSHARE_PUBLIC_UPLOAD_LIMIT` / `DSHARE_PUBLIC_CLEAR_LIMIT`
- add edge rate limiting / WAF (Cloudflare)

If you can, restrict access (VPN / allowlist).

