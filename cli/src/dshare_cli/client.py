"""HTTP client for the dShare public share endpoints.

Talks to the exact same endpoints the web UI's `divya` (upload) and
`moti` (download) keywords use — no server-side changes required. Django's
CSRF protection is satisfied the same way the browser does it: fetch the
`csrftoken` cookie from `GET /`, then echo it back as `X-CSRFToken` on
POSTs.
"""

from __future__ import annotations

import mimetypes
import os
from dataclasses import dataclass
from urllib.parse import unquote, urlparse

import requests


class DShareError(Exception):
    """Raised for any user-facing dShare CLI/API failure."""


@dataclass
class DownloadResult:
    kind: str  # "file" | "text" | "empty"
    filename: str | None = None
    content: bytes | None = None
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

    def upload_file(self, path: str) -> None:
        if not os.path.isfile(path):
            raise DShareError(f"No such file: {path}")

        filename = os.path.basename(path)
        content_type = mimetypes.guess_type(filename)[0] or "application/octet-stream"
        token = self._csrf_token()

        with open(path, "rb") as fh:
            resp = self._request(
                "POST",
                "/upload/",
                files={"file": (filename, fh, content_type)},
                headers={"X-CSRFToken": token},
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
            raise DShareError(f"Upload failed (HTTP {resp.status_code}).")
        try:
            if resp.json().get("status") != "ok":
                raise DShareError("Upload failed: server did not confirm success.")
        except ValueError:
            raise DShareError("Upload failed: unexpected response from server.")

    def download(self) -> DownloadResult:
        resp = self._request("GET", "/download/")
        if resp.status_code != 200:
            raise DShareError(f"Download failed (HTTP {resp.status_code}).")

        if resp.history:
            # Server issued a redirect to the stored file's media URL.
            filename = unquote(os.path.basename(urlparse(resp.url).path)) or "dshare-download"
            return DownloadResult(kind="file", filename=filename, content=resp.content)

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

    def clear(self) -> None:
        token = self._csrf_token()
        resp = self._request("POST", "/api/share/clear/", headers={"X-CSRFToken": token})
        if resp.status_code == 429:
            raise DShareError("Clear rejected: rate limit hit, try again shortly.")
        if resp.status_code != 200:
            raise DShareError(f"Clear failed (HTTP {resp.status_code}).")
