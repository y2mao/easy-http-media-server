#!/bin/bash

# HTTP Media Server v2 - Performance Testing Script
# This script performs various performance tests on the media server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_HOST="localhost"
DEFAULT_PORT="8080"
DEFAULT_CONCURRENT_USERS=10
DEFAULT_DURATION=30
DEFAULT_TEST_FILE_SIZE="10M"

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
HTTP Media Server v2 - Performance Testing Script

Usage: $0 [OPTIONS]

Options:
    -h, --host HOST         Server host (default: $DEFAULT_HOST)
    -p, --port PORT         Server port (default: $DEFAULT_PORT)
    -c, --concurrent N      Number of concurrent users (default: $DEFAULT_CONCURRENT_USERS)
    -d, --duration SECONDS  Test duration in seconds (default: $DEFAULT_DURATION)
    -s, --size SIZE         Test file size (default: $DEFAULT_TEST_FILE_SIZE)
    --create-test-files     Create test files for benchmarking
    --directory-test        Test directory browsing performance
    --file-test             Test file serving performance
    --range-test            Test HTTP range request performance
    --all-tests             Run all performance tests
    --apache-bench          Use Apache Bench (ab) if available
    --curl-test             Use curl for basic testing
    --help                  Show this help message

Test Types:
    directory-test          Measures directory listing performance
    file-test              Measures file download performance
    range-test             Measures streaming/range request performance
    concurrent-test        Measures performance under concurrent load

Examples:
    $0 --all-tests                          # Run all tests
    $0 --directory-test -c 20 -d 60         # Directory test with 20 users for 60s
    $0 --file-test --create-test-files      # File test with generated test files
    $0 --apache-bench --concurrent 50       # Apache bench test with 50 concurrent users

EOF
}

