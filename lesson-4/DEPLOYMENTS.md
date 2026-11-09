# Deployments

This document describes how to run the Wagtail project locally and in Docker.

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
pip install psycopg2-binary python-dotenv

# Configure .env and settings (see LOCAL-RUN.md)
# Add "django.contrib.postgres" to INSTALLED_APPS in base.py

python manage.py migrate
python manage.py createsuperuser
python manage.py runserver
```

---

## Docker Deployment

One image is used for all environments (dev, staging, production).  
Configuration is controlled via environment variables and `mysite.settings.docker`.

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

### Fix media permissions

The container runs as user `wagtail` (usually UID 1000).  
After the first start, fix ownership of the media folder:

```bash
docker exec wagtail-app id          # check UID (usually 1000)
sudo chown -R 1000:1000 media/
sudo chmod -R 755 media/
docker restart wagtail-app
```

### Useful commands

```bash
# View logs
docker logs -f wagtail-app

# Stop / start
docker stop wagtail-app
docker start wagtail-app

# Remove container
docker rm -f wagtail-app
```

### Environment variables

| Variable              | Description                          | Example                  |
|-----------------------|--------------------------------------|--------------------------|
| `SECRET_KEY`          | Django secret key                    | `your-secret-key`        |
| `DEBUG`               | Debug mode                           | `True` / `False`         |
| `ALLOWED_HOSTS`       | Comma-separated hosts                | `*` or `example.com`     |
| `POSTGRES_DB`         | Database name                        | `wagtail`                |
| `POSTGRES_USER`       | Database user                        | `wagtail`                |
| `POSTGRES_PASSWORD`   | Database password                    | `wagtail`                |
| `POSTGRES_HOST`       | Database host                        | `host.docker.internal`   |
| `POSTGRES_PORT`       | Database port                        | `5432`                   |
| `EMAIL_BACKEND`       | Email backend                        | `django.core.mail...`    |
| `WAGTAILADMIN_BASE_URL` | Base URL for admin emails          | `http://localhost:8000`  |

### Notes

- The same image is used for dev, staging, and production.
- Only environment variables differ between environments.
- Media files are stored in the mounted `./media` directory on the host.
- Migrations run automatically on container start (not ideal for production; consider a separate release step later).
