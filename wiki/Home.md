# DShare Wiki

DShare is a keyboard-first sharing tool:

- Type `divya` → upload (file or clipboard)
- Type `moti` → download/view the latest stored content

Those two keywords are global aliases and intended to never change.

## Quick start

### Public (guest)

1. Open the site.
2. Type `divya` to upload a file, or type `/paste` to upload clipboard text.
3. On another device, open the site and type `moti`.

Public mode is world-writable; read `Security`.

### Private (accounts)

1. Type `/register`, enter your email + password, optionally set a PIN fallback.
2. Click the verification email link once.
3. You now stay logged in for ~30 days by default. Just type `divya` / `moti`.

Optional: type `/passkey` once to add a passkey. After that, `/login` will prefer passkeys automatically.

## Mobile gestures

- Tap the logo (top-left) or long-press anywhere → Actions (login/logout/etc.)
- Swipe ↑ upload, ↓ download, ← copy latest text, → paste clipboard text
- Type `/docs` to open docs: https://docs.dshare.me

## How DShare stores data

DShare is designed around “one latest thing”:

- Public mode: one global slot (latest file or latest text)
- Private mode: one slot per user (latest file or latest text)

There is no built-in history UI by design.

## Where to go next

- Docs: https://docs.dshare.me

- `Commands` — full command reference
- `Security` — threat model and public mode risks
- `Email` — Resend SMTP setup
- `Passkeys` — WebAuthn requirements and troubleshooting
- `Deployment` — production checklist
