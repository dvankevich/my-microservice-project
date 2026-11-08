# Development Tools Automation Script

This repository contains an automated Bash script (`install_dev_tools.sh`) designed for **Debian** and **Ubuntu** systems. It checks for existing tools and installs the essential development stack without duplication.

---

## What the Script Installs

1. **Docker Engine** (using the official Docker repository adapted for Debian/Ubuntu).
2. **Docker Compose** (v2 plugin).
3. **Python 3** (>= 3.9), `python3-full`, `python3-venv`, and `pip`.
4. **Python Virtual Environment (`venv`)** created in the current working directory (defaults to `.venv`) with **Django** pre-installed inside it.

---

## Download & Run from GitHub

You can download and execute the script directly from your GitHub repository in one go. 

### Option 1: Using `curl`
```bash
curl -O [https://raw.githubusercontent.com/dvankevich/my-microservice-project/refs/heads/lesson-3/lesson-3/install_dev_tools.sh](https://raw.githubusercontent.com/dvankevich/my-microservice-project/refs/heads/lesson-3/lesson-3/install_dev_tools.sh)
chmod +x install_dev_tools.sh
sudo ./install_dev_tools.sh

```

### Option 2: Using `wget`

```bash
wget [https://raw.githubusercontent.com/dvankevich/my-microservice-project/refs/heads/lesson-3/lesson-3/install_dev_tools.sh](https://raw.githubusercontent.com/dvankevich/my-microservice-project/refs/heads/lesson-3/lesson-3/install_dev_tools.sh)
chmod +x install_dev_tools.sh
sudo ./install_dev_tools.sh

```

---

## Script Options

You can view the help message at any time by passing the `--help` flag:

```bash
sudo ./install_dev_tools.sh --help

```

* `-v, --venv-path PATH` — Specify a custom path for the virtual environment (default: `./.venv`).
* `-h, --help` — Display the help message and exit.

---

## How to Set Up and Run a Django Project

After running the script, a Python virtual environment will be created in your current directory (e.g., `.venv`). Follow these steps to initialize and run a Django project:

### 1. Activate the Virtual Environment

```bash
source .venv/bin/activate

```

*(Your terminal prompt will now show `(.venv)`).*

### 2. Create a New Django Project

```bash
django-admin startproject myproject
cd myproject

```

### 3. Configure `ALLOWED_HOSTS` (Optional for Remote Servers)

If you are running this on a remote VPS and want to access it via your browser:

1. Open the settings file:
```bash
nano myproject/settings.py

```


2. Locate and update `ALLOWED_HOSTS`:
```python
ALLOWED_HOSTS = ['*']

```


3. Save and exit (`Ctrl + O`, `Enter`, then `Ctrl + X`).

### 4. Apply Database Migrations

```bash
python manage.py migrate

```

### 5. Run the Development Server

* **For local development:**
```bash
python manage.py runserver

```


* **For a remote server (accessible externally):**
```bash
python manage.py runserver 0.0.0.0:8000

```



Open your browser and navigate to `http://<your-server-ip>:8000` to see the Django welcome page!

To stop the server, press `Ctrl + C`. To exit the virtual environment, type `deactivate`.
