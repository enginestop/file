#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

# Add Docker's official GPG keys
echo "################################"
echo "Adding Docker's official GPG key"
echo "################################"
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo ""

# Add the repository to Apt sources
echo "#######################################"
echo "Adding Docker repository to Apt sources"
echo "#######################################"
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
echo ""

# Update package index
echo "######################"
echo "Updating package index"
echo "######################"
sudo apt update
echo ""

# Install the latest version of Docker
echo "#################"
echo "Installing Docker"
echo "#################"
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
echo ""

# Add user to the Docker group
echo "###########################"
echo "Adding user to Group Docker"
echo "###########################"
sudo usermod -aG docker $USER
echo ""

# Verify Docker installation and add user to the docker group
echo "#############################"
echo "Verifying Docker installation"
echo "#############################"
sudo docker version
echo ""

# Finish
echo "##########################################################################"
echo "Docker installation completed. Please re-login to use Docker without sudo."
echo "##########################################################################"
echo ""
