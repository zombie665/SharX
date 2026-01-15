#!/bin/bash

# ============================================
# 3X-UI NEW Installation Script
# Author: @konspic
# Version: 3.0.0b
# ============================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Default values
DEFAULT_PANEL_PORT=2053
DEFAULT_SUB_PORT=2096
DEFAULT_DB_PASSWORD="change_this_password"
INSTALL_DIR="/opt/3x-ui-new"
COMPOSE_FILE="docker-compose.yml"

# Print banner
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║     ██████╗ ██╗  ██╗      ██╗   ██╗██╗    ███╗   ██╗███████╗██╗    ██╗  ║"
    echo "║     ╚════██╗╚██╗██╔╝      ██║   ██║██║    ████╗  ██║██╔════╝██║    ██║  ║"
    echo "║      █████╔╝ ╚███╔╝ █████╗██║   ██║██║    ██╔██╗ ██║█████╗  ██║ █╗ ██║  ║"
    echo "║      ╚═══██╗ ██╔██╗ ╚════╝██║   ██║██║    ██║╚██╗██║██╔══╝  ██║███╗██║  ║"
    echo "║     ██████╔╝██╔╝ ██╗      ╚██████╔╝██║    ██║ ╚████║███████╗╚███╔███╔╝  ║"
    echo "║     ╚═════╝ ╚═╝  ╚═╝       ╚═════╝ ╚═╝    ╚═╝  ╚═══╝╚══════╝ ╚══╝╚══╝   ║"
    echo "║                                                               ║"
    echo "║              Next Generation Panel Management                 ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Print colored message
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root!"
        echo -e "Please run: ${YELLOW}sudo bash install.sh${NC}"
        exit 1
    fi
}

# Check system requirements
check_system() {
    print_info "Checking system requirements..."
    
    # Check if Ubuntu
    if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
        print_warning "This script is designed for Ubuntu. Proceed with caution on other systems."
    fi
    
    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
        print_error "Unsupported architecture: $ARCH"
        exit 1
    fi
    
    print_success "System check passed!"
}

# Install Docker if not present
install_docker() {
    if command -v docker &> /dev/null; then
        print_success "Docker is already installed: $(docker --version)"
        return 0
    fi

    print_info "Installing Docker..."
    
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Update package index
    apt-get update -y
    
    # Install prerequisites
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    print_success "Docker installed successfully!"
}

# Install Docker Compose (standalone) if not present
install_docker_compose() {
    # Check for docker compose plugin
    if docker compose version &> /dev/null; then
        print_success "Docker Compose plugin is available: $(docker compose version)"
        return 0
    fi
    
    # Install as plugin if missing
    print_info "Installing Docker Compose plugin..."
    apt-get update -y
    apt-get install -y docker-compose-plugin
    
    print_success "Docker Compose installed successfully!"
}

# Generate random password
generate_password() {
    local length=${1:-24}
    tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c "$length"
}

# Get server IP
get_server_ip() {
    local ip
    ip=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s icanhazip.com 2>/dev/null || curl -4 -s ipinfo.io/ip 2>/dev/null)
    echo "$ip"
}

# Generate self-signed certificate for IP
generate_self_signed_cert() {
    local cert_dir="$1"
    local domain_or_ip="$2"
    local days="${3:-365}"
    
    print_info "Generating self-signed certificate for $domain_or_ip..."
    
    mkdir -p "$cert_dir"
    
    # Generate private key
    openssl genrsa -out "$cert_dir/privkey.pem" 2048
    
    # Generate certificate
    openssl req -new -x509 \
        -key "$cert_dir/privkey.pem" \
        -out "$cert_dir/fullchain.pem" \
        -days "$days" \
        -subj "/CN=$domain_or_ip" \
        -addext "subjectAltName=IP:$domain_or_ip,DNS:$domain_or_ip"
    
    chmod 600 "$cert_dir/privkey.pem"
    chmod 644 "$cert_dir/fullchain.pem"
    
    print_success "Self-signed certificate generated!"
}

