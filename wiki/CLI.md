# CLI

`dshare-cli` is a cross-platform (Linux/macOS/Windows) command-line client for the same
public `divya`/`moti` flow, published on [PyPI](https://pypi.org/project/dshare-cli/).
Source: [`cli/`](https://github.com/motiedivya/dshare/tree/main/cli).

## Install

```bash
pipx install dshare-cli   # or: pip install dshare-cli
```

Requires Python 3.9+. No shell scripts, no OS-specific steps — the same commands work
on Windows (PowerShell/cmd), macOS, and Linux.

## Default server

With no setup, `dshare send`/`receive` use the shared public slot on `https://dshare.me` —
the same one anonymous visitors to the site get. Anything you send there is visible to
(and overwritable by) anyone. Point it at your own deployment instead:

```bash
dshare config https://your-dshare-host.example.com
```

Saved to a per-OS config file. Override per-command with `--server`, or via the
`DSHARE_SERVER` environment variable (handy for CI/scripting). Precedence: `--server` >
`DSHARE_SERVER` > saved config > `dshare.me` default.

## Commands

| Command | What it does |
|---|---|
| `dshare send <file>` / `dshare divya <file>` | upload a file |
| `dshare send --text "..."` | upload text |
| `echo "..." \| dshare send` | upload piped text |
| `dshare receive` / `dshare moti` | download the latest file, or print the latest text |
| `dshare receive -o path/` | save to a specific file/folder |
| `dshare clear` | wipe the slot |
| `dshare status` | show configured server + reachability |
| `dshare config <url>` | show or set the default server |

`receive` saves files to the current directory in a terminal, but streams raw bytes to
stdout when piped (like `curl`) — so `dshare receive > out.zip` or `dshare receive | pbcopy`
both work.

## Notes

- Only uses the **public** lane — no login, matches anonymous `divya`/`moti` on the web.
- Self-signed/local server: pass `--insecure` to skip TLS verification.
- Exit codes: `0` success, `1` error, `2` the slot was empty on `receive`.
- Errors include a short excerpt of the server's response body, not just the HTTP status.

## Releasing (maintainers)

Fully automated: `git tag cli-vX.Y.Z && git push origin cli-vX.Y.Z` builds and publishes
to PyPI via GitHub Actions + PyPI Trusted Publishing (no stored tokens). Version comes
from the git tag itself. See [`cli/README.md`](https://github.com/motiedivya/dshare/blob/main/cli/README.md#releasing-maintainers).
