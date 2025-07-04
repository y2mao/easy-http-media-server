#!/bin/bash

# HTTP Media Server v2 - Monitoring Script
# This script monitors the server status and can send alerts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_CONFIG_FILE="config.yaml"
DEFAULT_HOST="localhost"
DEFAULT_PORT="8080"
DEFAULT_CHECK_INTERVAL=30
DEFAULT_TIMEOUT=10
DEFAULT_LOG_FILE="/var/log/http-media-server-monitor.log"

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

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ -w "$(dirname "$LOG_FILE")" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi

    case "$level" in
        "INFO")  print_info "$message" ;;
        "SUCCESS") print_success "$message" ;;
        "WARNING") print_warning "$message" ;;
        "ERROR") print_error "$message" ;;
        *) echo "$message" ;;
    esac
}

show_usage() {
    cat << EOF
HTTP Media Server v2 - Monitoring Script

Usage: $0 [OPTIONS]

Options:
    -c, --config FILE       Configuration file path (default: $DEFAULT_CONFIG_FILE)
    -h, --host HOST         Server host (default: auto-detect from config)
    -p, --port PORT         Server port (default: auto-detect from config)
    -i, --interval SECONDS  Check interval in seconds (default: $DEFAULT_CHECK_INTERVAL)
    -t, --timeout SECONDS   Request timeout in seconds (default: $DEFAULT_TIMEOUT)
    -l, --log-file FILE     Log file path (default: $DEFAULT_LOG_FILE)
    --once                  Run check once and exit
    --daemon                Run as daemon (background)
    --email EMAIL           Send email alerts to this address
    --webhook URL           Send webhook alerts to this URL
    --slack-webhook URL     Send Slack webhook alerts
    --check-disk            Monitor disk space of media directory
    --disk-threshold PCT    Disk space warning threshold percentage (default: 90)
    --help                  Show this help message

Examples:
    $0                                      # Monitor with defaults
    $0 --once                              # Single check
    $0 -i 60 --email admin@example.com     # Check every 60s with email alerts
    $0 --daemon --webhook http://alerts.example.com/webhook
    $0 --check-disk --disk-threshold 85    # Monitor with disk space check

EOF
}

# Parse configuration file
parse_config() {
    local config_file="$1"

    if [[ -f "$config_file" ]]; then
        # Extract host and port from YAML config
        local host=$(grep -E "^\s*host:" "$config_file" | sed 's/.*host:\s*//' | sed 's/["'\'']*//g' | xargs)
        local port=$(grep -E "^\s*port:" "$config_file" | sed 's/.*port:\s*//' | sed 's/["'\'']*//g' | xargs)
        local media_dir=$(grep -E "^\s*directory:" "$config_file" | sed 's/.*directory:\s*//' | sed 's/["'\'']*//g' | xargs)

        if [[ -n "$host" && "$host" != "0.0.0.0" ]]; then
            SERVER_HOST="$host"
        fi

        if [[ -n "$port" ]]; then
            SERVER_PORT="$port"
        fi

        if [[ -n "$media_dir" ]]; then
            MEDIA_DIR="$media_dir"
        fi
    fi
}

# Check if server is running
check_server_health() {
    local host="$1"
    local port="$2"
    local timeout="$3"

    # Check main endpoint
    if curl -sf --max-time "$timeout" "http://$host:$port/" > /dev/null 2>&1; then
        return 0
    fi

    return 1
}

# Check health endpoint
check_health_endpoint() {
    local host="$1"
    local port="$2"
    local timeout="$3"

    local response=$(curl -sf --max-time "$timeout" "http://$host:$port/health" 2>/dev/null)

    if [[ $? -eq 0 ]]; then
        local status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        if [[ "$status" == "healthy" ]]; then
            return 0
        fi
    fi

    return 1
}

# Check disk space
check_disk_space() {
    local media_dir="$1"
    local threshold="$2"

    if [[ ! -d "$media_dir" ]]; then
        return 1
    fi

    local usage=$(df "$media_dir" | tail -1 | awk '{print $5}' | sed 's/%//')

    if [[ "$usage" -gt "$threshold" ]]; then
        log_message "WARNING" "Disk space usage is ${usage}% (threshold: ${threshold}%)"
        return 1
    fi

    return 0
}

