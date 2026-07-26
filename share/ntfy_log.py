"""Best-effort action logging to a private ntfy topic.

Fire-and-forget: publishing runs on a daemon thread with a short timeout and
never raises, so a slow/unreachable ntfy server never blocks or breaks a
request. No-ops entirely unless DSHARE_NTFY_LOG_URL/_USER/_PASSWORD are all
configured.

Scope, deliberately conservative:
- IP, user-agent, action, lane (public/private), and account email (only for
  authenticated actions — never attached to anonymous/public-lane events
  beyond the IP already visible to the server).
- Never: passwords, PINs, tokens, session/CSRF secrets, or the actual
  uploaded file/text content.
- No IP-to-location lookups — that would mean sending every visitor's IP to
  a third-party geo-API on every action, which is a privacy regression, not
  an improvement. Geolocate a specific IP by hand if you ever actually need
  to.
"""

from __future__ import annotations

import base64
import logging
import threading
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from django.conf import settings

logger = logging.getLogger(__name__)


def _configured() -> bool:
    return bool(
        getattr(settings, "DSHARE_NTFY_LOG_URL", "")
        and getattr(settings, "DSHARE_NTFY_LOG_USER", "")
        and getattr(settings, "DSHARE_NTFY_LOG_PASSWORD", "")
    )


def _client_ip(request) -> str:
    return request.META.get("REMOTE_ADDR") or "0.0.0.0"


def _send(*, title: str, body: str, tags: str) -> None:
    url = settings.DSHARE_NTFY_LOG_URL
    user = settings.DSHARE_NTFY_LOG_USER
    password = settings.DSHARE_NTFY_LOG_PASSWORD
    auth = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
    req = Request(
        url,
        data=body.encode("utf-8"),
        headers={
            "Authorization": f"Basic {auth}",
            "Title": title,
            "Tags": tags,
            "Content-Type": "text/plain; charset=utf-8",
            # Cloudflare (fronting the ntfy host) blocks the default
            # urllib User-Agent as a bot signature (error code 1010).
            "User-Agent": "dshare-server/1.0",
        },
        method="POST",
    )
    try:
        with urlopen(req, timeout=5):
            pass
    except (HTTPError, URLError, OSError):
        logger.warning("ntfy action-log publish failed", exc_info=True)


def log_action(request, action: str, **fields) -> None:
    """Publish a best-effort audit event for `action` to the log topic.

    Extra keyword args become `key=value` fields in the message body; pass
    only metadata (filenames, sizes, outcomes) — never secrets or content.
    """
    if not _configured():
        return

    user = getattr(request, "user", None)
    is_authed = bool(user and user.is_authenticated)
    lane = "private" if is_authed else "public"

    parts = [f"action={action}", f"lane={lane}", f"ip={_client_ip(request)}"]
    if is_authed:
        parts.append(f"user={user.email or user.username}")
    for key, value in fields.items():
        if value is None or value == "":
            continue
        parts.append(f"{key}={value}")
    user_agent = (request.META.get("HTTP_USER_AGENT") or "")[:180]
    if user_agent:
        parts.append(f'ua="{user_agent}"')

    thread = threading.Thread(
        target=_send,
        kwargs={
            "title": f"dShare: {action} ({lane})",
            "body": " ".join(parts),
            "tags": f"{action},{lane}",
        },
        daemon=True,
    )
    thread.start()
