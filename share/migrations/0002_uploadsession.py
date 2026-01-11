from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion
import uuid


class Migration(migrations.Migration):
    dependencies = [
        ("share", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="UploadSession",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("is_public", models.BooleanField(default=True)),
                ("filename", models.CharField(max_length=255)),
                ("content_type", models.CharField(blank=True, max_length=255)),
                ("total_size", models.BigIntegerField()),
                ("chunk_size", models.PositiveIntegerField()),
                ("total_chunks", models.PositiveIntegerField()),
                ("received_chunks", models.JSONField(blank=True, default=list)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "user",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="upload_sessions",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
        ),
    ]
