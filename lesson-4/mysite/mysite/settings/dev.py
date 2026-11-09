from .base import *
import os
from dotenv import load_dotenv

load_dotenv()

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = True

# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = "django-insecure-ubwug8fvrjgh8(ljrj747v^_a_s(4dn*(!k1ep%4&+-s2=i-99"

# SECURITY WARNING: define the correct hosts in production!
ALLOWED_HOSTS = ["*"]

MAILERS = {
    "default": {
        "BACKEND": "django.core.mail.backends.console.EmailBackend",
    },
}

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.environ.get("POSTGRES_DB", "wagtail"),
        "USER": os.environ.get("POSTGRES_USER", "wagtail"),
        "PASSWORD": os.environ.get("POSTGRES_PASSWORD", "wagtail"),
        "HOST": os.environ.get("POSTGRES_HOST", "localhost"),
        "PORT": os.environ.get("POSTGRES_PORT", "5432"),
    }
}

try:
    from .local import *
except ImportError:
    pass
