wget https://raw.githubusercontent.com/adipbarcker/file/main/install_docker_v2.sh
chmod +x install_docker_v1.sh
./install_docker_v1.sh

=======================================================================
#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Define colors for output
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 4)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

# Function to print info messages
info() {
  echo "${BLUE}[INFO]${RESET} $1"
}

# Function to print success messages
success() {
  echo "${GREEN}[SUCCESS]${RESET} $1"
}

# Function to print error messages
error() {
  echo "${RED}[ERROR]${RESET} $1" >&2
}

# Check if sudo is available
if ! command -v sudo >/dev/null; then
  error "sudo is required but not installed. Exiting."
  exit 1
fi

# Check if Docker is already installed
if command -v docker >/dev/null; then
  success "Docker is already installed. Exiting."
  exit 0
fi

# Update package list and install prerequisites
info "Updating package list..."
sudo apt update

info "Installing prerequisites (ca-certificates, curl, gnupg, lsb-release)..."
sudo apt install -y ca-certificates curl gnupg lsb-release

# Create directory for Docker's GPG keys if not exists
info "Creating directory for Docker GPG keys..."
sudo install -m 0755 -d /etc/apt/keyrings

# Add Docker's official GPG key
info "Adding Docker's official GPG key..."
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Determine the Ubuntu codename
UBUNTU_CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")

# Add the Docker repository to Apt sources
info "Adding Docker repository to Apt sources..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index
info "Updating package index..."
sudo apt update

# Install Docker Engine and related components
info "Installing Docker Engine and related components..."
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify Docker installation
info "Verifying Docker installation..."
docker --version

# Add current user to the docker group
info "Adding user '$USER' to the 'docker' group..."
sudo usermod -aG docker "$USER"

success "Docker installation completed successfully. Please log out and log back in for group changes to take effect."
=======================================================================