# Install certbot and get Let's Encrypt certificate
install_letsencrypt_cert() {
    local domain="$1"
    local cert_dir="$2"
    local email="${3:-admin@$domain}"
    
    print_info "Installing Let's Encrypt certificate for $domain..."
    
    # Install certbot
    if ! command -v certbot &> /dev/null; then
        apt-get update -y
        apt-get install -y certbot
    fi
    
    # Stop any service on port 80
    docker stop $(docker ps -q) 2>/dev/null || true
    
    # Get certificate
    certbot certonly --standalone \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        -d "$domain" \
        --preferred-challenges http
    
    # Copy certificates
    mkdir -p "$cert_dir"
    cp "/etc/letsencrypt/live/$domain/fullchain.pem" "$cert_dir/"
    cp "/etc/letsencrypt/live/$domain/privkey.pem" "$cert_dir/"
    
    chmod 600 "$cert_dir/privkey.pem"
    chmod 644 "$cert_dir/fullchain.pem"
    
    # Setup auto-renewal cron job
    setup_cert_renewal "$domain" "$cert_dir"
    
    print_success "Let's Encrypt certificate installed!"
}

# Setup certificate auto-renewal
setup_cert_renewal() {
    local domain="$1"
    local cert_dir="$2"
    
    print_info "Setting up certificate auto-renewal..."
    
    # Create renewal script
    cat > /etc/cron.daily/3xui-cert-renewal << EOF
#!/bin/bash
# 3X-UI Certificate Auto-Renewal Script

certbot renew --quiet --post-hook "cp /etc/letsencrypt/live/$domain/fullchain.pem $cert_dir/ && cp /etc/letsencrypt/live/$domain/privkey.pem $cert_dir/ && cd $INSTALL_DIR && docker compose restart 3xui"
EOF
    
    chmod +x /etc/cron.daily/3xui-cert-renewal
    
    print_success "Auto-renewal configured!"
}

# Setup self-signed certificate renewal (for IP)
setup_self_signed_renewal() {
    local cert_dir="$1"
    local ip="$2"
    local days="${3:-30}"
    
    print_info "Setting up self-signed certificate auto-renewal every $days days..."
    
    # Create renewal script
    cat > /etc/cron.monthly/3xui-self-signed-renewal << EOF
#!/bin/bash
# 3X-UI Self-Signed Certificate Auto-Renewal Script

# Generate new certificate
openssl genrsa -out "$cert_dir/privkey.pem" 2048
openssl req -new -x509 \\
    -key "$cert_dir/privkey.pem" \\
    -out "$cert_dir/fullchain.pem" \\
    -days $days \\
    -subj "/CN=$ip" \\
    -addext "subjectAltName=IP:$ip,DNS:$ip"

chmod 600 "$cert_dir/privkey.pem"
chmod 644 "$cert_dir/fullchain.pem"

# Restart container
cd $INSTALL_DIR && docker compose restart 3xui
EOF
    
    chmod +x /etc/cron.monthly/3xui-self-signed-renewal
    
    print_success "Self-signed certificate auto-renewal configured!"
}

# Create docker-compose.yml with host network
create_compose_host() {
    local panel_port="$1"
    local sub_port="$2"
    local db_password="$3"
    
    cat > "$INSTALL_DIR/$COMPOSE_FILE" << EOF
services:
  3xui:
    image: registry.konstpic.ru/3x-ui/3xui:3.0.0b
    container_name: 3xui_app
    network_mode: host
    volumes:
      - \$PWD/cert/:/root/cert/
    environment:
      # Xray settings
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "true"
      
      # Panel ports (for host mode, change in panel settings)
      # Web UI: $panel_port
      # Subscriptions: $sub_port
      
      # PostgreSQL settings
      XUI_DB_HOST: 127.0.0.1
      XUI_DB_PORT: 5432
      XUI_DB_USER: xui_user
      XUI_DB_PASSWORD: $db_password
      XUI_DB_NAME: xui_db
      XUI_DB_SSLMODE: disable
    depends_on:
      postgres:
        condition: service_healthy
    tty: true
    restart: unless-stopped

  postgres:
    image: registry.konstpic.ru/3x-ui/postgres:16-alpine
    container_name: 3xui_postgres
    network_mode: host
    environment:
      POSTGRES_USER: xui_user
      POSTGRES_PASSWORD: $db_password
      POSTGRES_DB: xui_db
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -p 5432 -U xui_user -d xui_db"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

volumes:
  postgres_data:
EOF
    
    print_success "Docker Compose file created with host network mode!"
}

