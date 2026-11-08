# Development Environment Setup Script (`install_dev_tools.sh`)

This script automates the installation and verification of essential development tools on **Debian** and **Ubuntu** systems.

## Features

- **Docker Engine**: Automatically configures the official Docker repository based on your OS (`debian` or `ubuntu`) and installs the engine.
- **Docker Compose**: Installs the Docker Compose v2 plugin.
- **Python (>= 3.9)**: Verifies/installs Python 3 alongside `python3-full` and `python3-venv` for proper virtual environment management.
- **Virtual Environment (`venv`)**: Automatically creates an isolated Python virtual environment (`.venv`) in the current directory or a specified path.
- **Django**: Installs and upgrades Django via `pip` directly inside the virtual environment (complying with PEP 668).
- **Idempotent**: Checks if tools are already installed to prevent duplicated installations.

---

## Prerequisites

- **OS**: Debian (11/12/13) or Ubuntu (20.04/22.04/24.04).
- **Privileges**: Must be run with `root` privileges (or via `sudo`).

---

## Usage

### 1. Make the Script Executable
```bash
chmod +x install_dev_tools.sh
```

### 2. Run the Script

**Default execution** (creates `.venv` in the current directory):
```bash
sudo ./install_dev_tools.sh
# or if logged in as root:
./install_dev_tools.sh
```

**Custom virtual environment path**:
```bash
sudo ./install_dev_tools.sh --venv-path ./my_custom_env
```

**Display Help**:
```bash
./install_dev_tools.sh --help
```

---

## How to Create and Run a Django Project

Once the setup script finishes successfully, follow these steps to start a new Django project:

### Step 1: Activate the Virtual Environment
```bash
source .venv/bin/activate
```
*(Your terminal prompt will now show `(.venv)`).*

### Step 2: Create a New Django Project
Run `django-admin` to bootstrap your project structure:
```bash
django-admin startproject myproject
cd myproject
```

### Step 3: Run Database Migrations
Initialize the default SQLite database:
```bash
python manage.py migrate
```

### Step 4: Configure `ALLOWED_HOSTS` (Required for Remote Servers)
If you are running this on a remote server/VPS, allow access to your server's IP address:
1. Open `myproject/settings.py` in your editor:
   ```bash
   nano myproject/settings.py
   ```
2. Modify `ALLOWED_HOSTS`:
   ```python
   ALLOWED_HOSTS = ['*']  # Or specify your server's IP address
   ```
3. Save and exit (`Ctrl + O`, `Enter`, `Ctrl + X`).

### Step 5: Start the Development Server

- **For local development**:
  ```bash
  python manage.py runserver
  ```
- **For remote servers** (binds to all network interfaces on port 8000):
  ```bash
  python manage.py runserver 0.0.0.0:8000
  ```

Open your browser and navigate to `http://<your-server-ip>:8000` to view the Django welcome page.

---

## Deactivating the Virtual Environment
When you are done working:
```bash
deactivate
```