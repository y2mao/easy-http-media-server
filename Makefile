# HTTP Media Server v2 Makefile

# Variables
BINARY_NAME=http-media-server
VERSION=2.0.0
BUILD_DIR=build
GO_FILES=$(shell find . -name "*.go" -type f)

# Default target
.PHONY: all
all: build

# Build for current platform
.PHONY: build
build:
	@echo "Building $(BINARY_NAME) v$(VERSION)..."
	@mkdir -p $(BUILD_DIR)
	go build -ldflags "-X main.version=$(VERSION)" -o $(BUILD_DIR)/$(BINARY_NAME) .
	@echo "Build completed: $(BUILD_DIR)/$(BINARY_NAME)"

# Build for all platforms
.PHONY: build-all
build-all: build-linux build-windows build-darwin

# Build for Linux
.PHONY: build-linux
build-linux:
	@echo "Building for Linux..."
	@mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=amd64 go build -ldflags "-X main.version=$(VERSION)" -o $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 .
	@echo "Linux build completed: $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64"

# Build for Windows
.PHONY: build-windows
build-windows:
	@echo "Building for Windows..."
	@mkdir -p $(BUILD_DIR)
	GOOS=windows GOARCH=amd64 go build -ldflags "-X main.version=$(VERSION)" -o $(BUILD_DIR)/$(BINARY_NAME)-windows-amd64.exe .
	@echo "Windows build completed: $(BUILD_DIR)/$(BINARY_NAME)-windows-amd64.exe"

# Build for macOS
.PHONY: build-darwin
build-darwin:
	@echo "Building for macOS..."
	@mkdir -p $(BUILD_DIR)
	GOOS=darwin GOARCH=amd64 go build -ldflags "-X main.version=$(VERSION)" -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-amd64 .
	GOOS=darwin GOARCH=arm64 go build -ldflags "-X main.version=$(VERSION)" -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-arm64 .
	@echo "macOS builds completed: $(BUILD_DIR)/$(BINARY_NAME)-darwin-*"

# Install dependencies
.PHONY: deps
deps:
	@echo "Installing dependencies..."
	go mod tidy
	go mod download

# Run the server
.PHONY: run
run: build
	@echo "Starting server..."
	./$(BUILD_DIR)/$(BINARY_NAME)

# Run with custom config
.PHONY: run-config
run-config: build
	@echo "Starting server with custom config..."
	./$(BUILD_DIR)/$(BINARY_NAME) -config config.yaml

# Generate default config
.PHONY: config
config: build
	@echo "Generating default configuration..."
	./$(BUILD_DIR)/$(BINARY_NAME) -gen-config

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	go clean

# Format code
.PHONY: fmt
fmt:
	@echo "Formatting code..."
	go fmt ./...

# Run tests
.PHONY: test
test:
	@echo "Running tests..."
	go test -v ./...

# Run linter
.PHONY: lint
lint:
	@echo "Running linter..."
	golangci-lint run

# Create release package
.PHONY: release
release: clean build-all
	@echo "Creating release packages..."
	@mkdir -p $(BUILD_DIR)/release

	# Linux package
	@mkdir -p $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-linux-amd64
	cp $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-linux-amd64/$(BINARY_NAME)
	cp config.yaml $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-linux-amd64/
	cp README.md $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-linux-amd64/
	cd $(BUILD_DIR)/release && tar -czf $(BINARY_NAME)-$(VERSION)-linux-amd64.tar.gz $(BINARY_NAME)-$(VERSION)-linux-amd64/

	# Windows package
	@mkdir -p $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-windows-amd64
	cp $(BUILD_DIR)/$(BINARY_NAME)-windows-amd64.exe $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-windows-amd64/$(BINARY_NAME).exe
	cp config.yaml $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-windows-amd64/
	cp README.md $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-windows-amd64/
	cd $(BUILD_DIR)/release && zip -r $(BINARY_NAME)-$(VERSION)-windows-amd64.zip $(BINARY_NAME)-$(VERSION)-windows-amd64/

	# macOS Intel package
	@mkdir -p $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-darwin-amd64
	cp $(BUILD_DIR)/$(BINARY_NAME)-darwin-amd64 $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-darwin-amd64/$(BINARY_NAME)
	cp config.yaml $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-darwin-amd64/
	cp README.md $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-darwin-amd64/
	cd $(BUILD_DIR)/release && tar -czf $(BINARY_NAME)-$(VERSION)-darwin-amd64.tar.gz $(BINARY_NAME)-$(VERSION)-darwin-amd64/

	# macOS Apple Silicon package
	@mkdir -p $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-darwin-arm64
	cp $(BUILD_DIR)/$(BINARY_NAME)-darwin-arm64 $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-darwin-arm64/$(BINARY_NAME)
	cp config.yaml $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-darwin-arm64/
	cp README.md $(BUILD_DIR)/release/$(BINARY_NAME)-$(VERSION)-darwin-arm64/
	cd $(BUILD_DIR)/release && tar -czf $(BINARY_NAME)-$(VERSION)-darwin-arm64.tar.gz $(BINARY_NAME)-$(VERSION)-darwin-arm64/

	@echo "Release packages created in $(BUILD_DIR)/release/"

# Show help
.PHONY: help
help:
	@echo "HTTP Media Server v$(VERSION) - Available Make targets:"
	@echo ""
	@echo "  build         Build binary for current platform"
	@echo "  build-all     Build binaries for all platforms"
	@echo "  build-linux   Build binary for Linux"
	@echo "  build-windows Build binary for Windows"
	@echo "  build-darwin  Build binary for macOS"
	@echo "  deps          Install Go dependencies"
	@echo "  run           Build and run the server"
	@echo "  run-config    Build and run with custom config"
	@echo "  config        Generate default configuration file"
	@echo "  clean         Clean build artifacts"
	@echo "  fmt           Format Go source code"
	@echo "  test          Run tests"
	@echo "  lint          Run linter"
	@echo "  release       Create release packages"
	@echo "  help          Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make build    # Build for current platform"
	@echo "  make run      # Build and start server"
	@echo "  make config   # Generate config.yaml"
	@echo "  make release  # Create release packages"