# Create docker-compose.yml with bridge network (port mapping)
create_compose_bridge() {
    local panel_port="$1"
    local sub_port="$2"
    local db_password="$3"
    
    cat > "$INSTALL_DIR/$COMPOSE_FILE" << EOF
services:
  3xui:
    image: registry.konstpic.ru/3x-ui/3xui:3.0.0b
    container_name: 3xui_app
    ports:
      - "$panel_port:2053"   # Web UI
      - "$sub_port:2096"     # Subscriptions
      # Add more inbound ports as needed:
      # - "443:443"
      # - "8443:8443"
    volumes:
      - \$PWD/cert/:/root/cert/
    environment:
      # Xray settings
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "true"
      
      # PostgreSQL settings
      XUI_DB_HOST: postgres
      XUI_DB_PORT: 5432
      XUI_DB_USER: xui_user
      XUI_DB_PASSWORD: $db_password
      XUI_DB_NAME: xui_db
      XUI_DB_SSLMODE: disable
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - xui_network
    tty: true
    restart: unless-stopped

  postgres:
    image: registry.konstpic.ru/3x-ui/postgres:16-alpine
    container_name: 3xui_postgres
    environment:
      POSTGRES_USER: xui_user
      POSTGRES_PASSWORD: $db_password
      POSTGRES_DB: xui_db
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - xui_network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -p 5432 -U xui_user -d xui_db"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

networks:
  xui_network:
    driver: bridge

volumes:
  postgres_data:
EOF
    
    print_success "Docker Compose file created with bridge network mode!"
}

# Save configuration
save_config() {
    local panel_port="$1"
    local sub_port="$2"
    local db_password="$3"
    local network_mode="$4"
    local cert_type="$5"
    local domain_or_ip="$6"
    
    cat > "$INSTALL_DIR/.3xui-config" << EOF
# 3X-UI Configuration
# Generated: $(date)

PANEL_PORT=$panel_port
SUB_PORT=$sub_port
DB_PASSWORD=$db_password
NETWORK_MODE=$network_mode
CERT_TYPE=$cert_type
DOMAIN_OR_IP=$domain_or_ip
INSTALL_DIR=$INSTALL_DIR
EOF
    
    chmod 600 "$INSTALL_DIR/.3xui-config"
}

# Load configuration
load_config() {
    if [[ -f "$INSTALL_DIR/.3xui-config" ]]; then
        source "$INSTALL_DIR/.3xui-config"
        return 0
    fi
    return 1
}

# Start services
start_services() {
    print_info "Starting 3X-UI services..."
    cd "$INSTALL_DIR"
    docker compose up -d
    
    # Wait for services to start
    sleep 5
    
    if docker compose ps | grep -q "Up"; then
        print_success "Services started successfully!"
    else
        print_error "Failed to start services. Check logs with: docker compose logs"
        exit 1
    fi
}

# Stop services
stop_services() {
    print_info "Stopping 3X-UI services..."
    cd "$INSTALL_DIR"
    docker compose down
    print_success "Services stopped!"
}

# Update services
update_services() {
    print_info "Updating 3X-UI..."
    cd "$INSTALL_DIR"
    
    print_info "Step 1/3: Stopping containers..."
    docker compose down
    
    print_info "Step 2/3: Pulling new images..."
    docker compose pull
    
    print_info "Step 3/3: Starting containers..."
    docker compose up -d
    
    # Cleanup old images
    print_info "Cleaning up old images..."
    docker image prune -f
    
    print_success "3X-UI updated successfully!"
}

