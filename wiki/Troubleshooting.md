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

## “Public mode is getting abused”

If you must stay public:

- reduce `DSHARE_PUBLIC_MAX_UPLOAD_BYTES`
- reduce `DSHARE_PUBLIC_TTL_SECONDS`
- reduce `DSHARE_PUBLIC_UPLOAD_LIMIT` / `DSHARE_PUBLIC_CLEAR_LIMIT`
- add edge rate limiting / WAF (Cloudflare)

If you can, restrict access (VPN / allowlist).

