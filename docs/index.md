# DShare

Type-to-share <span class="redacted">TOP SECRET</span> files and clipboard text.

**Never-changing muscle memory**

- Type `divya` → upload (file or clipboard via `/paste`)
- Type `moti` → download/view the latest stored content

## Quick start

### Public (guest) mode

1. Open the site.
2. Type `divya` and upload a file (or type `/paste`).
3. On another <span class="redacted">DEVICE</span>, open the site and type `moti`.

### Mobile gestures (no keyboard needed)

- Tap the logo (top-left) or long-press anywhere → Actions (login/logout/etc.)
- Swipe ↑ upload, ↓ download, ← copy latest text, → paste clipboard text
- Type `/docs` to open `docs.dshare.me`

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
- `/docs` — open docs (`docs.dshare.me`)

## Security note

Public mode is <span class="redacted">WORLD-WRITABLE</span>. If you deploy DShare to the open internet, expect abuse unless you add external controls (WAF, rate limiting, allowlists, VPN).

Read the repo `README.md` for the full security model, configuration, and production checklist.