# Show service status
show_status() {
    print_info "3X-UI Service Status:"
    echo ""
    cd "$INSTALL_DIR"
    docker compose ps
    echo ""
    
    if load_config; then
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${WHITE}Configuration:${NC}"
        echo -e "  Panel Port:    ${GREEN}$PANEL_PORT${NC}"
        echo -e "  Sub Port:      ${GREEN}$SUB_PORT${NC}"
        echo -e "  Network Mode:  ${GREEN}$NETWORK_MODE${NC}"
        echo -e "  Certificate:   ${GREEN}$CERT_TYPE${NC}"
        echo -e "  Domain/IP:     ${GREEN}$DOMAIN_OR_IP${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        local server_ip=$(get_server_ip)
        echo ""
        echo -e "${WHITE}Access Panel:${NC}"
        if [[ "$CERT_TYPE" == "letsencrypt" ]]; then
            echo -e "  ${GREEN}https://$DOMAIN_OR_IP:$PANEL_PORT${NC}"
        else
            echo -e "  ${GREEN}http://$server_ip:$PANEL_PORT${NC}"
            echo -e "  ${YELLOW}(Self-signed HTTPS also available)${NC}"
        fi
    fi
}

# Show logs
show_logs() {
    cd "$INSTALL_DIR"
    echo -e "${CYAN}Select container:${NC}"
    echo "1) 3X-UI Panel"
    echo "2) PostgreSQL"
    echo "3) All"
    echo ""
    read -p "Choice [1-3]: " log_choice
    
    case $log_choice in
        1) docker compose logs -f 3xui ;;
        2) docker compose logs -f postgres ;;
        3) docker compose logs -f ;;
        *) docker compose logs -f ;;
    esac
}

# Change panel port
change_panel_port() {
    if ! load_config; then
        print_error "Configuration not found. Please run installation first."
        return 1
    fi
    
    read -p "Enter new panel port [$PANEL_PORT]: " new_port
    new_port=${new_port:-$PANEL_PORT}
    
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        print_error "Invalid port number!"
        return 1
    fi
    
    print_info "Changing panel port to $new_port..."
    
    if [[ "$NETWORK_MODE" == "bridge" ]]; then
        sed -i "s/\"$PANEL_PORT:2053\"/\"$new_port:2053\"/" "$INSTALL_DIR/$COMPOSE_FILE"
    fi
    
    PANEL_PORT=$new_port
    save_config "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "$NETWORK_MODE" "$CERT_TYPE" "$DOMAIN_OR_IP"
    
    print_info "Restarting services..."
    cd "$INSTALL_DIR"
    docker compose down
    docker compose up -d
    
    print_success "Panel port changed to $new_port!"
}

# Change subscription port
change_sub_port() {
    if ! load_config; then
        print_error "Configuration not found. Please run installation first."
        return 1
    fi
    
    read -p "Enter new subscription port [$SUB_PORT]: " new_port
    new_port=${new_port:-$SUB_PORT}
    
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        print_error "Invalid port number!"
        return 1
    fi
    
    print_info "Changing subscription port to $new_port..."
    
    if [[ "$NETWORK_MODE" == "bridge" ]]; then
        sed -i "s/\"$SUB_PORT:2096\"/\"$new_port:2096\"/" "$INSTALL_DIR/$COMPOSE_FILE"
    fi
    
    SUB_PORT=$new_port
    save_config "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "$NETWORK_MODE" "$CERT_TYPE" "$DOMAIN_OR_IP"
    
    print_info "Restarting services..."
    cd "$INSTALL_DIR"
    docker compose down
    docker compose up -d
    
    print_success "Subscription port changed to $new_port!"
}

