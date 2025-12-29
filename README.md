# DShare — type-to-share (files + clipboard)

DShare is a minimal, keyboard-first file/text sharing tool built with Django.

You don’t “navigate” the UI: you type keywords.

- Type `divya` → upload a file or paste clipboard text
- Type `moti` → download the latest file or view the latest text

Those two keywords are treated as global aliases and are intended to never change.

This repo also adds optional accounts (one-time email verification + 30‑day session retention) with passkeys (WebAuthn) preferred and PIN/password as a fallback.

---

## Table of contents

- [What this is](#what-this-is)
- [How it feels to use](#how-it-feels-to-use)
- [Commands](#commands)
- [Public vs Private mode](#public-vs-private-mode)
- [Security model (read this)](#security-model-read-this)
- [Retention & cleanup](#retention--cleanup)
- [Local setup](#local-setup)
- [Email setup (Resend SMTP)](#email-setup-resend-smtp)
- [Passkeys (WebAuthn)](#passkeys-webauthn)
- [Production checklist](#production-checklist)
- [GitHub Pages & Wiki](#github-pages--wiki)

---

## What this is

DShare is for “I need to move a file / a chunk of text between two devices right now”:

- phone ↔ laptop
- home PC ↔ work PC
- VM ↔ host
- any two devices that can open a URL

It’s intentionally *not* a chat app, not a drive, and not end‑to‑end encrypted storage.

It has one core idea:

> The homepage is a blank-ish screen where typing triggers actions.

---

## How it feels to use

### 10‑second public share

1. Open the site on device A.
2. Type `divya` → choose a file (or type `/paste` to upload clipboard text).
3. Open the site on device B.
4. Type `moti` → it downloads the latest public file or shows the latest public text.

### Private share (same flow, but per-user)

1. Type `/register` and enter your email (and optional PIN/password fallback).
2. Click the verification email link once (verifies + logs in).
3. From then on, just open the site and type `divya` / `moti`.

If you ever get logged out (new browser/device), type `/login`:

- tries passkey first (if you added one)
- falls back to email + PIN/password

---

## Commands

All commands are typed directly on the home page (no input fields).

| Command | What it does |
|---|---|
| `divya` | Reveals the upload section |
| `moti` | Downloads/views the latest stored file/text |
| `/register` | Create account (email verification sent) |
| `/login` | Log in (passkey first; PIN/password fallback) |
| `/logout` | Log out |
| `/passkey` | Add a passkey (requires you to be logged in + email verified) |
| `/paste` | Upload clipboard text |
| `/copy` | Copy latest stored text to clipboard |
| `/clear` | Clear stored file/text (and attempts to clear clipboard) |
| `/status` (or `/me`) | Tells you if you’re in `public` or `private` mode |
| `/help` | Quick cheat sheet |

Notes:

- Commands can also start with `\` (alias).
- If you see a faint `PUBLIC` watermark, you’re not logged in (public mode).

---

## Public vs Private mode

DShare has two “lanes” that share the exact same `divya`/`moti` muscle memory:

### Public mode (guest)

- Anyone who can reach your URL can overwrite the public slot.
- Useful for quick, no-login transfers.
- **Dangerous if deployed to the open internet without constraints.**

Public defaults:

- shorter retention (default 1 day)
- smaller upload limit (default 10 MB)
- simple per-IP throttling (to reduce abuse)

### Private mode (logged in)

- Each verified user gets a private “slot”.
- Retention defaults to 30 days.
- Still not “secure storage” — it’s a convenience slot for recent transfer.

---

## Security model (read this)

### What DShare protects well

- **No password needed for everyday use:** once verified, you typically stay logged in for ~30 days (sliding session).
- **Passkeys are the primary login method:** phishing-resistant and easy.
- **Private shares are isolated per user.**

### What DShare does *not* protect you from

- **Server operator can see your uploads/text** (this is not end‑to‑end encrypted).
- **Public mode is world-writable.**
- **The “latest upload wins”** — there’s no history UI by design.

### Public mode risks (realistic)

If you run DShare on a public URL, anonymous users can:

- upload illegal or malicious files
- overwrite your public slot
- attempt denial-of-service (upload spam, clear spam)

Mitigations you can enable even while remaining “public”:

- keep the upload size limit small (`DSHARE_PUBLIC_MAX_UPLOAD_BYTES`)
- keep public retention short (`DSHARE_PUBLIC_TTL_SECONDS`)
- keep rate limits low (`DSHARE_PUBLIC_UPLOAD_LIMIT`, `DSHARE_PUBLIC_CLEAR_LIMIT`)
- deploy behind Cloudflare / WAF / rate limiting
- restrict access by IP if you can (VPN, Tailscale, allowlists)

If you truly need “public for everyone in the world”, treat it like running a public pastebin/filedrop: you’ll need strong external controls.

---

## Retention & cleanup

- Public data is auto-expired after `DSHARE_PUBLIC_TTL_SECONDS` (default 1 day).
- Private data is auto-expired after `DSHARE_USER_TTL_SECONDS` (default 30 days).
- Expiry happens lazily (on access/upload) to avoid cron requirements.
- `/clear` clears the current lane (public if logged out, private if logged in).

---

## Local setup

### Requirements

- Python 3.10+

### Install

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

Open `http://localhost:8000/` (prefer `localhost` over `127.0.0.1` if you plan to test passkeys).

### Local `.env`

This repo loads `.env` automatically in `dshare/settings.py`, for local/dev convenience.

Copy `.env.example` to `.env` and fill values as needed.

---

## Email setup (Resend SMTP)

If you have Resend and a sender like `do-not-reply@divyeshvishwakarma.com`:

1. In Resend, verify your domain `divyeshvishwakarma.com` (DNS DKIM/SPF as Resend shows).
2. Create a Resend API key.
3. Set env vars (example):

```bash
DJANGO_EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST=smtp.resend.com
EMAIL_PORT=587
EMAIL_USE_TLS=1
EMAIL_HOST_USER=resend
EMAIL_HOST_PASSWORD=YOUR_RESEND_API_KEY
DEFAULT_FROM_EMAIL=do-not-reply@divyeshvishwakarma.com
```

Then type `/register` on the home page.

Email styling note: the verification email HTML is intentionally “stealth” (black-on-black) to match the theme. Some email clients override colors; the link should still be clickable (the message body is one big link).

---

## Passkeys (WebAuthn)

Passkeys are the preferred login method:

- phishing-resistant
- no password reuse
- fast login on new devices

### Requirements

- HTTPS in production
- for local dev: `http://localhost` is treated as a secure context by most browsers

### RP ID (important)

WebAuthn binds credentials to an RP ID (domain). Set:

```bash
DSHARE_RP_ID=yourdomain.com
```

Locally, use `DSHARE_RP_ID=localhost` and open `http://localhost:8000/`.

### Usage

- After verifying email, type `/passkey` once to register a passkey.
- Later, `/login` will try passkey first automatically.

---

## Production checklist

If you deploy DShare publicly, do these first:

- run behind HTTPS
- set a real `SECRET_KEY`
- set `DEBUG=False`
- set `ALLOWED_HOSTS` to your domain(s)
- consider secure cookie flags:
  - `SESSION_COOKIE_SECURE=True`
  - `CSRF_COOKIE_SECURE=True`
  - `SESSION_COOKIE_SAMESITE='Lax'` (or `'Strict'` depending on your needs)
- configure static files for Django (`collectstatic`) if you serve your own assets
- decide whether you truly want public mode enabled

Also consider putting DShare behind a reverse proxy (nginx) and/or Cloudflare for rate limiting.

---

## GitHub Pages & Wiki

This repo includes docs scaffolding:

- GitHub Pages content lives in `docs/`
- Wiki-ready markdown pages live in `wiki/`

### Enable GitHub Pages

1. Push this repo to GitHub.
2. Go to **Settings → Pages**.
3. Choose **Deploy from a branch** → select `main` and `/docs`.

### Use the Wiki pages

GitHub Wikis are separate git repos.

1. Enable **Wiki** in your GitHub repo settings.
2. Clone the wiki repo (GitHub shows the URL in the Wiki tab).
3. Copy files from `wiki/` into that wiki repo and push.
