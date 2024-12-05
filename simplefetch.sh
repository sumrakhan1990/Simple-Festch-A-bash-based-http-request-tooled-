#!/bin/bash

# Constants and configurations
MAX_LOG_SIZE=10240  # 10 KB
CACHE_DIR="./cache"
DEBUG_MODE=false  # Enable detailed logging for debugging
METRICS_LOG="metrics.log"

# Function to parse URL and extract host, path, and protocol
parse_url() {
    local url="$1"
    local protocol host path port

    if [[ "$url" =~ ^http://([^/]+)(/.*)?$ ]]; then
        protocol="http"
        host="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]:-/}"
        port=80
    elif [[ "$url" =~ ^https://([^/]+)(/.*)?$ ]]; then
        protocol="https"
        host="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]:-/}"
        port=443
    else
        echo "Invalid URL format. Supported protocols: http, https."
        exit 1
    fi

    echo "$protocol" "$host" "$port" "$path"
}

# Log rotation function
rotate_log() {
    local log_file="$1"
    if [ -f "$log_file" ] && [ "$(stat -c%s "$log_file")" -ge "$MAX_LOG_SIZE" ]; then
        mv "$log_file" "${log_file}.1"
        touch "$log_file"
    fi
}

# Debugging function
log_debug() {
    if [ "$DEBUG_MODE" = true ]; then
        echo "[DEBUG] $1" | tee -a simplefetch.log
    fi
}

# Monitor system resources
monitor_system() {
    local free_mem=$(free -m | awk '/^Mem:/ {print $4}')
    local cpu_load=$(uptime | awk -F'[a-z]:' '{ print $2 }' | cut -d, -f1)
    
    echo "[$(date)] - Free Memory: ${free_mem}MB, CPU Load: ${cpu_load}" >> "$METRICS_LOG"
    if [ "$free_mem" -lt 50 ]; then
        echo "[WARNING] Low memory detected: ${free_mem}MB available." >> "$METRICS_LOG"
    fi
}

# Metrics function to log response times
log_metrics() {
    local start_time="$1"
    local end_time="$2"
    local url="$3"

    local duration=$(echo "$end_time - $start_time" | bc)
    echo "[$(date)] - Request to $url took ${duration}s" >> "$METRICS_LOG"
}

# Caching function
check_cache() {
    local url_hash=$(echo -n "$1" | md5sum | awk '{print $1}')
    local cache_file="$CACHE_DIR/$url_hash"
    if [ -f "$cache_file" ]; then
        cat "$cache_file"
        return 0
    else
        return 1
    fi
}

save_to_cache() {
    local url="$1"
    local content="$2"
    local url_hash=$(echo -n "$url" | md5sum | awk '{print $1}')
    echo "$content" > "$CACHE_DIR/$url_hash"
}

# Function to send HTTP/HTTPS GET request
send_get_request() {
    local url="$1"
    local headers_only="$2"
    local output_file="$3"
    local use_cache="$4"
    local max_redirects=5
    local redirect_count=0

    monitor_system  # Log system metrics before starting

    local start_time=$(date +%s.%N)

    while true; do
        # Use cache if enabled
        if [ "$use_cache" = true ]; then
            if check_cache "$url"; then
                return
            else
                echo "[INFO] Fetching live response for $url."
            fi
        fi

        # Parse URL components
        read -r protocol host port path <<< "$(parse_url "$url")"

        # Construct the request headers
        request="GET $path HTTP/1.1\r\nHost: $host\r\nUser-Agent: SimpleFetch/1.0\r\nConnection: close\r\n\r\n"

        # Choose transport based on protocol
        if [ "$protocol" = "https" ]; then
            response=$(echo -e "$request" | openssl s_client -quiet -connect "$host:$port" 2>/dev/null)
        else
            response=$(echo -e "$request" | nc "$host" "$port")
        fi

        # Log the request and response
        echo "[$(date)] - GET $url" >> simplefetch.log
        log_debug "Request Headers: $request"
        rotate_log "simplefetch.log"

        # Separate headers from the body
        headers=$(echo "$response" | sed '/^\r$/q')

        if [ "$headers_only" = true ]; then
            if [ -n "$output_file" ]; then
                echo "$headers" > "$output_file"
            else
                echo "$headers"
            fi
        else
            if [ -n "$output_file" ]; then
                echo "$response" > "$output_file"
            else
                echo "$response"
            fi

            # Save to cache if enabled
            if [ "$use_cache" = true ]; then
                save_to_cache "$url" "$response"
            fi
        fi

        # Check for redirect (status code 3xx and Location header)
        status_code=$(echo "$headers" | grep -oP "HTTP/1\.[01] \K[0-9]+")
        location=$(echo "$headers" | grep -i "Location:" | awk '{print $2}' | tr -d '\r')

        if [[ "$status_code" =~ ^3 && $redirect_count -lt $max_redirects && -n "$location" ]]; then
            url="$location"  # Update URL to redirect location
            redirect_count=$((redirect_count + 1))
            echo "Redirecting to $url"
        else
            break
        fi
    done

    local end_time=$(date +%s.%N)
    log_metrics "$start_time" "$end_time" "$url"  # Log response time
}


# Function to send POST request
send_post_request() {
    local url="$1"
    local data="$2"
    local headers_only="$3"
    local output_file="$4"
    local use_cache="$5"

    # Use cache if enabled
    if [ "$use_cache" = true ]; then
        if check_cache "$url"; then
            echo "[INFO] Using cached response for $url."
            return
        else
            echo "[INFO] Fetching live response for $url."
        fi
    fi

    # Parse URL components
    read -r protocol host port path <<< "$(parse_url "$url")"

    # Detect format and set Content-Type
    local content_type=""
    if [[ "$data" =~ ^[a-zA-Z0-9_%+-]+=[a-zA-Z0-9_%+-]+(&[a-zA-Z0-9_%+-]+=[a-zA-Z0-9_%+-]+)*$ ]]; then
        # Assume key=value format and convert to JSON if multiple entries are detected
        if [[ "$data" == *"&"* ]]; then
            data=$(echo "$data" | awk -F'&' '{
                split($0, pairs, "&");
                printf("{");
                for (i in pairs) {
                    split(pairs[i], kv, "=");
                    printf("\"%s\":\"%s\"", kv[1], kv[2]);
                    if (i < length(pairs)) printf(",");
                }
                printf("}");
            }')
        else
            # Convert single key-value to JSON
            data=$(echo "$data" | awk -F'=' '{printf("{\"%s\":\"%s\"}", $1, $2)}')
        fi
        content_type="application/json"
    else
        # Assume JSON format
        content_type="application/json"

        # If data is a file, read its content
        if [ -f "$data" ]; then
            data=$(<"$data")
        fi
    fi

    # Construct the request headers and body
    request="POST $path HTTP/1.1\r\nHost: $host\r\nContent-Type: $content_type\r\nContent-Length: ${#data}\r\nUser-Agent: SimpleFetch/1.0\r\nConnection: close\r\n\r\n$data"

    # Choose transport based on protocol
    if [ "$protocol" = "https" ]; then
        response=$(echo -e "$request" | openssl s_client -quiet -connect "$host:$port" 2>/dev/null)
    else
        response=$(echo -e "$request" | nc "$host" "$port")
    fi

    echo "[$(date)] - POST $url" >> simplefetch.log
    rotate_log "simplefetch.log"

    headers=$(echo "$response" | sed '/^\r$/q')

    if [ "$headers_only" = true ]; then
        if [ -n "$output_file" ]; then
            echo "$headers" > "$output_file"
        else
            echo "$headers"
        fi
    else
        if [ -n "$output_file" ]; then
            echo "$response" > "$output_file"
        else
            echo "$response"
        fi

        if [ "$use_cache" = true ]; then
            save_to_cache "$url" "$response"
        fi
    fi
}


send_multiple_requests() {
    local urls=("$@")
    for url in "${urls[@]}"; do
        # Running requests in parallel
        send_get_request "$url" "$headers_only" "$output_file" "$use_cache" &
    done
    wait
}

# Main function to handle input
main() {
    if [ "$#" -lt 2 ]; then
        echo "Usage: $0 [GET|POST] URL [-n number_of_requests] [-I] [-o output_file] [-c] [-u url_file] [-d data] [-r]"
        exit 1
    fi

    local method="$1"
    local urls=()
    local data=""
    local headers_only=false
    local output_file=""
    local use_cache=false
    local num_requests=1

    # Save the full command with flags for logging
    local command_flags="$@"

    shift 1  # Shift to URL and options

    # Parse options
    while (( "$#" )); do
        case "$1" in
            -I)
                headers_only=true
                shift
                ;;
            -o)
                output_file="$2"
                shift 2
                ;;
            -c)
                use_cache=true
                shift
                ;;
            -n)
                num_requests="$2"
                shift 2
                ;;
            -u)
                url_file="$2"
                urls=($(cat "$url_file"))
                shift 2
                ;;
            -d)
                data="$2"
                shift 2
                ;;
            * )
                urls+=("$1")
                shift
                ;;
        esac
    done

    # Log the command with flags
    echo "[$(date)] - Command run: ${command_flags}" >> simplefetch.log
    rotate_log "simplefetch.log"

    # Send requests in parallel for multiple URLs
    if [ "$method" == "GET" ]; then
        if [ "${#urls[@]}" -gt 0 ]; then
            for i in $(seq 1 "$num_requests"); do
                send_multiple_requests "${urls[@]}" &
            done
            wait
        else
            echo "No URLs provided. Please specify URLs with -u or as positional arguments."
            exit 1
        fi
    elif [ "$method" == "POST" ]; then
        for i in $(seq 1 "$num_requests"); do
            send_post_request "${urls[@]}" "$data" "$headers_only" "$output_file" "$use_cache" &
        done
        wait
    fi
}

# Initialize directories and logs
mkdir -p "$CACHE_DIR"
touch "$METRICS_LOG"
rotate_log "$METRICS_LOG"

# Run the script
main "$@"