# Send email alert
send_email_alert() {
    local email="$1"
    local subject="$2"
    local message="$3"

    if command -v mail &> /dev/null; then
        echo "$message" | mail -s "$subject" "$email"
    elif command -v sendmail &> /dev/null; then
        {
            echo "To: $email"
            echo "Subject: $subject"
            echo ""
            echo "$message"
        } | sendmail "$email"
    else
        log_message "ERROR" "No mail command available for sending email alerts"
        return 1
    fi
}

# Send webhook alert
send_webhook_alert() {
    local webhook_url="$1"
    local message="$2"
    local status="$3"

    local payload=$(cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "service": "HTTP Media Server v2",
    "status": "$status",
    "message": "$message",
    "host": "$(hostname)"
}
EOF
)

    curl -sf -X POST -H "Content-Type: application/json" -d "$payload" "$webhook_url" > /dev/null 2>&1
}

# Send Slack alert
send_slack_alert() {
    local webhook_url="$1"
    local message="$2"
    local status="$3"

    local color="good"
    local emoji=":white_check_mark:"

    if [[ "$status" == "error" ]]; then
        color="danger"
        emoji=":x:"
    elif [[ "$status" == "warning" ]]; then
        color="warning"
        emoji=":warning:"
    fi

    local payload=$(cat << EOF
{
    "attachments": [
        {
            "color": "$color",
            "title": "HTTP Media Server v2 Alert",
            "text": "$emoji $message",
            "fields": [
                {
                    "title": "Host",
                    "value": "$(hostname)",
                    "short": true
                },
                {
                    "title": "Time",
                    "value": "$(date)",
                    "short": true
                }
            ]
        }
    ]
}
EOF
)

    curl -sf -X POST -H "Content-Type: application/json" -d "$payload" "$webhook_url" > /dev/null 2>&1
}

# Send alert
send_alert() {
    local message="$1"
    local status="$2"

    if [[ -n "$EMAIL_ALERT" ]]; then
        local subject="HTTP Media Server v2 Alert - $status"
        send_email_alert "$EMAIL_ALERT" "$subject" "$message"
    fi

    if [[ -n "$WEBHOOK_URL" ]]; then
        send_webhook_alert "$WEBHOOK_URL" "$message" "$status"
    fi

    if [[ -n "$SLACK_WEBHOOK" ]]; then
        send_slack_alert "$SLACK_WEBHOOK" "$message" "$status"
    fi
}

