#!/bin/bash

# Install Grafana, Prometheus and Node Exporter on Ubuntu 22.04
# This script must be run with root privileges

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run this script as root or with sudo"
    exit 1
fi

# Check Ubuntu version
if [ ! -f /etc/os-release ]; then
    log_error "Cannot determine OS version"
    exit 1
fi

source /etc/os-release
if [ "$ID" != "ubuntu" ] || [ "$VERSION_ID" != "22.04" ]; then
    log_warn "This script is tested on Ubuntu 22.04, but you are running $ID $VERSION_ID"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Variables
PROMETHEUS_VERSION="3.5.0"
NODE_EXPORTER_VERSION="1.9.1"
ARCH="amd64"

# Update system
log_info "Updating system packages..."
apt update && apt upgrade -y

# Install dependencies
log_info "Installing dependencies..."
apt install -y wget tar curl nano

# Function to create system user
create_system_user() {
    local username=$1
    local shell=$2
    
    if id "$username" &>/dev/null; then
        log_info "User $username already exists"
    else
        if [ "$shell" == "/sbin/nologin" ]; then
            useradd -s /sbin/nologin --system -g prometheus prometheus
        else
            useradd -rs /bin/false "$username"
        fi
        log_info "Created user: $username"
    fi
}

# =================================================================================
# PROMETHEUS INSTALLATION
# =================================================================================
log_info "Starting Prometheus installation..."

# Create Prometheus user and group
log_info "Creating Prometheus user and group..."
if ! getent group prometheus >/dev/null; then
    groupadd --system prometheus
fi
create_system_user "prometheus" "/sbin/nologin"

# Create directories
log_info "Creating directories for Prometheus..."
mkdir -p /etc/prometheus
mkdir -p /var/lib/prometheus

# Download and install Prometheus
log_info "Downloading Prometheus v${PROMETHEUS_VERSION}..."
cd /tmp
PROMETHEUS_TAR="prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}.tar.gz"
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${PROMETHEUS_TAR}"

if [ ! -f "$PROMETHEUS_TAR" ]; then
    log_error "Failed to download Prometheus"
    exit 1
fi

log_info "Extracting Prometheus..."
tar xvf "$PROMETHEUS_TAR"
cd "prometheus-${PROMETHEUS_VERSION}.linux-${ARCH}"

# Move binaries
log_info "Installing Prometheus binaries..."
mv prometheus /usr/local/bin/
mv promtool /usr/local/bin/

# Set permissions
chown prometheus:prometheus /usr/local/bin/prometheus
chown prometheus:prometheus /usr/local/bin/promtool

# Move configuration files
mv prometheus.yml /etc/prometheus/
chown -R prometheus:prometheus /etc/prometheus
chown -R prometheus:prometheus /var/lib/prometheus

# Create systemd service for Prometheus
log_info "Creating Prometheus systemd service..."
cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
  --config.file=/etc/prometheus/prometheus.yml \\
  --storage.tsdb.path=/var/lib/prometheus/

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start Prometheus
log_info "Starting Prometheus service..."
systemctl daemon-reload
systemctl enable --now prometheus

# Check Prometheus status
if systemctl is-active --quiet prometheus; then
    log_info "Prometheus is running successfully"
else
    log_error "Prometheus failed to start"
    systemctl status prometheus
    exit 1
fi

# =================================================================================
# NODE EXPORTER INSTALLATION
# =================================================================================
log_info "Starting Node Exporter installation..."

# Download and install Node Exporter
log_info "Downloading Node Exporter v${NODE_EXPORTER_VERSION}..."
cd /tmp
NODE_EXPORTER_TAR="node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}.tar.gz"
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${NODE_EXPORTER_TAR}"

if [ ! -f "$NODE_EXPORTER_TAR" ]; then
    log_error "Failed to download Node Exporter"
    exit 1
fi

log_info "Extracting Node Exporter..."
tar xvf "$NODE_EXPORTER_TAR"
cd "node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}"

# Move binary
mv node_exporter /usr/local/bin/

# Create system user for Node Exporter
create_system_user "node_exporter" "/bin/false"

# Create systemd service for Node Exporter
log_info "Creating Node Exporter systemd service..."
cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOF

# Start and enable Node Exporter
log_info "Starting Node Exporter service..."
systemctl daemon-reload
systemctl enable --now node_exporter

# Check Node Exporter status
if systemctl is-active --quiet node_exporter; then
    log_info "Node Exporter is running successfully"
else
    log_error "Node Exporter failed to start"
    systemctl status node_exporter
    exit 1
fi

# Configure Prometheus to scrape Node Exporter
log_info "Configuring Prometheus to scrape Node Exporter..."
if ! grep -q "node_exporter" /etc/prometheus/prometheus.yml; then
    # Backup original config
    cp /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.bak
    
    # Create new config with node_exporter
    cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]
        labels:
          app: "node-exporter"
EOF
    
    chown prometheus:prometheus /etc/prometheus/prometheus.yml
fi

# Restart Prometheus to apply changes
log_info "Restarting Prometheus to apply configuration..."
systemctl restart prometheus

# =================================================================================
# GRAFANA INSTALLATION
# =================================================================================
log_info "Starting Grafana installation..."

# Install dependencies
apt install -y apt-transport-https software-properties-common

# Create keyrings directory
mkdir -p /etc/apt/keyrings/

# Download and store Grafana GPG key
log_info "Adding Grafana repository..."
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null

# Add Grafana APT repository
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list > /dev/null

# Update and install Grafana
apt update
apt install -y grafana

# Start and enable Grafana
log_info "Starting Grafana service..."
systemctl enable --now grafana-server

# Check Grafana status
if systemctl is-active --quiet grafana-server; then
    log_info "Grafana is running successfully"
else
    log_error "Grafana failed to start"
    systemctl status grafana-server
    exit 1
fi

# Configure firewall (if ufw is active)
if systemctl is-active --quiet ufw; then
    log_info "Configuring firewall for Grafana..."
    ufw allow 3000/tcp comment "Grafana"
fi

# =================================================================================
# COMPLETION MESSAGE
# =================================================================================
log_info "Installation completed successfully!"
echo
echo "=== SERVICES STATUS ==="
echo "Prometheus:    $(systemctl is-active prometheus)"
echo "Node Exporter: $(systemctl is-active node_exporter)"
echo "Grafana:       $(systemctl is-active grafana-server)"
echo
echo "=== ACCESS INFORMATION ==="
echo "Prometheus:    http://$(hostname -I | awk '{print $1}'):9090"
echo "Node Exporter: http://$(hostname -I | awk '{print $1}'):9100"
echo "Grafana:       http://$(hostname -I | awk '{print $1}'):3000"
echo "               Default credentials: admin / admin"
echo
echo "=== NEXT STEPS ==="
echo "1. Access Grafana at http://$(hostname -I | awk '{print $1}'):3000"
echo "2. Add Prometheus as data source: http://localhost:9090"
echo "3. Import dashboards from https://grafana.com/grafana/dashboards/"
echo
log_info "Script execution completed!"