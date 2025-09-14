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
    elif [ -f /etc/os-release ]; then
        # Handle modern systems that may not have /etc/redhat-release
        source /etc/os-release
        OS_NAME=$NAME
        if [[ $ID == "centos" ]]; then
            OS_TYPE="centos"
        elif [[ $ID == "rhel" ]]; then
            OS_TYPE="rhel"
        elif [[ $ID == "almalinux" ]]; then
            OS_TYPE="almalinux"
        elif [[ $ID == "rocky" ]]; then
            OS_TYPE="rockylinux"
        else
            echo "Error: This script is designed for RHEL-based distributions only."
            exit 1
        fi
        VERSION=$(echo $VERSION_ID | cut -d'.' -f1)
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
    sudo $PKG_MGR install -y yum-utils device-mapper-persistent-data lvm2 curl git
    
    # Install additional dependencies for Rocky Linux
    if [ "$OS_TYPE" = "rockylinux" ]; then
        echo "Installing additional dependencies for Rocky Linux..."
        sudo $PKG_MGR install -y containerd.io
    fi
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

# Function to configure Docker daemon
configure_docker_daemon() {
    echo "##########################"
    echo "Configuring Docker daemon"
    echo "##########################"
    
    # Create docker daemon config directory if it doesn't exist
    sudo mkdir -p /etc/docker
    
    # Create or update daemon.json with appropriate settings for Rocky Linux
    sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
    
    echo "Docker daemon configuration updated."
    echo ""
}

# Function to start and enable Docker
start_enable_docker() {
    echo "############################"
    echo "Starting and enabling Docker"
    echo "############################"
    
    # Enable and start containerd service first if it exists
    if systemctl list-unit-files | grep -q containerd.service; then
        sudo systemctl enable --now containerd.service
    fi
    
    # Enable and start docker
    sudo systemctl enable docker
    sudo systemctl start docker
    
    # Wait for docker to start properly
    sleep 5
    
    # Check if docker is running, if not try to troubleshoot
    if ! sudo systemctl is-active --quiet docker; then
        echo "Docker failed to start. Attempting to troubleshoot..."
        
        # Check if cgroups are properly mounted
        if ! mount | grep -q cgroup; then
            echo "Cgroups not mounted. Attempting to mount cgroups..."
            sudo mount -t cgroup2 none /sys/fs/cgroup
        fi
        
        # Try to start docker again
        sudo systemctl start docker
        sleep 3
    fi
    
    echo ""
}

# Function to add user to Docker group
add_user_to_docker_group() {
    echo "###########################"
    echo "Adding user to Docker group"
    echo "###########################"
    sudo groupadd docker || true
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
        
        # Add docker interface to trusted zone
        sudo firewall-cmd --permanent --zone=trusted --add-interface=docker0 || echo "Warning: Could not add docker0 to trusted zone"
        
        # Allow necessary ports for Docker
        sudo firewall-cmd --permanent --add-port=2376/tcp || true  # Docker Machine
        sudo firewall-cmd --permanent --add-port=2377/tcp || true  # Swarm
        sudo firewall-cmd --permanent --add-port=4789/udp || true  # Swarm overlay network
        sudo firewall-cmd --permanent --add-port=7946/tcp || true  # Swarm node communication
        sudo firewall-cmd --permanent --add-port=7946/udp || true  # Swarm node communication
        
        # Enable masquerading
        sudo firewall-cmd --permanent --add-masquerade
        
        # Reload firewall
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
    # Give docker a moment to fully initialize
    sleep 2
    sudo docker run --rm hello-world
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

# Function to check for potential issues
check_system() {
    echo "########################"
    echo "Checking system compatibility"
    echo "########################"
    
    # Check kernel version
    KERNEL_VERSION=$(uname -r)
    echo "Kernel version: $KERNEL_VERSION"
    
    # Check if overlay2 is supported
    if ! sudo modprobe overlay; then
        echo "Warning: Overlay filesystem not supported by kernel"
    else
        echo "Overlay filesystem supported"
        sudo modprobe -r overlay
    fi
    
    # Check cgroup configuration
    if [ ! -e /sys/fs/cgroup ]; then
        echo "Warning: Cgroups not mounted"
    else
        echo "Cgroups properly mounted"
    fi
    
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
    check_system
    
    # Installation steps
    remove_old_docker
    install_requirements
    add_docker_repo
    update_package_index
    install_docker
    configure_docker_daemon
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
    echo "If you encounter issues:"
    echo "- Check kernel version meets Docker requirements (3.10+ for CentOS/RHEL 7, 4.x+ for newer versions)"
    echo "- Ensure SELinux is properly configured or set to permissive mode if needed"
    echo "- Verify firewall rules allow Docker traffic"
    echo ""
    echo "Supported OS: RHEL, CentOS, AlmaLinux, Rocky Linux"
    echo "##########################################################################"
    echo ""
}

# Run main function
main