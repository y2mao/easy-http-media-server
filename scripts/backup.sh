#!/bin/bash

# HTTP Media Server v2 - Backup Script
# This script creates backups of media files and configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_CONFIG_FILE="config.yaml"
DEFAULT_BACKUP_DIR="./backups"
DEFAULT_MEDIA_DIR="./media"

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

show_usage() {
    cat << EOF
HTTP Media Server v2 - Backup Script

Usage: $0 [OPTIONS]

Options:
    -c, --config FILE       Configuration file path (default: $DEFAULT_CONFIG_FILE)
    -b, --backup-dir DIR    Backup directory (default: $DEFAULT_BACKUP_DIR)
    -m, --media-dir DIR     Media directory (default: auto-detect from config)
    --config-only           Backup only configuration files
    --media-only            Backup only media files
    --compress              Create compressed archives
    --exclude PATTERN       Exclude files matching pattern (can be used multiple times)
    --dry-run               Show what would be backed up without actually doing it
    -h, --help              Show this help message

Examples:
    $0                                      # Full backup with defaults
    $0 -b /backup/media-server              # Backup to specific directory
    $0 --config-only                        # Backup only configuration
    $0 --media-only --compress              # Backup only media files, compressed
    $0 --exclude "*.tmp" --exclude "*.log"  # Exclude temporary and log files
    $0 --dry-run                           # Preview what would be backed up

EOF
}

# Parse media directory from config file
parse_media_dir() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        # Extract media directory from YAML config
        local media_dir=$(grep -E "^\s*directory:" "$config_file" | sed 's/.*directory:\s*//' | sed 's/["'\'']*//g' | xargs)
        if [[ -n "$media_dir" ]]; then
            echo "$media_dir"
        else
            echo "$DEFAULT_MEDIA_DIR"
        fi
    else
        echo "$DEFAULT_MEDIA_DIR"
    fi
}

# Create backup directory
create_backup_dir() {
    local backup_dir="$1"
    if [[ ! -d "$backup_dir" ]]; then
        print_info "Creating backup directory: $backup_dir"
        mkdir -p "$backup_dir"
    fi
}

# Backup configuration files
backup_config() {
    local config_file="$1"
    local backup_dir="$2"
    local timestamp="$3"
    local dry_run="$4"

    local config_backup_dir="$backup_dir/config-$timestamp"

    if [[ "$dry_run" == "true" ]]; then
        print_info "[DRY RUN] Would backup configuration to: $config_backup_dir"
        if [[ -f "$config_file" ]]; then
            print_info "[DRY RUN] Would copy: $config_file"
        fi
        return
    fi

    print_info "Backing up configuration files..."
    mkdir -p "$config_backup_dir"

    # Backup main config file
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "$config_backup_dir/"
        print_success "Configuration file backed up: $config_file"
    else
        print_warning "Configuration file not found: $config_file"
    fi

    # Backup any additional config files
    for file in *.yaml *.yml *.conf *.json; do
        if [[ -f "$file" && "$file" != "$config_file" ]]; then
            cp "$file" "$config_backup_dir/"
            print_info "Additional config backed up: $file"
        fi
    done

    print_success "Configuration backup completed: $config_backup_dir"
}

# Backup media files
backup_media() {
    local media_dir="$1"
    local backup_dir="$2"
    local timestamp="$3"
    local compress="$4"
    local excludes=("${!5}")
    local dry_run="$6"

    if [[ ! -d "$media_dir" ]]; then
        print_error "Media directory not found: $media_dir"
        return 1
    fi

    local media_backup_dir="$backup_dir/media-$timestamp"

    # Build exclude parameters for rsync
    local exclude_params=()
    for pattern in "${excludes[@]}"; do
        exclude_params+=("--exclude=$pattern")
    done

    # Always exclude common unwanted files
    exclude_params+=("--exclude=.DS_Store")
    exclude_params+=("--exclude=Thumbs.db")
    exclude_params+=("--exclude=*.tmp")
    exclude_params+=("--exclude=*.temp")

    if [[ "$dry_run" == "true" ]]; then
        print_info "[DRY RUN] Would backup media from: $media_dir"
        print_info "[DRY RUN] Would backup media to: $media_backup_dir"
        if [[ "$compress" == "true" ]]; then
            print_info "[DRY RUN] Would create compressed archive: $media_backup_dir.tar.gz"
        fi
        return
    fi

    print_info "Backing up media files from: $media_dir"

    if [[ "$compress" == "true" ]]; then
        print_info "Creating compressed media backup..."
        tar czf "$media_backup_dir.tar.gz" "${exclude_params[@]/#--exclude=/--exclude=}" -C "$(dirname "$media_dir")" "$(basename "$media_dir")" 2>/dev/null || {
            # Fallback to rsync + tar if tar exclude doesn't work properly
            mkdir -p "$media_backup_dir"
            rsync -av "${exclude_params[@]}" "$media_dir/" "$media_backup_dir/"
            tar czf "$media_backup_dir.tar.gz" -C "$backup_dir" "$(basename "$media_backup_dir")"
            rm -rf "$media_backup_dir"
        }
        print_success "Compressed media backup completed: $media_backup_dir.tar.gz"
    else
        mkdir -p "$media_backup_dir"
        rsync -av "${exclude_params[@]}" "$media_dir/" "$media_backup_dir/"
        print_success "Media backup completed: $media_backup_dir"
    fi
}

