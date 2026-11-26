"""Optional S3 storage for Wagtail images and documents."""

import os


def apply_s3_media_storage(settings):
    """Point Django's default storage at S3 when a bucket name is set.

    Wagtail images and documents use the default storage. Static files stay
    on the local staticfiles backend. An empty AWS_STORAGE_BUCKET_NAME leaves
    the filesystem storage from the base settings unchanged.
    """
    bucket = os.environ.get("AWS_STORAGE_BUCKET_NAME", "").strip()
    if not bucket:
        return

    region = os.environ.get("AWS_S3_REGION_NAME", "eu-central-1").strip() or "eu-central-1"
    custom_domain = os.environ.get("AWS_S3_CUSTOM_DOMAIN", "").strip()
    if not custom_domain:
        custom_domain = f"{bucket}.s3.{region}.amazonaws.com"

    apps = list(settings["INSTALLED_APPS"])
    if "storages" not in apps:
        apps.append("storages")

    settings["INSTALLED_APPS"] = apps
    settings["AWS_STORAGE_BUCKET_NAME"] = bucket
    settings["AWS_S3_REGION_NAME"] = region
    settings["AWS_S3_CUSTOM_DOMAIN"] = custom_domain
    settings["AWS_S3_FILE_OVERWRITE"] = False
    # Object ownership is BucketOwnerEnforced, so ACLs are disabled.
    # Public reads come from the bucket policy, not from an object ACL.
    settings["AWS_DEFAULT_ACL"] = None
    settings["AWS_QUERYSTRING_AUTH"] = os.environ.get("AWS_QUERYSTRING_AUTH", "False") == "True"
    settings["AWS_S3_OBJECT_PARAMETERS"] = {
        "CacheControl": "max-age=86400",
    }
    settings["STORAGES"] = {
        **settings["STORAGES"],
        "default": {
            "BACKEND": "storages.backends.s3.S3Storage",
        },
    }
    settings["MEDIA_URL"] = f"https://{custom_domain}/"
