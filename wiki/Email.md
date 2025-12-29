# Email (Resend SMTP)

## Setup steps

1. Verify your sending domain in Resend (`divyeshvishwakarma.com`) and complete DNS records (DKIM/SPF as Resend shows).
2. Create a Resend API key.
3. Configure env vars:

```bash
DJANGO_EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST=smtp.resend.com
EMAIL_PORT=587
EMAIL_USE_TLS=1
EMAIL_HOST_USER=resend
EMAIL_HOST_PASSWORD=YOUR_RESEND_API_KEY
DEFAULT_FROM_EMAIL=do-not-reply@divyeshvishwakarma.com
```

4. Restart the server.
5. Type `/register` on the DShare home page.

## Local testing

Run a one-liner test:

```bash
python manage.py shell -c "from django.core.mail import send_mail; send_mail('DShare test','ok',None,['you@example.com'])"
```

If it prints the email to the console instead of sending, you’re still using the console email backend.

## Troubleshooting

- `sent` toast but no email: check Resend logs and spam folder; ensure domain is verified.
- `fail` toast: check server logs (SMTP auth, TLS, port).
- Wrong From address: ensure `DEFAULT_FROM_EMAIL` is set and the sender is verified in Resend.

## Styling note

The verification email HTML is intentionally “stealth” (black-on-black) to match DShare’s theme. Some clients override colors; the link should still be clickable (the body is one big link).