# Get backup size
get_backup_size() {
    local path="$1"
    if [[ -d "$path" ]]; then
        du -sh "$path" 2>/dev/null | cut -f1
    elif [[ -f "$path" ]]; then
        ls -lh "$path" 2>/dev/null | awk '{print $5}'
    else
        echo "0"
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    local backup_dir="$1"
    local keep_days="${2:-30}"
    local dry_run="$3"

    print_info "Cleaning up backups older than $keep_days days..."

    if [[ "$dry_run" == "true" ]]; then
        find "$backup_dir" -type d -name "*-20*" -mtime +$keep_days 2>/dev/null | while read -r old_backup; do
            print_info "[DRY RUN] Would remove old backup: $old_backup"
        done
        find "$backup_dir" -type f -name "*.tar.gz" -mtime +$keep_days 2>/dev/null | while read -r old_backup; do
            print_info "[DRY RUN] Would remove old backup: $old_backup"
        done
        return
    fi

    local removed_count=0
    find "$backup_dir" -type d -name "*-20*" -mtime +$keep_days 2>/dev/null | while read -r old_backup; do
        rm -rf "$old_backup"
        print_info "Removed old backup directory: $old_backup"
        ((removed_count++))
    done

    find "$backup_dir" -type f -name "*.tar.gz" -mtime +$keep_days 2>/dev/null | while read -r old_backup; do
        rm -f "$old_backup"
        print_info "Removed old backup file: $old_backup"
        ((removed_count++))
    done

    if [[ $removed_count -eq 0 ]]; then
        print_info "No old backups to remove"
    fi
}

# Main function
main() {
    local config_file="$DEFAULT_CONFIG_FILE"
    local backup_dir="$DEFAULT_BACKUP_DIR"
    local media_dir=""
    local config_only=false
    local media_only=false
    local compress=false
    local dry_run=false
    local excludes=()
    local keep_days=30

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                config_file="$2"
                shift 2
                ;;
            -b|--backup-dir)
                backup_dir="$2"
                shift 2
                ;;
            -m|--media-dir)
                media_dir="$2"
                shift 2
                ;;
            --config-only)
                config_only=true
                shift
                ;;
            --media-only)
                media_only=true
                shift
                ;;
            --compress)
                compress=true
                shift
                ;;
            --exclude)
                excludes+=("$2")
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --keep-days)
                keep_days="$2"
                shift 2
                ;;
            -h|--help)
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

    # Auto-detect media directory if not specified
    if [[ -z "$media_dir" ]]; then
        media_dir=$(parse_media_dir "$config_file")
    fi

    # Validate inputs
    if [[ "$config_only" == "true" && "$media_only" == "true" ]]; then
        print_error "Cannot specify both --config-only and --media-only"
        exit 1
    fi

    # Create timestamp
    local timestamp=$(date +"%Y%m%d_%H%M%S")

    print_info "HTTP Media Server v2 - Backup Started"
    print_info "Timestamp: $timestamp"
    print_info "Configuration file: $config_file"
    print_info "Media directory: $media_dir"
    print_info "Backup directory: $backup_dir"
    if [[ "$dry_run" == "true" ]]; then
        print_warning "DRY RUN MODE - No actual changes will be made"
    fi
    echo

    # Create backup directory
    if [[ "$dry_run" != "true" ]]; then
        create_backup_dir "$backup_dir"
    fi

    # Perform backups
    if [[ "$media_only" != "true" ]]; then
        backup_config "$config_file" "$backup_dir" "$timestamp" "$dry_run"
        echo
    fi

    if [[ "$config_only" != "true" ]]; then
        backup_media "$media_dir" "$backup_dir" "$timestamp" "$compress" excludes[@] "$dry_run"
        echo
    fi

    # Cleanup old backups
    cleanup_old_backups "$backup_dir" "$keep_days" "$dry_run"
    echo

    # Show summary
    if [[ "$dry_run" != "true" ]]; then
        print_success "Backup completed successfully!"
        print_info "Backup location: $backup_dir"

        # Show backup sizes
        if [[ "$config_only" != "true" ]]; then
            if [[ "$compress" == "true" ]]; then
                local media_backup_file="$backup_dir/media-$timestamp.tar.gz"
                if [[ -f "$media_backup_file" ]]; then
                    local media_size=$(get_backup_size "$media_backup_file")
                    print_info "Media backup size: $media_size"
                fi
            else
                local media_backup_dir="$backup_dir/media-$timestamp"
                if [[ -d "$media_backup_dir" ]]; then
                    local media_size=$(get_backup_size "$media_backup_dir")
                    print_info "Media backup size: $media_size"
                fi
            fi
        fi

        if [[ "$media_only" != "true" ]]; then
            local config_backup_dir="$backup_dir/config-$timestamp"
            if [[ -d "$config_backup_dir" ]]; then
                local config_size=$(get_backup_size "$config_backup_dir")
                print_info "Config backup size: $config_size"
            fi
        fi

        local total_size=$(get_backup_size "$backup_dir")
        print_info "Total backup directory size: $total_size"
    else
        print_info "Dry run completed. Use without --dry-run to perform actual backup."
    fi
}

# Check dependencies
if ! command -v rsync &> /dev/null; then
    print_error "rsync is required but not installed"
    exit 1
fi

# Run main function
main "$@"
