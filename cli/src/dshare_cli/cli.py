"""dshare — cross-platform CLI for dShare's public share slot.

Mirrors the web UI's `divya` (upload) / `moti` (download) keywords, talking
to the same public endpoints. Works anywhere Python + pip/pipx do:
Linux, macOS, and Windows.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Callable, Iterator

from tqdm import tqdm

from . import __version__, config
from .client import DShareClient, DShareError

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_EMPTY = 2


def _err(message: str) -> None:
    print(f"dshare: {message}", file=sys.stderr)


def _info(message: str) -> None:
    print(message, file=sys.stderr)


def _progress_bar(desc: str, total: int | None) -> tqdm:
    # Progress goes to stderr (tqdm's default) so it never corrupts stdout
    # when piping (`dshare receive | ...`); disabled outright when stderr
    # isn't a terminal (redirected to a file, CI logs, etc.) to avoid
    # spamming escape codes somewhere no one will watch them live.
    return tqdm(
        total=total,
        unit="B",
        unit_scale=True,
        unit_divisor=1024,
        desc=desc,
        disable=not sys.stderr.isatty(),
        leave=False,
    )


def _stream_to(write: Callable[[bytes], object], stream: Iterator[bytes], *, total, desc: str) -> None:
    with _progress_bar(desc, total) as bar:
        for chunk in stream:
            write(chunk)
            bar.update(len(chunk))


def _resolve_client(args: argparse.Namespace) -> DShareClient:
    server = config.get_server(getattr(args, "server", None))
    return DShareClient(server, timeout=args.timeout, verify=not args.insecure)


def _cmd_send(args: argparse.Namespace) -> int:
    client = _resolve_client(args)

    if args.text is not None:
        client.upload_text(args.text)
        _info("Uploaded text.")
        return EXIT_OK

    if args.file == "-":
        text = sys.stdin.read()
        client.upload_text(text)
        _info("Uploaded text from stdin.")
        return EXIT_OK

    if args.file:
        size = os.path.getsize(args.file)
        seen = 0
        with _progress_bar(os.path.basename(args.file), size) as bar:

            def _progress(bytes_done: int, total_bytes) -> None:
                nonlocal seen
                if total_bytes is not None and total_bytes != bar.total:
                    bar.total = total_bytes
                bar.update(bytes_done - seen)
                seen = bytes_done

            client.upload_file(args.file, on_progress=_progress)
        _info(f"Uploaded {args.file}.")
        return EXIT_OK

    if not sys.stdin.isatty():
        text = sys.stdin.read()
        if text:
            client.upload_text(text)
            _info("Uploaded text from stdin.")
            return EXIT_OK

    raise DShareError(
        "nothing to send. Pass a file path, --text \"...\", or pipe text in "
        "(e.g. 'echo hi | dshare send')."
    )


def _cmd_receive(args: argparse.Namespace) -> int:
    client = _resolve_client(args)
    result = client.download()

    if result.kind == "empty":
        _info("(nothing shared yet)")
        return EXIT_EMPTY

    if result.kind == "text":
        text = result.text or ""
        if args.output:
            Path(args.output).write_text(text, encoding="utf-8")
            _info(f"Saved to {args.output}")
        else:
            sys.stdout.write(text)
            if sys.stdout.isatty() and not text.endswith("\n"):
                sys.stdout.write("\n")
        return EXIT_OK

    # result.kind == "file"
    filename = result.filename or "dshare-download"
    if args.output:
        dest = Path(args.output)
        if dest.is_dir():
            dest = dest / filename
        with open(dest, "wb") as f:
            _stream_to(f.write, result.stream, total=result.size, desc=filename)
        _info(f"Saved to {dest}")
    elif not sys.stdout.isatty():
        _stream_to(sys.stdout.buffer.write, result.stream, total=result.size, desc=filename)
    else:
        dest = Path.cwd() / filename
        with open(dest, "wb") as f:
            _stream_to(f.write, result.stream, total=result.size, desc=filename)
        _info(f"Saved to {dest}")
    return EXIT_OK


def _cmd_clear(args: argparse.Namespace) -> int:
    client = _resolve_client(args)
    client.clear()
    _info("Cleared.")
    return EXIT_OK


def _cmd_status(args: argparse.Namespace) -> int:
    server = config.get_server(getattr(args, "server", None))
    print(f"Server: {server}")
    client = DShareClient(server, timeout=args.timeout, verify=not args.insecure)
    try:
        reachable = client.ping()
    except DShareError as exc:
        print("Reachable: no")
        print(f"  ({exc})")
        return EXIT_ERROR
    print(f"Reachable: {'yes' if reachable else 'no'}")
    return EXIT_OK if reachable else EXIT_ERROR


def _cmd_config(args: argparse.Namespace) -> int:
    if args.server_url:
        path = config.set_server(args.server_url)
        print(f"Saved server '{args.server_url.rstrip('/')}' to {path}")
        return EXIT_OK

    env = os.environ.get("DSHARE_SERVER")
    saved = config.load_config().get("server")
    if env:
        print(f"{env.rstrip('/')} (from DSHARE_SERVER)")
    elif saved:
        print(saved)
    else:
        print(f"{config.DEFAULT_SERVER} (default — nothing configured yet)")
        _info("Run 'dshare config https://your-dshare-host' to point at your own server.")
    return EXIT_OK


def _add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--server", help="dShare server URL (overrides saved config/env)")
    parser.add_argument(
        "--insecure", action="store_true", help="skip TLS certificate verification"
    )
    parser.add_argument(
        "--timeout", type=float, default=30.0, help="request timeout in seconds (default: 30)"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="dshare",
        description="Share files and text with a dShare server, from Linux, macOS, or Windows.",
    )
    parser.add_argument("--version", action="version", version=f"dshare-cli {__version__}")

    subparsers = parser.add_subparsers(dest="command", required=True)

    send = subparsers.add_parser(
        "send",
        aliases=["divya"],
        help="upload a file or text to the public slot",
    )
    send.add_argument(
        "file", nargs="?", help="path to a file to upload ('-' to read text from stdin)"
    )
    send.add_argument("-t", "--text", help="upload this text instead of a file")
    _add_common_args(send)
    send.set_defaults(func=_cmd_send)

    receive = subparsers.add_parser(
        "receive",
        aliases=["moti"],
        help="download the latest shared file or text",
    )
    receive.add_argument(
        "-o", "--output", help="save to this path/directory instead of the default"
    )
    _add_common_args(receive)
    receive.set_defaults(func=_cmd_receive)

    clear = subparsers.add_parser("clear", help="clear the public slot")
    _add_common_args(clear)
    clear.set_defaults(func=_cmd_clear)

    status = subparsers.add_parser("status", help="show the configured server and reachability")
    _add_common_args(status)
    status.set_defaults(func=_cmd_status)

    config_cmd = subparsers.add_parser(
        "config", help="show or set the default dShare server URL"
    )
    config_cmd.add_argument(
        "server_url", nargs="?", help="server URL to save as the default (omit to show current)"
    )
    config_cmd.set_defaults(func=_cmd_config)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except DShareError as exc:
        _err(str(exc))
        return EXIT_ERROR
    except KeyboardInterrupt:
        _err("interrupted.")
        return 130


if __name__ == "__main__":
    sys.exit(main())