# Check dependencies
check_dependencies() {
    local missing_deps=()

    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi

    if [[ "$USE_APACHE_BENCH" == "true" ]] && ! command -v ab &> /dev/null; then
        print_warning "Apache Bench (ab) not found, falling back to curl"
        USE_APACHE_BENCH=false
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

# Create test files
create_test_files() {
    local test_dir="./test-media"

    print_info "Creating test files in $test_dir..."

    mkdir -p "$test_dir"

    # Create files of different sizes
    local sizes=("1M" "5M" "10M" "50M" "100M")

    for size in "${sizes[@]}"; do
        local filename="test-file-${size}.bin"
        local filepath="$test_dir/$filename"

        if [[ ! -f "$filepath" ]]; then
            print_info "Creating test file: $filename ($size)"
            dd if=/dev/urandom of="$filepath" bs=1024 count=$(echo "$size" | sed 's/M//' | awk '{print $1 * 1024}') 2>/dev/null
        fi
    done

    # Create directory structure
    mkdir -p "$test_dir/subdir1"
    mkdir -p "$test_dir/subdir2/nested"

    # Create small files for directory listing tests
    for i in {1..50}; do
        echo "Test file content $i" > "$test_dir/small-file-$i.txt"
    done

    print_success "Test files created in $test_dir"
    print_info "Don't forget to update your config to serve from $test_dir for testing"
}

# Test server availability
test_server_availability() {
    local host="$1"
    local port="$2"

    print_info "Testing server availability at http://$host:$port"

    if curl -sf --max-time 5 "http://$host:$port/health" > /dev/null 2>&1; then
        print_success "Server is responding"
        return 0
    elif curl -sf --max-time 5 "http://$host:$port/" > /dev/null 2>&1; then
        print_success "Server is responding (health endpoint not available)"
        return 0
    else
        print_error "Server is not responding"
        return 1
    fi
}

# Directory browsing performance test
test_directory_performance() {
    local host="$1"
    local port="$2"
    local concurrent="$3"
    local duration="$4"

    print_info "Testing directory browsing performance..."
    print_info "Concurrent users: $concurrent, Duration: ${duration}s"

    local url="http://$host:$port/"
    local temp_dir=$(mktemp -d)
    local results_file="$temp_dir/directory_results.txt"

    # Run concurrent requests
    local pids=()
    local start_time=$(date +%s)
    local end_time=$((start_time + duration))

    for ((i=1; i<=concurrent; i++)); do
        (
            local requests=0
            local errors=0
            while [[ $(date +%s) -lt $end_time ]]; do
                if curl -sf --max-time 10 "$url" > /dev/null 2>&1; then
                    ((requests++))
                else
                    ((errors++))
                fi
            done
            echo "$requests $errors" >> "$results_file"
        ) &
        pids+=($!)
    done

    # Wait for all background processes
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # Calculate results
    local total_requests=0
    local total_errors=0

    while read -r requests errors; do
        total_requests=$((total_requests + requests))
        total_errors=$((total_errors + errors))
    done < "$results_file"

    local rps=$(echo "scale=2; $total_requests / $duration" | bc 2>/dev/null || echo "N/A")
    local error_rate=$(echo "scale=2; ($total_errors * 100) / ($total_requests + $total_errors)" | bc 2>/dev/null || echo "0")

    print_success "Directory browsing test completed"
    echo "  Total requests: $total_requests"
    echo "  Total errors: $total_errors"
    echo "  Requests per second: $rps"
    echo "  Error rate: ${error_rate}%"

    rm -rf "$temp_dir"
}

# File serving performance test
test_file_performance() {
    local host="$1"
    local port="$2"
    local concurrent="$3"
    local duration="$4"
    local test_file="$5"

    print_info "Testing file serving performance..."
    print_info "Test file: $test_file"
    print_info "Concurrent users: $concurrent, Duration: ${duration}s"

    local url="http://$host:$port/$test_file"

    # Check if test file exists
    if ! curl -sf --head "$url" > /dev/null 2>&1; then
        print_error "Test file not accessible: $url"
        return 1
    fi

    if [[ "$USE_APACHE_BENCH" == "true" ]]; then
        test_file_with_apache_bench "$url" "$concurrent" "$duration"
    else
        test_file_with_curl "$url" "$concurrent" "$duration"
    fi
}

# File test with Apache Bench
test_file_with_apache_bench() {
    local url="$1"
    local concurrent="$2"
    local duration="$3"

    local total_requests=$((duration * concurrent * 2)) # Estimate

    print_info "Running Apache Bench test..."
    ab -n "$total_requests" -c "$concurrent" -g /tmp/ab_results.tsv "$url" 2>/dev/null || {
        print_error "Apache Bench test failed"
        return 1
    }
}

# File test with curl
test_file_with_curl() {
    local url="$1"
    local concurrent="$2"
    local duration="$3"

    local temp_dir=$(mktemp -d)
    local results_file="$temp_dir/file_results.txt"
    local timing_file="$temp_dir/timing.txt"

    # Run concurrent downloads
    local pids=()
    local start_time=$(date +%s)
    local end_time=$((start_time + duration))

    for ((i=1; i<=concurrent; i++)); do
        (
            local requests=0
            local errors=0
            local total_time=0

            while [[ $(date +%s) -lt $end_time ]]; do
                local start_req=$(date +%s.%N)
                if curl -sf --max-time 30 "$url" -o /dev/null 2>&1; then
                    local end_req=$(date +%s.%N)
                    local req_time=$(echo "$end_req - $start_req" | bc 2>/dev/null || echo "0")
                    total_time=$(echo "$total_time + $req_time" | bc 2>/dev/null || echo "$total_time")
                    ((requests++))
                else
                    ((errors++))
                fi
            done
            echo "$requests $errors $total_time" >> "$results_file"
        ) &
        pids+=($!)
    done

    # Wait for all background processes
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # Calculate results
    local total_requests=0
    local total_errors=0
    local total_time=0

    while read -r requests errors time; do
        total_requests=$((total_requests + requests))
        total_errors=$((total_errors + errors))
        total_time=$(echo "$total_time + $time" | bc 2>/dev/null || echo "$total_time")
    done < "$results_file"

    local rps=$(echo "scale=2; $total_requests / $duration" | bc 2>/dev/null || echo "N/A")
    local avg_time=$(echo "scale=3; $total_time / $total_requests" | bc 2>/dev/null || echo "N/A")
    local error_rate=$(echo "scale=2; ($total_errors * 100) / ($total_requests + $total_errors)" | bc 2>/dev/null || echo "0")

    print_success "File serving test completed"
    echo "  Total requests: $total_requests"
    echo "  Total errors: $total_errors"
    echo "  Requests per second: $rps"
    echo "  Average response time: ${avg_time}s"
    echo "  Error rate: ${error_rate}%"

    rm -rf "$temp_dir"
}

# HTTP Range request test
test_range_performance() {
    local host="$1"
    local port="$2"
    local test_file="$3"

    print_info "Testing HTTP Range request performance..."

    local url="http://$host:$port/$test_file"

    # Test various range requests
    local ranges=("0-1023" "1024-2047" "0-" "-1024")

    for range in "${ranges[@]}"; do
        print_info "Testing range: bytes=$range"

        local start_time=$(date +%s.%N)
        local status=$(curl -sf -H "Range: bytes=$range" -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
        local end_time=$(date +%s.%N)

        local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "N/A")

        if [[ "$status" == "206" ]]; then
            print_success "Range $range: ${duration}s (HTTP $status)"
        else
            print_warning "Range $range: ${duration}s (HTTP $status - expected 206)"
        fi
    done
}

# Memory and resource usage test
test_resource_usage() {
    local host="$1"
    local port="$2"
    local concurrent="$3"
    local duration="$4"

    print_info "Testing resource usage under load..."

    # Find server process
    local server_pid=$(pgrep -f "http-media-server" | head -1)

    if [[ -z "$server_pid" ]]; then
        print_warning "Could not find server process for resource monitoring"
        return 1
    fi

    print_info "Monitoring server process: $server_pid"

    # Start resource monitoring
    local monitor_file=$(mktemp)
    (
        while kill -0 "$server_pid" 2>/dev/null; do
            ps -p "$server_pid" -o pid,%cpu,%mem,rss,vsz >> "$monitor_file" 2>/dev/null || break
            sleep 1
        done
    ) &
    local monitor_pid=$!

    # Run load test
    local url="http://$host:$port/"
    local pids=()
    local end_time=$(($(date +%s) + duration))

    for ((i=1; i<=concurrent; i++)); do
        (
            while [[ $(date +%s) -lt $end_time ]]; do
                curl -sf --max-time 5 "$url" > /dev/null 2>&1
                sleep 0.1
            done
        ) &
        pids+=($!)
    done

    # Wait for load test to complete
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # Stop monitoring
    kill "$monitor_pid" 2>/dev/null || true

    # Analyze results
    if [[ -s "$monitor_file" ]]; then
        local max_cpu=$(awk 'NR>1 {print $2}' "$monitor_file" | sort -nr | head -1)
        local max_mem=$(awk 'NR>1 {print $3}' "$monitor_file" | sort -nr | head -1)
        local max_rss=$(awk 'NR>1 {print $4}' "$monitor_file" | sort -nr | head -1)

        print_success "Resource usage test completed"
        echo "  Peak CPU usage: ${max_cpu}%"
        echo "  Peak memory usage: ${max_mem}%"
        echo "  Peak RSS: ${max_rss}KB"
    else
        print_warning "No resource data collected"
    fi

    rm -f "$monitor_file"
}

# Generate performance report
generate_report() {
    local host="$1"
    local port="$2"
    local report_file="performance-report-$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "HTTP Media Server v2 - Performance Test Report"
        echo "============================================="
        echo "Date: $(date)"
        echo "Server: http://$host:$port"
        echo "Test configuration:"
        echo "  Concurrent users: $CONCURRENT_USERS"
        echo "  Test duration: ${DURATION}s"
        echo "  Test file size: $TEST_FILE_SIZE"
        echo ""
    } > "$report_file"

    print_success "Performance report saved: $report_file"
}

