#!/bin/bash

# HTTP Media Server v2 - Quick Demo Script
# This script sets up and runs a quick demo of the media server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

print_header() {
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} HTTP Media Server v2.0 - Quick Demo${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
}

# Check if binary exists
check_binary() {
    if [[ ! -f "./build/http-media-server" ]]; then
        if [[ -f "./http-media-server" ]]; then
            BINARY_PATH="./http-media-server"
        else
            print_error "Binary not found. Building now..."
            if command -v make &> /dev/null; then
                make build
                BINARY_PATH="./build/http-media-server"
            else
                go build -o http-media-server
                BINARY_PATH="./http-media-server"
            fi
        fi
    else
        BINARY_PATH="./build/http-media-server"
    fi
}

# Setup demo environment
setup_demo() {
    print_info "Setting up demo environment..."

    # Create demo media directory
    mkdir -p demo-media/movies
    mkdir -p demo-media/tv-shows
    mkdir -p demo-media/music
    mkdir -p demo-media/photos

    # Create sample files
    cat > demo-media/README.txt << 'EOF'
Welcome to HTTP Media Server v2 Demo!

This demo directory contains sample files to demonstrate the server's capabilities.

Features demonstrated:
- Directory browsing with nice UI
- File type icons and categorization
- Support for various media formats
- Responsive design
- Kodi compatibility

Try accessing the server at: http://localhost:8080
EOF

    # Create sample movie files (empty files for demo)
    touch "demo-media/movies/Sample Movie 1.mp4"
    touch "demo-media/movies/Sample Movie 2.avi"
    touch "demo-media/movies/Sample Movie 3.mkv"

    # Create sample TV show structure
    mkdir -p "demo-media/tv-shows/Sample Show S01"
    touch "demo-media/tv-shows/Sample Show S01/Episode 01.mp4"
    touch "demo-media/tv-shows/Sample Show S01/Episode 02.mp4"
    touch "demo-media/tv-shows/Sample Show S01/Episode 03.mp4"

    # Create sample music files
    touch "demo-media/music/Sample Song 1.mp3"
    touch "demo-media/music/Sample Song 2.flac"
    touch "demo-media/music/Sample Song 3.wav"

    # Create sample photo files
    touch "demo-media/photos/Sample Photo 1.jpg"
    touch "demo-media/photos/Sample Photo 2.png"
    touch "demo-media/photos/Sample Photo 3.gif"

    # Create demo config
    cat > demo-config.yaml << 'EOF'
# HTTP Media Server v2 - Demo Configuration
server:
  port: 8080
  host: "127.0.0.1"

media:
  directory: "./demo-media"
EOF

    print_success "Demo environment created!"
    print_info "Demo media directory: ./demo-media"
    print_info "Demo config file: ./demo-config.yaml"
}

# Check if port is available
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_warning "Port $port is already in use!"
        print_info "Please stop any services using port $port or modify demo-config.yaml"
        return 1
    fi
    return 0
}

# Start demo server
start_demo() {
    print_info "Starting HTTP Media Server v2 demo..."

    if ! check_port 8080; then
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Demo cancelled"
            exit 0
        fi
    fi

    print_success "Starting server with demo configuration..."
    print_info "Server will be available at: http://localhost:8080"
    print_info "Press Ctrl+C to stop the server"
    echo

    # Start server in foreground
    exec "$BINARY_PATH" -config demo-config.yaml
}

# Cleanup demo
cleanup_demo() {
    print_info "Cleaning up demo environment..."
    rm -rf demo-media/
    rm -f demo-config.yaml
    print_success "Demo cleanup completed!"
}

# Show usage
show_usage() {
    cat << EOF
HTTP Media Server v2 - Quick Demo Script

Usage: $0 [COMMAND]

Commands:
    start     Setup and start demo server (default)
    setup     Setup demo environment only
    cleanup   Remove demo files
    help      Show this help message

Examples:
    $0                # Setup and start demo
    $0 start          # Same as above
    $0 setup          # Only create demo files
    $0 cleanup        # Remove demo files

The demo will:
1. Create sample media files and directories
2. Generate a demo configuration
3. Start the server on http://localhost:8080
4. Display instructions for testing

EOF
}

# Handle Ctrl+C
cleanup_on_exit() {
    echo
    print_info "Demo stopped"
    print_info "Demo files are preserved. Run '$0 cleanup' to remove them."
    exit 0
}

# Main function
main() {
    local command="${1:-start}"

    case "$command" in
        start)
            print_header
            trap cleanup_on_exit INT TERM
            check_binary
            setup_demo
            echo
            print_info "Demo setup complete! Starting server..."
            print_info "You can now:"
            echo "  1. Open http://localhost:8080 in your browser"
            echo "  2. Browse the demo media files"
            echo "  3. Test with Kodi or other media players"
            echo "  4. Check health endpoint: http://localhost:8080/health"
            echo "  5. View API info: http://localhost:8080/api/info"
            echo
            start_demo
            ;;
        setup)
            print_header
            check_binary
            setup_demo
            echo
            print_info "Demo environment setup complete!"
            print_info "To start the server manually:"
            echo "  $BINARY_PATH -config demo-config.yaml"
            ;;
        cleanup)
            cleanup_demo
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            print_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
