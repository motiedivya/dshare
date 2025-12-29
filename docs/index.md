---
title: DShare
---

# DShare

Type-to-share files and clipboard text.

**Never-changing muscle memory**

- Type `divya` → upload (file or clipboard via `/paste`)
- Type `moti` → download/view the latest stored content

## Quick start

### Public (guest) mode

1. Open the site.
2. Type `divya` and upload a file (or type `/paste`).
3. On another device, open the site and type `moti`.

### Private mode (recommended)

1. Type `/register` and enter your email + password (+ optional PIN fallback).
2. Click the verification email link once.
3. From then on, just visit the site and type `divya` / `moti` (your session lasts ~30 days by default).

Optional: type `/passkey` once to add a passkey; `/login` prefers passkeys automatically.

## Commands

- `divya` — upload
- `moti` — download/view
- `/register` — create account (sends verification email)
- `/login` — login (passkey first; password/PIN fallback)
- `/logout` — logout
- `/passkey` — add passkey (WebAuthn)
- `/status` — shows `public` or `private`
- `/paste` — upload clipboard text
- `/copy` — copy stored text to clipboard
- `/clear` — clear stored file/text (+ attempts clipboard clear)

## Security note

Public mode is world-writable. If you deploy DShare to the open internet, expect abuse unless you add external controls (WAF, rate limiting, allowlists, VPN).

Read the repo `README.md` for the full security model, configuration, and production checklist.
