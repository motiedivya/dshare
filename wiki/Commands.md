# Commands

All commands are typed directly on the home page. There are no “settings pages” by design.

## Keyword triggers

| Trigger | Action |
|---|---|
| `divya` | Reveal upload UI (file upload + paste button) |
| `moti` | Download/view the latest stored file/text for the current lane |

## Slash commands

Commands start with `/` (or `\` as an alias). They are detected as you type.

| Command | Requires login? | What it does |
|---|---:|---|
| `/help` | no | Shows a small cheat sheet |
| `/status` / `/me` | no | Shows `public` or `private` |
| `/register` | no | Creates/updates an account and sends a verification email |
| `/login` | no | Logs in (passkey first; PIN/password fallback) |
| `/logout` | yes | Logs out |
| `/passkey` | yes | Registers a passkey (WebAuthn) |
| `/paste` | no | Uploads clipboard text |
| `/copy` | no | Copies stored text to clipboard |
| `/clear` | no | Clears stored file/text (+ attempts clipboard clear) |

## Subtle feedback

DShare tries to give minimal hints:

- a short toast in the center (`ok`, `sent`, `fail`, `public`, `private`)
- a faint `PUBLIC` watermark when not logged in

If something fails:

- `/status` tells you which lane you’re in
- check server logs for details (SMTP errors, etc.)