# Change database password
change_db_password() {
    if ! load_config; then
        print_error "Configuration not found. Please run installation first."
        return 1
    fi
    
    echo -e "${YELLOW}WARNING: Changing database password requires data migration!${NC}"
    read -p "Generate new password? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        return 0
    fi
    
    local new_password=$(generate_password 24)
    
    print_info "New password: $new_password"
    print_warning "Save this password! It will be needed for recovery."
    
    read -p "Continue with this password? [y/N]: " confirm2
    
    if [[ "$confirm2" != "y" && "$confirm2" != "Y" ]]; then
        return 0
    fi
    
    print_info "Changing database password..."
    
    # Update compose file
    sed -i "s/XUI_DB_PASSWORD: .*/XUI_DB_PASSWORD: $new_password/" "$INSTALL_DIR/$COMPOSE_FILE"
    sed -i "s/POSTGRES_PASSWORD: .*/POSTGRES_PASSWORD: $new_password/" "$INSTALL_DIR/$COMPOSE_FILE"
    
    # Stop services and remove volume
    cd "$INSTALL_DIR"
    docker compose down
    docker volume rm 3x-ui-new_postgres_data 2>/dev/null || docker volume rm $(docker volume ls -q | grep postgres_data) 2>/dev/null || true
    
    DB_PASSWORD=$new_password
    save_config "$PANEL_PORT" "$SUB_PORT" "$DB_PASSWORD" "$NETWORK_MODE" "$CERT_TYPE" "$DOMAIN_OR_IP"
    
    # Start services
    docker compose up -d
    
    print_success "Database password changed!"
    echo -e "${RED}WARNING: All previous data has been reset!${NC}"
}

# Renew certificate
renew_certificate() {
    if ! load_config; then
        print_error "Configuration not found. Please run installation first."
        return 1
    fi
    
    local cert_dir="$INSTALL_DIR/cert"
    
    if [[ "$CERT_TYPE" == "letsencrypt" ]]; then
        print_info "Renewing Let's Encrypt certificate..."
        certbot renew --force-renewal
        cp "/etc/letsencrypt/live/$DOMAIN_OR_IP/fullchain.pem" "$cert_dir/"
        cp "/etc/letsencrypt/live/$DOMAIN_OR_IP/privkey.pem" "$cert_dir/"
    else
        print_info "Regenerating self-signed certificate..."
        generate_self_signed_cert "$cert_dir" "$DOMAIN_OR_IP" 30
    fi
    
    cd "$INSTALL_DIR"
    docker compose restart 3xui
    
    print_success "Certificate renewed!"
}

# Uninstall
uninstall() {
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                     WARNING: UNINSTALL                        ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This will:"
    echo "  - Stop and remove all containers"
    echo "  - Remove Docker volumes (ALL DATA WILL BE LOST)"
    echo "  - Remove installation directory"
    echo ""
    read -p "Are you sure you want to uninstall? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        return 0
    fi
    
    read -p "Type 'DELETE' to confirm: " confirm2
    
    if [[ "$confirm2" != "DELETE" ]]; then
        print_info "Uninstall cancelled."
        return 0
    fi
    
    print_info "Uninstalling 3X-UI..."
    
    cd "$INSTALL_DIR" 2>/dev/null || true
    docker compose down -v 2>/dev/null || true
    
    # Remove cron jobs
    rm -f /etc/cron.daily/3xui-cert-renewal 2>/dev/null || true
    rm -f /etc/cron.monthly/3xui-self-signed-renewal 2>/dev/null || true
    
    # Remove installation directory
    rm -rf "$INSTALL_DIR"
    
    print_success "3X-UI uninstalled successfully!"
}

