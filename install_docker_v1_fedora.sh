#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

# Function to detect OS
detect_os() {
    if [ -f /etc/redhat-release ]; then
        OS_NAME=$(cat /etc/redhat-release | cut -d' ' -f1)
        if grep -q "CentOS" /etc/redhat-release; then
            OS_TYPE="centos"
        elif grep -q "Red Hat" /etc/redhat-release; then
            OS_TYPE="rhel"
        elif grep -q "AlmaLinux" /etc/redhat-release; then
            OS_TYPE="almalinux"
        elif grep -q "Rocky" /etc/redhat-release; then
            OS_TYPE="rockylinux"
        else
            OS_TYPE="rhel"  # Default to RHEL-like
        fi
        
        VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d'.' -f1)
    else
        echo "Error: This script is designed for RHEL-based distributions only."
        exit 1
    fi
}

# Function to check if dnf or yum should be used
get_package_manager() {
    if command -v dnf &> /dev/null; then
        PKG_MGR="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MGR="yum"
    else
        echo "Error: Neither dnf nor yum package manager found."
        exit 1
    fi
}

# Function to remove old Docker versions
remove_old_docker() {
    echo "##########################"
    echo "Removing old Docker versions"
    echo "##########################"
    sudo $PKG_MGR remove -y docker \
                         docker-client \
                         docker-client-latest \
                         docker-common \
                         docker-latest \
                         docker-latest-logrotate \
                         docker-logrotate \
                         docker-engine \
                         podman \
                         runc 2>/dev/null || true
    echo ""
}

# Function to install required packages
install_requirements() {
    echo "################################"
    echo "Installing required packages"
    echo "################################"
    sudo $PKG_MGR update -y
    sudo $PKG_MGR install -y yum-utils device-mapper-persistent-data lvm2 curl
    echo ""
}

# Function to add Docker repository
add_docker_repo() {
    echo "#######################################"
    echo "Adding Docker repository"
    echo "#######################################"
    
    # Remove existing Docker repo if exists
    sudo rm -f /etc/yum.repos.d/docker-ce.repo
    
    # Add Docker CE repository based on OS type
    case $OS_TYPE in
        "centos"|"almalinux"|"rockylinux")
            sudo $PKG_MGR config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            ;;
        "rhel")
            sudo $PKG_MGR config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
            ;;
        *)
            # Default to CentOS repo for other RHEL-like distros
            sudo $PKG_MGR config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            ;;
    esac
    echo ""
}

# Function to update package index
update_package_index() {
    echo "######################"
    echo "Updating package index"
    echo "######################"
    sudo $PKG_MGR makecache
    echo ""
}

# Function to install Docker
install_docker() {
    echo "#################"
    echo "Installing Docker"
    echo "#################"
    sudo $PKG_MGR install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    echo ""
}

# Function to start and enable Docker
start_enable_docker() {
    echo "############################"
    echo "Starting and enabling Docker"
    echo "############################"
    sudo systemctl start docker
    sudo systemctl enable docker
    echo ""
}

# Function to add user to Docker group
add_user_to_docker_group() {
    echo "###########################"
    echo "Adding user to Docker group"
    echo "###########################"
    sudo usermod -aG docker $USER
    echo ""
}

# Function to configure firewall
configure_firewall() {
    echo "####################"
    echo "Configuring firewall"
    echo "####################"
    
    # Check if firewalld is active
    if systemctl is-active --quiet firewalld; then
        echo "Configuring firewalld for Docker..."
        sudo firewall-cmd --permanent --zone=trusted --add-interface=docker0 2>/dev/null || true
        sudo firewall-cmd --permanent --zone=public --add-masquerade
        sudo firewall-cmd --reload
        echo "Firewalld configured successfully."
    else
        echo "Firewalld is not active. Skipping firewall configuration."
    fi
    echo ""
}

# Function to verify Docker installation
verify_docker() {
    echo "#############################"
    echo "Verifying Docker installation"
    echo "#############################"
    sudo docker version
    echo ""
    
    echo "Testing Docker with hello-world image..."
    sudo docker run hello-world
    echo ""
}

# Function to display system information
display_info() {
    echo "####################"
    echo "System Information"
    echo "####################"
    echo "OS: $OS_NAME"
    echo "OS Type: $OS_TYPE"
    echo "Version: $VERSION"
    echo "Package Manager: $PKG_MGR"
    echo ""
}

# Main execution
main() {
    echo "========================================================"
    echo "Docker Installation Script for RHEL-based Distributions"
    echo "========================================================"
    echo ""
    
    # Detect OS and package manager
    detect_os
    get_package_manager
    display_info
    
    # Installation steps
    remove_old_docker
    install_requirements
    add_docker_repo
    update_package_index
    install_docker
    start_enable_docker
    add_user_to_docker_group
    configure_firewall
    verify_docker
    
    # Final message
    echo "##########################################################################"
    echo "Docker installation completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Please log out and log back in (or run 'newgrp docker') to use Docker without sudo."
    echo "2. Test Docker with: docker run hello-world"
    echo "3. Check Docker status with: systemctl status docker"
    echo ""
    echo "Supported OS: RHEL, CentOS, AlmaLinux, Rocky Linux"
    echo "##########################################################################"
    echo ""
}

# Run main function
main