---
title: CLI
---

# CLI

`dshare-cli` — cross-platform (Linux/macOS/Windows) command-line client for the same
public `divya`/`moti` flow, published on [PyPI](https://pypi.org/project/dshare-cli/).

## Install

```bash
pipx install dshare-cli   # or: pip install dshare-cli
```

Requires Python 3.9+. Same commands on Windows, macOS, and Linux — no shell scripts.

## Default server

With no setup, `dshare send`/`receive` use the shared public slot on `https://dshare.me` —
visible to (and overwritable by) anyone, same as anonymous `divya`/`moti` on the site.
Point it at your own deployment instead:

```bash
dshare config https://your-dshare-host.example.com
```

Override per-command with `--server`, or via `DSHARE_SERVER`.

## Usage

```bash
dshare send report.pdf              # divya — upload a file
dshare send --text "some text"      # divya — upload text
echo "some text" | dshare send      # piping works too

dshare receive                      # moti — download the latest file/text
dshare receive -o path/             # save to a specific file/folder

dshare clear                        # /clear
dshare status                       # configured server + reachability
```

`receive` saves files to the current directory in a terminal, but streams raw bytes to
stdout when piped — so `dshare receive > out.zip` or `dshare receive | pbcopy` both work.

File transfers show a live progress bar (filename, percentage, size, rate) on stderr,
so it never corrupts piped stdout output.

`dshare divya <file>` / `dshare moti` also work, matching the site's keywords.

## Notes

- Public lane only — no login, no private per-user slots.
- Self-signed/local server: `--insecure` skips TLS verification.
- Exit codes: `0` success, `1` error, `2` the slot was empty on `receive`.
- File uploads/downloads are streamed, not buffered fully in memory.

Full reference: [github.com/motiedivya/dshare/tree/main/cli](https://github.com/motiedivya/dshare/tree/main/cli).
