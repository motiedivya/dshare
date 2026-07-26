"""HTTP client for the dShare public share endpoints.

Talks to the exact same endpoints the web UI's `divya` (upload) and
`moti` (download) keywords use — no server-side changes required. Django's
CSRF protection is satisfied the same way the browser does it: fetch the
`csrftoken` cookie from `GET /`, then echo it back as `X-CSRFToken` on
POSTs.

Uploads/downloads are streamed (not buffered fully in memory) so callers can
report real transfer progress via an `on_progress(bytes_done, total_or_None)`
callback — see cli.py for the tqdm wiring.
"""

from __future__ import annotations

import mimetypes
import os
from dataclasses import dataclass
from typing import Callable, Iterator, Optional
from urllib.parse import unquote, urlparse

import requests
from requests_toolbelt import MultipartEncoder, MultipartEncoderMonitor

ProgressCallback = Callable[[int, Optional[int]], None]


class DShareError(Exception):
    """Raised for any user-facing dShare CLI/API failure."""


def _error_detail(resp: requests.Response) -> str:
    """Short, single-line excerpt of a failed response body, for diagnostics."""
    text = (resp.text or "").strip().replace("\n", " ")
    if not text:
        return ""
    if len(text) > 200:
        text = text[:200] + "…"
    return f": {text}"


@dataclass
class DownloadResult:
    kind: str  # "file" | "text" | "empty"
    filename: str | None = None
    size: int | None = None  # total bytes, if the server sent Content-Length
    stream: Iterator[bytes] | None = None  # "file" only — raw chunks, unread
    text: str | None = None


class DShareClient:
    def __init__(self, server: str, *, timeout: float = 30.0, verify: bool = True):
        self.server = server.rstrip("/")
        self.timeout = timeout
        self.session = requests.Session()
        self.session.verify = verify
        self.session.headers["User-Agent"] = "dshare-cli"
        # Django's CSRF middleware requires Origin/Referer on HTTPS POSTs (it
        # only skips that check over plain HTTP) — without these, every POST
        # gets rejected with 403 on any HTTPS-hosted dShare server.
        self.session.headers["Origin"] = self.server
        self.session.headers["Referer"] = f"{self.server}/"

    def _request(self, method: str, path: str, **kwargs):
        url = f"{self.server}{path}"
        try:
            return self.session.request(method, url, timeout=self.timeout, **kwargs)
        except requests.exceptions.SSLError as exc:
            raise DShareError(
                f"TLS verification failed for {self.server} ({exc}). "
                "If this is a self-signed/local server, retry with --insecure."
            ) from exc
        except requests.exceptions.ConnectionError as exc:
            raise DShareError(f"Could not reach {self.server}: {exc}") from exc
        except requests.exceptions.Timeout as exc:
            raise DShareError(f"Request to {self.server} timed out: {exc}") from exc

    def _csrf_token(self) -> str:
        token = self.session.cookies.get("csrftoken")
        if token:
            return token
        self._request("GET", "/")
        token = self.session.cookies.get("csrftoken")
        if not token:
            raise DShareError(
                f"{self.server} did not return a CSRF cookie — is this a dShare server?"
            )
        return token

    def ping(self) -> bool:
        resp = self._request("GET", "/")
        return resp.status_code < 500

    def upload_file(self, path: str, on_progress: ProgressCallback | None = None) -> None:
        if not os.path.isfile(path):
            raise DShareError(f"No such file: {path}")

        filename = os.path.basename(path)
        content_type = mimetypes.guess_type(filename)[0] or "application/octet-stream"
        token = self._csrf_token()

        with open(path, "rb") as fh:
            encoder = MultipartEncoder(fields={"file": (filename, fh, content_type)})
            total = encoder.len  # encoded multipart size — what bytes_read counts up to

            def _tick(monitor: MultipartEncoderMonitor) -> None:
                if on_progress:
                    on_progress(monitor.bytes_read, total)

            monitor = MultipartEncoderMonitor(encoder, _tick)
            resp = self._request(
                "POST",
                "/upload/",
                data=monitor,
                headers={"X-CSRFToken": token, "Content-Type": monitor.content_type},
            )
        self._raise_for_upload(resp)

    def upload_text(self, text: str) -> None:
        token = self._csrf_token()
        resp = self._request(
            "POST",
            "/upload/",
            data={"text": text},
            headers={"X-CSRFToken": token},
        )
        self._raise_for_upload(resp)

    def _raise_for_upload(self, resp: requests.Response) -> None:
        if resp.status_code == 413:
            raise DShareError("Upload rejected: exceeds this server's size limit.")
        if resp.status_code == 429:
            raise DShareError("Upload rejected: rate limit hit, try again shortly.")
        if resp.status_code != 200:
            raise DShareError(f"Upload failed (HTTP {resp.status_code}){_error_detail(resp)}")
        try:
            if resp.json().get("status") != "ok":
                raise DShareError("Upload failed: server did not confirm success.")
        except ValueError:
            raise DShareError("Upload failed: unexpected response from server.")

    def download(self) -> DownloadResult:
        resp = self._request("GET", "/download/", stream=True)
        if resp.status_code != 200:
            raise DShareError(f"Download failed (HTTP {resp.status_code}){_error_detail(resp)}")

        if resp.history:
            # Server issued a redirect to the stored file's media URL. Body
            # is not read yet (stream=True) — hand back a lazy chunk
            # iterator so the caller can write it out while reporting
            # progress, instead of buffering the whole file in memory.
            filename = unquote(os.path.basename(urlparse(resp.url).path)) or "dshare-download"
            size_header = resp.headers.get("content-length")
            size = int(size_header) if size_header and size_header.isdigit() else None
            return DownloadResult(
                kind="file", filename=filename, size=size, stream=self._iter_chunks(resp)
            )

        content_type = resp.headers.get("content-type", "")
        if content_type.startswith("text/plain"):
            return DownloadResult(kind="text", text=resp.text)

        try:
            payload = resp.json()
        except ValueError:
            raise DShareError("Unexpected response from server.")
        if payload.get("status") == "empty":
            return DownloadResult(kind="empty")
        raise DShareError("Unexpected response from server.")

    @staticmethod
    def _iter_chunks(resp: requests.Response, chunk_size: int = 256 * 1024) -> Iterator[bytes]:
        try:
            for chunk in resp.iter_content(chunk_size=chunk_size):
                if chunk:
                    yield chunk
        except requests.exceptions.RequestException as exc:
            raise DShareError(f"Download interrupted: {exc}") from exc

    def clear(self) -> None:
        token = self._csrf_token()
        resp = self._request("POST", "/api/share/clear/", headers={"X-CSRFToken": token})
        if resp.status_code == 429:
            raise DShareError("Clear rejected: rate limit hit, try again shortly.")
        if resp.status_code != 200:
            raise DShareError(f"Clear failed (HTTP {resp.status_code}){_error_detail(resp)}")
