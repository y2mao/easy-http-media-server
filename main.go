package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
)

const (
	defaultConfigFile = "config.yaml"
	version           = "2.0.0"
)

func main() {
	var (
		configFile = flag.String("config", defaultConfigFile, "Path to configuration file")
		showVer    = flag.Bool("version", false, "Show version information")
		help       = flag.Bool("help", false, "Show help information")
		genConfig  = flag.Bool("gen-config", false, "Generate default configuration file")
	)

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "HTTP Media Server v%s\n\n", version)
		fmt.Fprintf(os.Stderr, "Usage: %s [options]\n\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  %s                    # Start server with default config\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  %s -config /path/to/config.yaml\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  %s -gen-config        # Generate default config file\n", os.Args[0])
	}

	flag.Parse()

	if *help {
		flag.Usage()
		os.Exit(0)
	}

	if *showVer {
		fmt.Printf("HTTP Media Server v%s\n", version)
		os.Exit(0)
	}

	if *genConfig {
		if err := generateConfig(*configFile); err != nil {
			log.Fatalf("Failed to generate config file: %v", err)
		}
		fmt.Printf("Default configuration file generated: %s\n", *configFile)
		os.Exit(0)
	}

	// Load configuration
	config, err := loadOrCreateConfig(*configFile)
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Validate media directory
	if err := validateMediaDirectory(config.Media.Directory); err != nil {
		log.Fatalf("Media directory validation failed: %v", err)
	}

	// Create and start server
	server := NewMediaServer(config)
	log.Printf("HTTP Media Server v%s starting...", version)

	if err := server.Start(); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

// loadOrCreateConfig loads existing config or creates a default one
func loadOrCreateConfig(configPath string) (*Config, error) {
	// Check if config file exists
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		log.Printf("Configuration file not found, creating default: %s", configPath)
		if err := CreateDefaultConfig(configPath); err != nil {
			return nil, fmt.Errorf("failed to create default config: %w", err)
		}
	}

	config, err := LoadConfig(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to load config: %w", err)
	}

	log.Printf("Configuration loaded from: %s", configPath)
	return config, nil
}

// generateConfig generates a default configuration file
func generateConfig(configPath string) error {
	// Create directory if it doesn't exist
	dir := filepath.Dir(configPath)
	if dir != "." {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("failed to create config directory: %w", err)
		}
	}

	return CreateDefaultConfig(configPath)
}

// validateMediaDirectory validates that the media directory exists and is accessible
func validateMediaDirectory(mediaDir string) error {
	absPath, err := filepath.Abs(mediaDir)
	if err != nil {
		return fmt.Errorf("failed to get absolute path: %w", err)
	}

	info, err := os.Stat(absPath)
	if err != nil {
		if os.IsNotExist(err) {
			log.Printf("Media directory doesn't exist, creating: %s", absPath)
			if err := os.MkdirAll(absPath, 0755); err != nil {
				return fmt.Errorf("failed to create media directory: %w", err)
			}
			return nil
		}
		return fmt.Errorf("failed to access media directory: %w", err)
	}

	if !info.IsDir() {
		return fmt.Errorf("media path is not a directory: %s", absPath)
	}

	// Check if directory is readable
	entries, err := os.ReadDir(absPath)
	if err != nil {
		return fmt.Errorf("media directory is not readable: %w", err)
	}

	log.Printf("Media directory validated: %s (%d items)", absPath, len(entries))
	return nil
}
