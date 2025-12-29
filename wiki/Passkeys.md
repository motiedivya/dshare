# Passkeys (WebAuthn)

## Why passkeys

Passkeys are:

- phishing-resistant
- fast (FaceID/TouchID/Windows Hello)
- easier than passwords once set up

DShare uses passkeys as the preferred login method when you type `/login`.

## Requirements

- Production: HTTPS
- Local: most browsers treat `http://localhost` as a secure context

## RP ID (domain binding)

Passkeys are bound to an RP ID (domain).

- Set `DSHARE_RP_ID=yourdomain.com` in production.
- For local testing: `DSHARE_RP_ID=localhost` and use `http://localhost:8000/`.

If you use `127.0.0.1`, passkeys may fail depending on the browser.

## How to use

1. `/register` → verify email once
2. Type `/passkey` to register a passkey
3. Later, type `/login` on a new device/browser

## Troubleshooting

- Passkey prompt never appears: ensure you’re on HTTPS (or localhost).
- “Invalid origin” errors: check `DSHARE_RP_ID` matches your domain.
- Using a reverse proxy: ensure the app sees the correct host (and scheme).

