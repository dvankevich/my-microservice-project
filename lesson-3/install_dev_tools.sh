#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to display help information
show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -v, --venv-path PATH  Specify custom path for venv (default: .venv in current directory)
  -h, --help            Display this help message and exit

Description:
  Automates the installation of essential development tools on Debian/Ubuntu:
  - Docker (Engine)
  - Docker Compose (v2 plugin)
  - Python (3.9 or newer) & python3-full
  - Virtual Environment (venv) with Django installed inside it
EOF
  exit 0
}

# Parse command line arguments
VENV_PATH="./.venv"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -v|--venv-path)
      VENV_PATH="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      ;;
    *)
      echo "[-] Unknown parameter: $1" >&2
      echo "[-] Use --help for usage information." >&2
      exit 1
      ;;
  esac
done

# Check if the script is run with root privileges (either via root or sudo)
if [ "$EUID" -ne 0 ]; then
  echo "[-] This script must be run as root or with sudo privileges." >&2
  exit 1
fi

echo "[+] Starting development tools installation/verification..."

# Source os-release explicitly
if [ -f /etc/os-release ]; then
  . /etc/os-release
else
  echo "[-] Error: /etc/os-release not found. Cannot determine OS." >&2
  exit 1
fi

# Explicitly determine Docker OS repository target based on ID or PRETTY_NAME
DOCKER_OS=""
if [[ "$ID" == "debian" ]] || [[ "$PRETTY_NAME" =~ "Debian" ]]; then
  DOCKER_OS="debian"
elif [[ "$ID" == "ubuntu" ]] || [[ "$PRETTY_NAME" =~ "Ubuntu" ]]; then
  DOCKER_OS="ubuntu"
else
  echo "[-] Unsupported distribution: ID=$ID, PRETTY_NAME=$PRETTY_NAME" >&2
  exit 1
fi

echo "[*] Detected OS: $PRETTY_NAME -> Using Docker repository for: $DOCKER_OS ($VERSION_CODENAME)"

# Clean up broken repository list if it was previously created incorrectly
if [ -f /etc/apt/sources.list.d/docker.list ]; then
  if grep -q "linux/ubuntu" /etc/apt/sources.list.d/docker.list; then
    echo "[!] Removing incorrect Docker repository configuration..."
    rm -f /etc/apt/sources.list.d/docker.list
  fi
fi

# 1. Check and install Docker
if command -v docker &>/dev/null; then
  echo "[!] Docker is already installed ($(docker --version)). Skipping."
else
  echo "[+] Installing Docker for $DOCKER_OS ($VERSION_CODENAME)..."
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  
  # Add Docker's official GPG key (.asc format)
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$DOCKER_OS/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  # Set up the correct repository dynamically
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$DOCKER_OS \
    $VERSION_CODENAME stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  echo "[+] Docker successfully installed."
fi

# 2. Check and install Docker Compose (Plugin check)
if docker compose version &>/dev/null; then
  echo "[!] Docker Compose is already installed ($(docker compose version)). Skipping."
else
  echo "[+] Installing Docker Compose plugin..."
  apt-get update
  apt-get install -y docker-compose-plugin
  echo "[+] Docker Compose successfully installed."
fi

# 3. Check and install Python (>= 3.9), python3-full, and pip
PYTHON_READY=false
if command -v python3 &>/dev/null; then
  PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
  PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
  PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)
  
  if [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -ge 9 ]; then
    # Ensure python3-full and python3-venv are available for venv creation
    if dpkg -l | grep -q python3-venv && (command -v pip3 &>/dev/null || python3 -m pip --version &>/dev/null); then
      echo "[!] Python $PY_VERSION, pip, and venv support are already installed. Skipping."
      PYTHON_READY=true
    else
      echo "[!] Python $PY_VERSION is installed, but missing venv or pip packages."
    fi
  fi
fi

if [ "$PYTHON_READY" = false ]; then
  echo "[+] Installing Python 3, python3-full, python3-venv, and pip..."
  apt-get update
  apt-get install -y python3 python3-pip python3-full python3-venv
  echo "[+] Python and required modules successfully installed."
fi

# 4. Create virtual environment (venv) in current directory and install Django inside it
echo "[+] Setting up Python virtual environment at $VENV_PATH..."

if [ ! -d "$VENV_PATH" ]; then
  python3 -m venv "$VENV_PATH"
  echo "[+] Virtual environment created."
else
  echo "[!] Virtual environment already exists at $VENV_PATH."
fi

# Upgrade pip and install Django inside the virtual environment
echo "[+] Installing/Updating Django inside the virtual environment..."
"$VENV_PATH/bin/python3" -m pip install --no-cache-dir --upgrade pip
"$VENV_PATH/bin/python3" -m pip install --no-cache-dir django

# Verify Django installation inside venv
if "$VENV_PATH/bin/python3" -c "import django" &>/dev/null; then
  DJANGO_VERSION=$("$VENV_PATH/bin/python3" -m django --version)
  echo "[+] Django (version $DJANGO_VERSION) successfully installed inside $VENV_PATH."
else
  echo "[-] Failed to install Django inside virtual environment." >&2
  exit 1
fi

echo "[done] All development tools are installed and ready to use!"
echo "[*] To activate the Python virtual environment, run: source $VENV_PATH/bin/activate"

