package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// Config holds the application configuration
type Config struct {
	Server ServerConfig `yaml:"server"`
	Media  MediaConfig  `yaml:"media"`
}

// ServerConfig holds server-related configuration
type ServerConfig struct {
	Port int    `yaml:"port"`
	Host string `yaml:"host"`
}

// MediaConfig holds media directory configuration
type MediaConfig struct {
	Directory string `yaml:"directory"`
}

// LoadConfig loads configuration from a YAML file
func LoadConfig(configPath string) (*Config, error) {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var config Config
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	// Set default values if not specified
	if config.Server.Host == "" {
		config.Server.Host = "0.0.0.0"
	}
	if config.Server.Port == 0 {
		config.Server.Port = 8080
	}
	if config.Media.Directory == "" {
		config.Media.Directory = "./media"
	}

	// Validate configuration
	if err := config.Validate(); err != nil {
		return nil, fmt.Errorf("configuration validation failed: %w", err)
	}

	return &config, nil
}

// CreateDefaultConfig creates a default configuration file
func CreateDefaultConfig(configPath string) error {
	defaultConfig := Config{
		Server: ServerConfig{
			Port: 8080,
			Host: "0.0.0.0",
		},
		Media: MediaConfig{
			Directory: "./media",
		},
	}

	data, err := yaml.Marshal(&defaultConfig)
	if err != nil {
		return fmt.Errorf("failed to marshal default config: %w", err)
	}

	if err := os.WriteFile(configPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write default config file: %w", err)
	}

	return nil
}

// Validate validates the configuration values
func (c *Config) Validate() error {
	// Validate server configuration
	if c.Server.Port < 1 || c.Server.Port > 65535 {
		return fmt.Errorf("invalid port number: %d (must be between 1-65535)", c.Server.Port)
	}

	if c.Server.Host == "" {
		return fmt.Errorf("host cannot be empty")
	}

	// Validate media configuration
	if c.Media.Directory == "" {
		return fmt.Errorf("media directory cannot be empty")
	}

	// Check if media directory path is valid
	if _, err := os.Stat(c.Media.Directory); err != nil {
		if os.IsNotExist(err) {
			// Directory doesn't exist, but that's okay - we'll create it
			return nil
		}
		return fmt.Errorf("media directory is not accessible: %w", err)
	}

	return nil
}

// GetAbsMediaPath returns the absolute path of the media directory
func (c *Config) GetAbsMediaPath() (string, error) {
	absPath, err := filepath.Abs(c.Media.Directory)
	if err != nil {
		return "", fmt.Errorf("failed to get absolute path for media directory: %w", err)
	}
	return absPath, nil
}

// IsValidMediaPath checks if a given path is within the media directory
func (c *Config) IsValidMediaPath(requestPath string) (bool, error) {
	absMediaPath, err := c.GetAbsMediaPath()
	if err != nil {
		return false, err
	}

	// Clean the request path and join with media directory
	cleanPath := filepath.Clean(requestPath)
	if cleanPath == "." || cleanPath == "/" {
		return true, nil
	}

	fullPath := filepath.Join(absMediaPath, cleanPath)
	absFullPath, err := filepath.Abs(fullPath)
	if err != nil {
		return false, fmt.Errorf("failed to get absolute path: %w", err)
	}

	// Check if the path is within the media directory
	return strings.HasPrefix(absFullPath, absMediaPath), nil
}
