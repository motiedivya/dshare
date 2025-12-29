---
title: Security
---

# Security

## Public mode

Public mode is intentionally “truly public”: anyone who can access the URL can upload/download/clear the public slot.

This is convenient, but risky.

### Risks

- overwriting your public slot
- spam uploads / spam clears
- illegal content uploads

### Mitigations

- keep public TTL short (`DSHARE_PUBLIC_TTL_SECONDS`)
- keep file size small (`DSHARE_PUBLIC_MAX_UPLOAD_BYTES`)
- keep throttle limits low (`DSHARE_PUBLIC_UPLOAD_LIMIT`, `DSHARE_PUBLIC_CLEAR_LIMIT`)
- deploy behind a WAF / Cloudflare
- consider access restriction (VPN, IP allowlist, basic auth at reverse proxy)

## Private mode

Private mode isolates stored content per verified user, and sessions last ~30 days by default.

Note: DShare is not end‑to‑end encrypted; the server can see files/text.
