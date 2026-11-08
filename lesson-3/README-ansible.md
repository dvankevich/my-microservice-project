# Setup Development Environment

Ansible playbook for automated setup of a development environment on Debian/Ubuntu.

## What the playbook installs

- Docker Engine + Docker Compose plugin
- Python 3 + `python3-venv` + `pip`
- Python virtual environment at `/home/<user>/.venv`
- Django inside that virtual environment
- Adds the current user to the `docker` group

## Requirements

- Debian or Ubuntu
- Ansible installed
- Internet access
- sudo privileges

### Install Ansible (if not already installed)

```bash
sudo apt update
sudo apt install -y ansible
```

## How to download and run

### 1. Download the playbook

```bash
curl -O https://raw.githubusercontent.com/dvankevich/my-microservice-project/refs/heads/lesson-3/lesson-3/setup_dev_tools.yml
```

or

```bash
wget https://raw.githubusercontent.com/dvankevich/my-microservice-project/refs/heads/lesson-3/lesson-3/setup_dev_tools.yml
```

### 2. Run the playbook

```bash
sudo ansible-playbook setup_dev_tools.yml
```

> The playbook **must** be run with `sudo` because it installs system packages and configures Docker.

## After execution

### Activate the virtual environment

```bash
source /home/$USER/.venv/bin/activate
```

### Apply docker group changes (without rebooting)

```bash
newgrp docker
```

or simply log out and log back in.

### Verify the installation

```bash
docker --version
docker compose version
python --version
pip show django
```

## Important notes

- The virtual environment is created at `/home/<your_user>/.venv`.
- The username is detected automatically (via `SUDO_USER`).
- If `.venv` already exists, it will be removed and recreated (to fix ownership).
- The playbook supports Debian and Ubuntu only.

## Re-running

The playbook is idempotent. You can run it multiple times — it will not break an already configured environment.