# Main function
main() {
    local host="$DEFAULT_HOST"
    local port="$DEFAULT_PORT"
    local concurrent="$DEFAULT_CONCURRENT_USERS"
    local duration="$DEFAULT_DURATION"
    local test_file_size="$DEFAULT_TEST_FILE_SIZE"
    local create_files=false
    local directory_test=false
    local file_test=false
    local range_test=false
    local all_tests=false
    local use_apache_bench=false
    local curl_test=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--host)
                host="$2"
                shift 2
                ;;
            -p|--port)
                port="$2"
                shift 2
                ;;
            -c|--concurrent)
                concurrent="$2"
                shift 2
                ;;
            -d|--duration)
                duration="$2"
                shift 2
                ;;
            -s|--size)
                test_file_size="$2"
                shift 2
                ;;
            --create-test-files)
                create_files=true
                shift
                ;;
            --directory-test)
                directory_test=true
                shift
                ;;
            --file-test)
                file_test=true
                shift
                ;;
            --range-test)
                range_test=true
                shift
                ;;
            --all-tests)
                all_tests=true
                shift
                ;;
            --apache-bench)
                use_apache_bench=true
                shift
                ;;
            --curl-test)
                curl_test=true
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

    # Set global variables
    CONCURRENT_USERS="$concurrent"
    DURATION="$duration"
    TEST_FILE_SIZE="$test_file_size"
    USE_APACHE_BENCH="$use_apache_bench"

    print_info "HTTP Media Server v2 - Performance Testing"
    print_info "Server: http://$host:$port"
    echo

    # Check dependencies
    check_dependencies

    # Create test files if requested
    if [[ "$create_files" == "true" ]]; then
        create_test_files
        echo
    fi

    # Test server availability
    if ! test_server_availability "$host" "$port"; then
        exit 1
    fi
    echo

    # Run tests
    if [[ "$all_tests" == "true" ]]; then
        directory_test=true
        file_test=true
        range_test=true
    fi

    if [[ "$directory_test" == "true" ]]; then
        test_directory_performance "$host" "$port" "$concurrent" "$duration"
        echo
    fi

    if [[ "$file_test" == "true" ]]; then
        test_file_performance "$host" "$port" "$concurrent" "$duration" "test-file-${test_file_size}.bin"
        echo
    fi

    if [[ "$range_test" == "true" ]]; then
        test_range_performance "$host" "$port" "test-file-${test_file_size}.bin"
        echo
    fi

    # Resource usage test
    test_resource_usage "$host" "$port" "$concurrent" "$duration"
    echo

    # Generate report
    generate_report "$host" "$port"

    print_success "Performance testing completed!"
}

# Check for bc command
if ! command -v bc &> /dev/null; then
    print_warning "bc command not found, some calculations may not work properly"
fi

# Run main function
main "$@"
