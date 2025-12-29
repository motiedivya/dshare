# Security

## Mental model

DShare is a convenience “transfer slot”, not a secure vault.

- The server can read stored files/text.
- Public mode is world-writable.
- Private mode isolates by account, not by encryption.

## Public mode (guest)

Public mode means:

- anyone can upload (overwrite)
- anyone can clear
- anyone can download the latest thing

### Risks

- abuse (spam uploads, spam clears)
- illegal content uploads (you become the host)
- surprise overwrites

### Built-in guardrails (still not a WAF)

DShare includes:

- public upload size limits (`DSHARE_PUBLIC_MAX_UPLOAD_BYTES`)
- public retention (`DSHARE_PUBLIC_TTL_SECONDS`)
- simple per-IP throttles (`DSHARE_PUBLIC_UPLOAD_LIMIT`, `DSHARE_PUBLIC_CLEAR_LIMIT`)

### Strongly recommended in production

If you deploy a public URL:

- put DShare behind Cloudflare/WAF
- add rate limiting at the edge
- consider IP allowlists / VPN if your use-case allows
- keep public TTL short (hours, not days)
- keep upload limits small

## Accounts (private mode)

Accounts are meant to give you:

- per-user isolation
- retention (default 30 days)
- passkeys for convenient, secure re-login

### Email verification

Verification is one-time:

- `/register` sends a signed link
- clicking it verifies + logs in
- sessions are long-lived (default 30 days)

### Passkeys

Passkeys are preferred for future login because they’re phishing-resistant.

## What DShare does not do

- malware scanning
- content moderation
- end-to-end encryption

If you need any of those, add an external service or don’t run public mode.

