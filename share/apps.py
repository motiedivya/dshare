import logging
import os

from django.apps import AppConfig
from django.contrib.auth import get_user_model
from django.db import IntegrityError
from django.db.models.signals import post_migrate


class ShareConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'share'

    def ready(self):
        post_migrate.connect(
            ensure_bootstrap_superuser,
            dispatch_uid="share.ensure_bootstrap_superuser",
        )


logger = logging.getLogger(__name__)


def ensure_bootstrap_superuser(sender, **kwargs) -> None:
    if getattr(sender, "label", None) != "share":
        return

    verbosity = int(kwargs.get("verbosity", 1) or 1)

    username = (os.getenv("DSHARE_SUPERADMIN_USERNAME") or "").strip()
    password = os.getenv("DSHARE_SUPERADMIN_PASSWORD") or ""
    email = (os.getenv("DSHARE_SUPERADMIN_EMAIL") or "").strip()

    if not username or not password:
        return

    User = get_user_model()
    if User.objects.filter(username=username).exists():
        return

    try:
        User.objects.create_superuser(username=username, email=email or None, password=password)
        if verbosity >= 1:
            try:
                print(f"Created bootstrap superuser '{username}'.")
            except OSError:
                pass
        logger.info("Created bootstrap superuser '%s' from env vars.", username)
    except IntegrityError:
        # Race/concurrent migrate: another process created it.
        return
    except Exception:
        logger.exception("Failed to create bootstrap superuser from env vars.")
