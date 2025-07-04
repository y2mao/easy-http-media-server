#!/bin/bash

# HTTP Media Server v2 Installation Script
# This script helps you install and configure the HTTP Media Server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/http-media-server"
SERVICE_NAME="http-media-server"
USER_NAME="media-server"
GROUP_NAME="media-server"
BINARY_NAME="http-media-server"

# Functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

detect_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        print_error "Cannot detect operating system"
        exit 1
    fi
    print_info "Detected system: $OS $VER"
}

check_binary() {
    if [[ ! -f "./$BINARY_NAME" ]]; then
        print_error "Binary '$BINARY_NAME' not found in current directory"
        print_info "Please build the binary first with: go build -o $BINARY_NAME"
        exit 1
    fi
    print_success "Binary found: $BINARY_NAME"
}

create_user() {
    if ! id "$USER_NAME" &>/dev/null; then
        print_info "Creating user: $USER_NAME"
        useradd -r -s /bin/false -d $INSTALL_DIR -c "HTTP Media Server" $USER_NAME
        print_success "User created: $USER_NAME"
    else
        print_info "User already exists: $USER_NAME"
    fi
}

create_directories() {
    print_info "Creating directories..."
    mkdir -p $INSTALL_DIR
    mkdir -p $INSTALL_DIR/media
    mkdir -p /var/log/$SERVICE_NAME
    print_success "Directories created"
}

install_binary() {
    print_info "Installing binary..."
    cp ./$BINARY_NAME $INSTALL_DIR/
    chmod +x $INSTALL_DIR/$BINARY_NAME
    print_success "Binary installed to $INSTALL_DIR/$BINARY_NAME"
}

install_config() {
    if [[ -f "./config.yaml" ]]; then
        if [[ -f "$INSTALL_DIR/config.yaml" ]]; then
            print_warning "Config file already exists, backing up..."
            cp $INSTALL_DIR/config.yaml $INSTALL_DIR/config.yaml.backup.$(date +%Y%m%d_%H%M%S)
        fi
        cp ./config.yaml $INSTALL_DIR/
        print_success "Configuration file installed"
    else
        print_info "Generating default configuration..."
        $INSTALL_DIR/$BINARY_NAME -gen-config -config $INSTALL_DIR/config.yaml
        print_success "Default configuration generated"
    fi
}

set_permissions() {
    print_info "Setting permissions..."
    chown -R $USER_NAME:$GROUP_NAME $INSTALL_DIR
    chown -R $USER_NAME:$GROUP_NAME /var/log/$SERVICE_NAME
    chmod 755 $INSTALL_DIR
    chmod 644 $INSTALL_DIR/config.yaml
    chmod 755 $INSTALL_DIR/media
    print_success "Permissions set"
}

install_service() {
    if [[ -f "./$SERVICE_NAME.service" ]]; then
        print_info "Installing systemd service..."
        cp ./$SERVICE_NAME.service /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable $SERVICE_NAME
        print_success "Service installed and enabled"
    else
        print_warning "Service file not found, creating basic service..."
        cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=HTTP Media Server v2
After=network.target

[Service]
Type=simple
User=$USER_NAME
Group=$GROUP_NAME
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$BINARY_NAME -config $INSTALL_DIR/config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable $SERVICE_NAME
        print_success "Basic service created and enabled"
    fi
}

configure_firewall() {
    # Try to configure firewall if available
    if command -v ufw &> /dev/null; then
        print_info "Configuring UFW firewall..."
        ufw allow 8080/tcp
        print_success "UFW firewall configured"
    elif command -v firewall-cmd &> /dev/null; then
        print_info "Configuring firewalld..."
        firewall-cmd --permanent --add-port=8080/tcp
        firewall-cmd --reload
        print_success "Firewalld configured"
    else
        print_warning "No supported firewall found. Please manually open port 8080"
    fi
}

show_usage() {
    cat << EOF
HTTP Media Server v2 Installation Script

Usage: $0 [OPTIONS]

Options:
    --install-dir DIR    Installation directory (default: $INSTALL_DIR)
    --user USER          Service user name (default: $USER_NAME)
    --no-service         Don't install systemd service
    --no-firewall        Don't configure firewall
    --help               Show this help message

Examples:
    $0                                    # Standard installation
    $0 --install-dir /usr/local/bin       # Custom installation directory
    $0 --user httpd --no-firewall         # Custom user, no firewall config
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --user)
            USER_NAME="$2"
            GROUP_NAME="$2"
            shift 2
            ;;
        --no-service)
            NO_SERVICE=1
            shift
            ;;
        --no-firewall)
            NO_FIREWALL=1
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main installation process
main() {
    print_info "Starting HTTP Media Server v2 installation..."

    check_root
    detect_system
    check_binary

    create_user
    create_directories
    install_binary
    install_config
    set_permissions

    if [[ -z "$NO_SERVICE" ]]; then
        install_service
    fi

    if [[ -z "$NO_FIREWALL" ]]; then
        configure_firewall
    fi

    print_success "Installation completed!"
    echo
    print_info "Installation details:"
    echo "  Installation directory: $INSTALL_DIR"
    echo "  Service user: $USER_NAME"
    echo "  Configuration file: $INSTALL_DIR/config.yaml"
    echo "  Media directory: $INSTALL_DIR/media"
    echo "  Log directory: /var/log/$SERVICE_NAME"
    echo
    print_info "Next steps:"
    echo "  1. Edit configuration: nano $INSTALL_DIR/config.yaml"
    echo "  2. Add media files to: $INSTALL_DIR/media"
    echo "  3. Start the service: systemctl start $SERVICE_NAME"
    echo "  4. Check status: systemctl status $SERVICE_NAME"
    echo "  5. View logs: journalctl -u $SERVICE_NAME -f"
    echo
    print_info "Access your media server at: http://localhost:8080"

    # Ask if user wants to start the service now
    read -p "Do you want to start the service now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl start $SERVICE_NAME
        sleep 2
        if systemctl is-active --quiet $SERVICE_NAME; then
            print_success "Service started successfully!"
            print_info "Service status:"
            systemctl status $SERVICE_NAME --no-pager
        else
            print_error "Failed to start service. Check logs with: journalctl -u $SERVICE_NAME"
        fi
    fi
}

# Run main function
main "$@"
