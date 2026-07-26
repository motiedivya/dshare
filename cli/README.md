# dshare-cli

A cross-platform command-line client for [dShare](https://docs.dshare.me) — the
same 10-second "public share" flow as typing `divya` / `moti` on the web UI,
from a terminal on Linux, macOS, or Windows.

It talks to your dShare server's existing public endpoints (`/upload/`,
`/download/`, `/api/share/clear/`) — no server changes required, and it
doesn't touch private/login-based sharing.

> **Heads up:** with no setup, `dshare send`/`receive` use the shared public
> slot on `https://dshare.me` — the same one anonymous visitors to the site
> get. Anything you send there is visible to (and overwritable by) anyone.
> Run `dshare config https://your-own-host` to use your own private
> deployment instead. See [Setup](#setup).

## Install

Requires Python 3.9+ (any OS). [pipx](https://pipx.pypa.io/) is recommended
since it keeps the CLI's dependencies isolated:

```bash
pipx install dshare-cli
```

Or with plain pip:

```bash
pip install dshare-cli
```

For local development (from a clone of this repo):

```bash
cd cli
pip install -e .
```

All of these work identically on Windows (PowerShell/cmd), macOS, and
Linux — the CLI has no shell scripts and no OS-specific setup steps.

## Setup

By default the CLI talks to `https://dshare.me`, so `dshare send`/`receive`
work with no setup at all. If you're self-hosting your own dShare instance,
point the CLI at it once:

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

File transfers (`send <file>` and `receive` when the slot holds a file) show a
live `tqdm` progress bar — filename, percentage, size, and transfer rate —
streamed to stderr so it never corrupts piped stdout output. It's automatically
hidden when stderr isn't a terminal (redirected to a file, CI logs, etc.).

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
- On failure, error messages include a short excerpt of the server's response
  body (not just the HTTP status) to make unexpected errors diagnosable.
- File uploads/downloads are streamed, not buffered fully in memory, so large
  files don't balloon RAM usage.

## Releasing (maintainers)

Publishing to PyPI is fully automated via GitHub Actions + PyPI Trusted
Publishing (OIDC) — no API tokens stored anywhere. The version number is
derived from the git tag itself (via `hatch-vcs`), so there's nothing to
bump by hand. To ship a release:

```bash
git tag cli-vX.Y.Z   # e.g. cli-v0.1.3
git push origin cli-vX.Y.Z
```

That triggers [`.github/workflows/publish-cli.yml`](../.github/workflows/publish-cli.yml),
which builds the package and publishes `dshare-cli==X.Y.Z` to PyPI. The `pypi`
GitHub Environment has no required-reviewer gate, so a tag push publishes
immediately — double-check the tag before pushing it. Current releases:
[PyPI](https://pypi.org/project/dshare-cli/) · [git tags](https://github.com/motiedivya/dshare/tags?q=cli-v).