# Monitor function
monitor_server() {
    local consecutive_failures=0
    local last_status="unknown"

    while true; do
        local current_time=$(date '+%Y-%m-%d %H:%M:%S')
        local server_ok=true
        local issues=()

        # Check server health
        if ! check_server_health "$SERVER_HOST" "$SERVER_PORT" "$TIMEOUT"; then
            server_ok=false
            issues+=("Server is not responding")
        fi

        # Check health endpoint
        if [[ "$server_ok" == "true" ]] && ! check_health_endpoint "$SERVER_HOST" "$SERVER_PORT" "$TIMEOUT"; then
            server_ok=false
            issues+=("Health endpoint reports unhealthy status")
        fi

        # Check disk space if enabled
        if [[ "$CHECK_DISK" == "true" && -n "$MEDIA_DIR" ]]; then
            if ! check_disk_space "$MEDIA_DIR" "$DISK_THRESHOLD"; then
                issues+=("Disk space usage above threshold")
            fi
        fi

        # Handle status changes
        if [[ "$server_ok" == "true" ]]; then
            if [[ "$last_status" != "healthy" ]]; then
                log_message "SUCCESS" "Server is healthy"
                if [[ "$last_status" == "unhealthy" ]]; then
                    send_alert "HTTP Media Server v2 is now healthy" "recovery"
                fi
            fi
            consecutive_failures=0
            last_status="healthy"
        else
            consecutive_failures=$((consecutive_failures + 1))
            local issue_text=$(IFS='; '; echo "${issues[*]}")

            if [[ "$last_status" != "unhealthy" ]]; then
                log_message "ERROR" "Server is unhealthy: $issue_text"
                send_alert "HTTP Media Server v2 is unhealthy: $issue_text" "error"
            fi

            last_status="unhealthy"
        fi

        # Log periodic status if healthy
        if [[ "$server_ok" == "true" && $(($(date +%s) % 300)) -eq 0 ]]; then
            log_message "INFO" "Server is running normally"
        fi

        # Break if running once
        if [[ "$RUN_ONCE" == "true" ]]; then
            break
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# Daemon mode
run_as_daemon() {
    local pid_file="/var/run/http-media-server-monitor.pid"

    # Check if already running
    if [[ -f "$pid_file" ]]; then
        local existing_pid=$(cat "$pid_file")
        if kill -0 "$existing_pid" 2>/dev/null; then
            print_error "Monitor is already running with PID $existing_pid"
            exit 1
        else
            rm -f "$pid_file"
        fi
    fi

    # Start as daemon
    log_message "INFO" "Starting HTTP Media Server monitor as daemon"

    # Fork to background
    (
        echo $$ > "$pid_file"
        exec > /dev/null 2>&1
        monitor_server
        rm -f "$pid_file"
    ) &

    print_success "Monitor started as daemon with PID $(cat "$pid_file")"
}

# Main function
main() {
    local config_file="$DEFAULT_CONFIG_FILE"
    local check_interval="$DEFAULT_CHECK_INTERVAL"
    local timeout="$DEFAULT_TIMEOUT"
    local log_file="$DEFAULT_LOG_FILE"
    local run_once=false
    local daemon_mode=false
    local check_disk=false
    local disk_threshold=90
    local email_alert=""
    local webhook_url=""
    local slack_webhook=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                config_file="$2"
                shift 2
                ;;
            -h|--host)
                SERVER_HOST="$2"
                shift 2
                ;;
            -p|--port)
                SERVER_PORT="$2"
                shift 2
                ;;
            -i|--interval)
                check_interval="$2"
                shift 2
                ;;
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            -l|--log-file)
                log_file="$2"
                shift 2
                ;;
            --once)
                run_once=true
                shift
                ;;
            --daemon)
                daemon_mode=true
                shift
                ;;
            --email)
                email_alert="$2"
                shift 2
                ;;
            --webhook)
                webhook_url="$2"
                shift 2
                ;;
            --slack-webhook)
                slack_webhook="$2"
                shift 2
                ;;
            --check-disk)
                check_disk=true
                shift
                ;;
            --disk-threshold)
                disk_threshold="$2"
                shift 2
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

    # Set global variables
    SERVER_HOST="${SERVER_HOST:-$DEFAULT_HOST}"
    SERVER_PORT="${SERVER_PORT:-$DEFAULT_PORT}"
    CHECK_INTERVAL="$check_interval"
    TIMEOUT="$timeout"
    LOG_FILE="$log_file"
    RUN_ONCE="$run_once"
    CHECK_DISK="$check_disk"
    DISK_THRESHOLD="$disk_threshold"
    EMAIL_ALERT="$email_alert"
    WEBHOOK_URL="$webhook_url"
    SLACK_WEBHOOK="$slack_webhook"
    MEDIA_DIR=""

    # Parse configuration file
    parse_config "$config_file"

    # Validate dependencies
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed"
        exit 1
    fi

    print_info "HTTP Media Server v2 - Monitor Starting"
    print_info "Server: http://$SERVER_HOST:$SERVER_PORT"
    print_info "Check interval: ${CHECK_INTERVAL}s"
    print_info "Timeout: ${TIMEOUT}s"
    print_info "Log file: $LOG_FILE"

    if [[ "$CHECK_DISK" == "true" ]]; then
        print_info "Disk monitoring: enabled (threshold: ${DISK_THRESHOLD}%)"
        print_info "Media directory: ${MEDIA_DIR:-not detected}"
    fi

    if [[ -n "$EMAIL_ALERT" ]]; then
        print_info "Email alerts: $EMAIL_ALERT"
    fi

    if [[ -n "$WEBHOOK_URL" ]]; then
        print_info "Webhook alerts: $WEBHOOK_URL"
    fi

    if [[ -n "$SLACK_WEBHOOK" ]]; then
        print_info "Slack alerts: enabled"
    fi

    echo

    # Run monitor
    if [[ "$daemon_mode" == "true" ]]; then
        run_as_daemon
    else
        monitor_server
    fi
}

# Run main function
main "$@"
