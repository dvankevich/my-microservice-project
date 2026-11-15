# Local Development Setup (Wagtail + PostgreSQL)

This document describes how to run the project locally for development.

## Requirements

- Python 3.11+
- Docker (for running PostgreSQL)
- `pip` and `venv`

## 1. Start PostgreSQL in Docker

```bash
docker run -d \
  --name wagtail-postgres \
  -e POSTGRES_DB=wagtail \
  -e POSTGRES_USER=wagtail \
  -e POSTGRES_PASSWORD=wagtail \
  -p 5432:5432 \
  -v wagtail_postgres_data:/var/lib/postgresql/data \
  postgres:16-alpine
```

Check status:

```bash
docker ps
docker logs wagtail-postgres
```

Stop / start the container:

```bash
docker stop wagtail-postgres
docker start wagtail-postgres
```

## 2. Create virtual environment and install dependencies

```bash
# In the project root (where manage.py is located)
python3 -m venv .venv
source .venv/bin/activate          # Linux / macOS
# .venv\Scripts\activate           # Windows

pip install -r requirements.txt
```

## 3. Configure environment variables

Create a `.env` file in the project root (next to `manage.py`):

```env
POSTGRES_DB=wagtail
POSTGRES_USER=wagtail
POSTGRES_PASSWORD=wagtail
POSTGRES_HOST=localhost
POSTGRES_PORT=5432

DEBUG=True
SECRET_KEY=your-secret-key-here
```

## 4. Configure the database

In `mysite/settings/dev.py` make sure the `DATABASES` setting uses PostgreSQL via environment variables.

Also add `"django.contrib.postgres"` to `INSTALLED_APPS` in `mysite/settings/base.py`.  
This is required because Wagtail uses PostgreSQL full-text search fields (`SearchVectorField`, `GinIndex`) when the database backend is PostgreSQL:

```python
INSTALLED_APPS = [
    # ...
    "django.contrib.postgres",   # required for Wagtail + PostgreSQL
    # ...
]
```

## 5. Apply migrations and create a superuser

```bash
python manage.py migrate
python manage.py createsuperuser
```

## 6. Run the development server

```bash
python manage.py runserver
```

- Site: http://127.0.0.1:8000
- Wagtail admin: http://127.0.0.1:8000/admin/

## Useful commands

```bash
# Create new migrations after model changes
python manage.py makemigrations

# Apply migrations
python manage.py migrate

# Collect static files (if needed)
python manage.py collectstatic
```

## Stopping

```bash
# Stop Django (Ctrl+C in the terminal)
# Stop Postgres
docker stop wagtail-postgres
```
