# Deployments

This document describes how to run the Wagtail project locally, with a single Docker container, and with Docker Compose.

## Local Development (without Docker)

See [LOCAL-RUN.md](LOCAL-RUN.md) for full instructions.

Quick summary:

```bash
# Start PostgreSQL container
docker run -d \
  --name wagtail-postgres \
  -e POSTGRES_DB=wagtail \
  -e POSTGRES_USER=wagtail \
  -e POSTGRES_PASSWORD=wagtail \
  -p 5432:5432 \
  -v wagtail_postgres_data:/var/lib/postgresql/data \
  postgres:16-alpine

# Create virtual environment and install dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Configure .env and settings (see LOCAL-RUN.md)
# Add "django.contrib.postgres" to INSTALLED_APPS in base.py

python manage.py migrate
python manage.py createsuperuser
python manage.py runserver
```

---

## Single Docker Container

One image is used for all environments (dev, staging, production).  
Configuration is controlled via environment variables and `mysite.settings.docker`.

Migrations run automatically on container start via `entrypoint.sh`.

### Build the image

```bash
docker build -t mysite-wagtail .
```

### Run the container

```bash
docker run -d \
  --name wagtail-app \
  --add-host=host.docker.internal:host-gateway \
  -p 8000:8000 \
  -e SECRET_KEY="your-secret-key" \
  -e DEBUG=True \
  -e ALLOWED_HOSTS="*" \
  -e POSTGRES_DB=wagtail \
  -e POSTGRES_USER=wagtail \
  -e POSTGRES_PASSWORD=wagtail \
  -e POSTGRES_HOST=host.docker.internal \
  -e POSTGRES_PORT=5432 \
  -v $(pwd)/media:/app/media \
  mysite-wagtail
```

### Create superuser (first time only)

```bash
docker exec -it wagtail-app python manage.py createsuperuser
```

### Fix media permissions

```bash
docker exec wagtail-app id
sudo chown -R 1000:1000 media/
sudo chmod -R 755 media/
docker restart wagtail-app
```

---

## Docker Compose

All services (web, db, nginx) are defined in `docker-compose.yml`.

Migrations run automatically on container start via `entrypoint.sh`.

### Start the stack

```bash
# Create .env file if it does not exist
echo 'SECRET_KEY=your-secret-key-here' > .env

# Build and start
docker compose up --build -d
```

### Create superuser (first time only)

```bash
docker compose exec web python manage.py createsuperuser
```

### Fix media permissions (if needed)

```bash
docker compose exec -u root web chown -R wagtail:wagtail /app/media
docker compose restart web
```

### Useful commands

```bash
# View logs
docker compose logs -f web

# Stop
docker compose down

# Stop and remove volumes
docker compose down -v

# Rebuild after code changes
docker compose up --build -d
```

### Services

| Service | Description        | Port |
|---------|--------------------|------|
| web     | Wagtail / Gunicorn | 8000 |
| db      | PostgreSQL         | 5432 |
| nginx   | Reverse proxy      | 80   |

Site is available at http://localhost (via Nginx).

---

## Environment variables

| Variable            | Description           | Example                        |
|---------------------|-----------------------|--------------------------------|
| `SECRET_KEY`        | Django secret key     | `your-secret-key`              |
| `DEBUG`             | Debug mode            | `True` / `False`               |
| `ALLOWED_HOSTS`     | Comma-separated hosts | `*` or `example.com`           |
| `POSTGRES_DB`       | Database name         | `wagtail`                      |
| `POSTGRES_USER`     | Database user         | `wagtail`                      |
| `POSTGRES_PASSWORD` | Database password     | `wagtail`                      |
| `POSTGRES_HOST`     | Database host         | `db` or `host.docker.internal` |
| `POSTGRES_PORT`     | Database port         | `5432`                         |

### Notes

- The same image is used for dev, staging, and production.
- Only environment variables differ between environments.
- Media files are stored in a named volume (`media_data`) when using Docker Compose, or in a bind mount when using a single container.
- Migrations run automatically on container start via `entrypoint.sh`.
- Superuser must be created manually once.
