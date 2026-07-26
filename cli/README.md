# dshare-cli

A cross-platform command-line client for [dShare](https://docs.dshare.me) — the
same 10-second "public share" flow as typing `divya` / `moti` on the web UI,
from a terminal on Linux, macOS, or Windows.

It talks to your dShare server's existing public endpoints (`/upload/`,
`/download/`, `/api/share/clear/`) — no server changes required, and it
doesn't touch private/login-based sharing.

## Install

Requires Python 3.9+ (any OS). [pipx](https://pipx.pypa.io/) is recommended
since it keeps the CLI's dependencies isolated:

```bash
pipx install "git+https://github.com/motiedivya/dshare.git#subdirectory=cli"
```

Or with plain pip:

```bash
pip install "git+https://github.com/motiedivya/dshare.git#subdirectory=cli"
```

For local development (from a clone of this repo):

```bash
cd cli
pip install -e .
```

All three commands work identically on Windows (PowerShell/cmd), macOS, and
Linux — the CLI has no shell scripts and no OS-specific setup steps.

Once published to PyPI, the same command becomes `pipx install dshare-cli`.

## Setup

Point the CLI at your dShare server once:

```bash
dshare config https://your-dshare-host.example.com
```

This is saved to a per-OS config file (`~/.config/dshare/config.json` on
Linux, `~/Library/Application Support/dshare/config.json` on macOS,
`%APPDATA%\dshare\config.json` on Windows). You can override it per-command
with `--server`, or via the `DSHARE_SERVER` environment variable — handy for
CI or scripting.

## Usage

Upload a file (same as typing `divya` and picking a file):

```bash
dshare send report.pdf
```

Upload text (same as `/paste`):

```bash
dshare send --text "some text to move between devices"
echo "some text" | dshare send      # piping works too
```

Download the latest shared file or text (same as typing `moti`):

```bash
dshare receive
```

- If the slot holds a file, it's saved to the current directory (or `-o/--output`).
- If the slot holds text, it's printed to stdout — so `dshare receive > out.txt`
  or `dshare receive | pbcopy` / `| clip` works.
- If stdout isn't a terminal, file bytes stream straight to stdout too (like `curl`).

Clear the slot (same as `/clear`):

```bash
dshare clear
```

Check what server you're pointed at and whether it's reachable:

```bash
dshare status
```

`divya` and `moti` also work as aliases for `send`/`receive`, matching the
web UI's keywords:

```bash
dshare divya report.pdf
dshare moti
```

## Notes

- This CLI only uses the **public** lane (the same one anonymous visitors to
  the web UI get) — it does not log in or touch private per-user slots.
- Self-signed/local server? Pass `--insecure` to skip TLS verification.
- Exit codes: `0` success, `1` error, `2` the slot was empty on `receive`.