# Full installation wizard
install_wizard() {
    print_banner
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}          3X-UI NEW Installation Wizard${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    check_root
    check_system
    
    # Step 1: Install Docker
    echo ""
    echo -e "${PURPLE}[Step 1/6]${NC} Docker Installation"
    install_docker
    install_docker_compose
    
    # Step 2: Network mode
    echo ""
    echo -e "${PURPLE}[Step 2/6]${NC} Network Configuration"
    echo -e "${CYAN}Choose network mode:${NC}"
    echo "1) Host network (recommended for advanced users)"
    echo "   - Direct access to all ports"
    echo "   - Better performance"
    echo "   - Requires manual port configuration in panel"
    echo ""
    echo "2) Bridge network with port mapping (recommended)"
    echo "   - Isolated containers"
    echo "   - Easy port management"
    echo "   - Need to expose inbound ports manually"
    echo ""
    read -p "Select [1-2, default: 2]: " network_choice
    network_choice=${network_choice:-2}
    
    local network_mode="bridge"
    if [[ "$network_choice" == "1" ]]; then
        network_mode="host"
    fi
    
    # Step 3: Port configuration
    echo ""
    echo -e "${PURPLE}[Step 3/6]${NC} Port Configuration"
    read -p "Panel port [$DEFAULT_PANEL_PORT]: " panel_port
    panel_port=${panel_port:-$DEFAULT_PANEL_PORT}
    
    read -p "Subscription port [$DEFAULT_SUB_PORT]: " sub_port
    sub_port=${sub_port:-$DEFAULT_SUB_PORT}
    
    # Validate ports
    if ! [[ "$panel_port" =~ ^[0-9]+$ ]] || [ "$panel_port" -lt 1 ] || [ "$panel_port" -gt 65535 ]; then
        print_error "Invalid panel port!"
        exit 1
    fi
    if ! [[ "$sub_port" =~ ^[0-9]+$ ]] || [ "$sub_port" -lt 1 ] || [ "$sub_port" -gt 65535 ]; then
        print_error "Invalid subscription port!"
        exit 1
    fi
    
    # Step 4: Database password
    echo ""
    echo -e "${PURPLE}[Step 4/6]${NC} Database Configuration"
    echo -e "${CYAN}Database password options:${NC}"
    echo "1) Generate secure random password (recommended)"
    echo "2) Enter custom password"
    echo ""
    read -p "Select [1-2, default: 1]: " pwd_choice
    pwd_choice=${pwd_choice:-1}
    
    local db_password
    if [[ "$pwd_choice" == "2" ]]; then
        read -sp "Enter database password: " db_password
        echo ""
        if [[ ${#db_password} -lt 8 ]]; then
            print_warning "Password is too short. Generating secure password instead."
            db_password=$(generate_password 24)
        fi
    else
        db_password=$(generate_password 24)
    fi
    
    echo -e "${GREEN}Database password: $db_password${NC}"
    echo -e "${YELLOW}Please save this password!${NC}"
    echo ""
    
    # Step 5: SSL Certificate
    echo ""
    echo -e "${PURPLE}[Step 5/6]${NC} SSL Certificate Configuration"
    local server_ip=$(get_server_ip)
    echo -e "Your server IP: ${GREEN}$server_ip${NC}"
    echo ""
    echo -e "${CYAN}Certificate options:${NC}"
    echo "1) Self-signed certificate for IP (30 days, auto-renewal)"
    echo "2) Let's Encrypt certificate for domain (90 days, auto-renewal)"
    echo "3) Skip certificate setup (configure later)"
    echo ""
    read -p "Select [1-3, default: 1]: " cert_choice
    cert_choice=${cert_choice:-1}
    
    local cert_type="none"
    local domain_or_ip="$server_ip"
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR/cert"
    
    case $cert_choice in
        1)
            cert_type="self-signed"
            domain_or_ip="$server_ip"
            generate_self_signed_cert "$INSTALL_DIR/cert" "$server_ip" 30
            setup_self_signed_renewal "$INSTALL_DIR/cert" "$server_ip" 30
            ;;
        2)
            cert_type="letsencrypt"
            read -p "Enter your domain name: " domain_or_ip
            if [[ -z "$domain_or_ip" ]]; then
                print_error "Domain name is required!"
                exit 1
            fi
            read -p "Enter email for Let's Encrypt [$domain_or_ip admin]: " cert_email
            cert_email=${cert_email:-"admin@$domain_or_ip"}
            install_letsencrypt_cert "$domain_or_ip" "$INSTALL_DIR/cert" "$cert_email"
            ;;
        3)
            cert_type="none"
            print_warning "Skipping certificate setup. Remember to configure SSL later!"
            ;;
    esac
    
    # Step 6: Create and start services
    echo ""
    echo -e "${PURPLE}[Step 6/6]${NC} Creating and Starting Services"
    
    if [[ "$network_mode" == "host" ]]; then
        create_compose_host "$panel_port" "$sub_port" "$db_password"
    else
        create_compose_bridge "$panel_port" "$sub_port" "$db_password"
    fi
    
    # Save configuration
    save_config "$panel_port" "$sub_port" "$db_password" "$network_mode" "$cert_type" "$domain_or_ip"
    
    # Start services
    start_services
    
    # Final summary
    print_banner
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Installation Completed Successfully!            ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${WHITE}Configuration Summary:${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  Installation Dir:  ${CYAN}$INSTALL_DIR${NC}"
    echo -e "  Panel Port:        ${CYAN}$panel_port${NC}"
    echo -e "  Subscription Port: ${CYAN}$sub_port${NC}"
    echo -e "  Network Mode:      ${CYAN}$network_mode${NC}"
    echo -e "  Certificate:       ${CYAN}$cert_type${NC}"
    echo -e "  Database Password: ${CYAN}$db_password${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${WHITE}Access your panel:${NC}"
    if [[ "$cert_type" == "letsencrypt" ]]; then
        echo -e "  ${GREEN}https://$domain_or_ip:$panel_port${NC}"
    else
        echo -e "  ${GREEN}http://$server_ip:$panel_port${NC}"
    fi
    echo ""
    echo -e "${WHITE}Default credentials:${NC}"
    echo -e "  Username: ${CYAN}admin${NC}"
    echo -e "  Password: ${CYAN}admin${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Please change default credentials after first login!${NC}"
    echo ""
    echo -e "${WHITE}Management commands:${NC}"
    echo -e "  ${CYAN}bash install.sh${NC} - Open management menu"
    echo ""
}

# Main menu
main_menu() {
    while true; do
        print_banner
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${WHITE}                    Management Menu${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  ${GREEN}1)${NC}  Install 3X-UI"
        echo -e "  ${GREEN}2)${NC}  Update 3X-UI"
        echo -e "  ${GREEN}3)${NC}  Start Services"
        echo -e "  ${GREEN}4)${NC}  Stop Services"
        echo -e "  ${GREEN}5)${NC}  Restart Services"
        echo -e "  ${GREEN}6)${NC}  Show Status"
        echo -e "  ${GREEN}7)${NC}  View Logs"
        echo ""
        echo -e "  ${YELLOW}8)${NC}  Change Panel Port"
        echo -e "  ${YELLOW}9)${NC}  Change Subscription Port"
        echo -e "  ${YELLOW}10)${NC} Change Database Password"
        echo -e "  ${YELLOW}11)${NC} Renew Certificate"
        echo ""
        echo -e "  ${RED}12)${NC} Uninstall"
        echo -e "  ${WHITE}0)${NC}  Exit"
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        read -p "Select option [0-12]: " choice
        
        case $choice in
            1) install_wizard ;;
            2) update_services ;;
            3) start_services ;;
            4) stop_services ;;
            5) 
                cd "$INSTALL_DIR"
                docker compose restart
                print_success "Services restarted!"
                ;;
            6) show_status ;;
            7) show_logs ;;
            8) change_panel_port ;;
            9) change_sub_port ;;
            10) change_db_password ;;
            11) renew_certificate ;;
            12) uninstall ;;
            0) 
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                print_error "Invalid option!"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Script entry point
main() {
    # Check if config exists (already installed)
    if [[ -f "$INSTALL_DIR/.3xui-config" ]]; then
        main_menu
    else
        # First run - check for arguments
        case "${1:-}" in
            install|--install|-i)
                check_root
                install_wizard
                ;;
            menu|--menu|-m)
                check_root
                main_menu
                ;;
            *)
                # Interactive selection for first run
                print_banner
                echo ""
                echo -e "${CYAN}Welcome to 3X-UI NEW Installer!${NC}"
                echo ""
                echo "1) Start Installation"
                echo "2) Open Menu (for manual configuration)"
                echo "0) Exit"
                echo ""
                read -p "Select option: " first_choice
                
                case $first_choice in
                    1)
                        check_root
                        install_wizard
                        ;;
                    2)
                        check_root
                        main_menu
                        ;;
                    0|*)
                        echo -e "${GREEN}Goodbye!${NC}"
                        exit 0
                        ;;
                esac
                ;;
        esac
    fi
}

# Run main
main "$@"
