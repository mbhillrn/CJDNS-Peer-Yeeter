#!/usr/bin/env bash
# CJDNS Detection Module
# Auto-detects cjdns config file, service, and admin credentials

# Find the active cjdns service
detect_cjdns_service() {
    local services

    # Find all services with 'cjd' in the name
    services=$(systemctl list-units --type=service --all --no-pager 2>/dev/null | grep -i 'cjd' | awk '{print $1}' || echo "")

    if [ -z "$services" ]; then
        return 1
    fi

    # Check each service to find one with a valid cjdroute config
    while IFS= read -r service; do
        [ -z "$service" ] && continue

        # Get service status to check if it references a config file
        local service_info
        service_info=$(systemctl status "$service" 2>/dev/null || echo "")

        # Look for /etc/cjdroute_*.conf pattern in service output
        local config_file
        config_file=$(echo "$service_info" | grep -oP '/etc/cjdroute_[0-9]+\.conf' | head -1 || echo "")

        if [ -n "$config_file" ] && [ -f "$config_file" ]; then
            echo "$service|$config_file"
            return 0
        fi

        # Alternative: check if service file itself references a config
        local service_file="/etc/systemd/system/$service"
        if [ -f "$service_file" ]; then
            config_file=$(grep -oP '/etc/cjdroute_[0-9]+\.conf' "$service_file" | head -1 || echo "")
            if [ -n "$config_file" ] && [ -f "$config_file" ]; then
                echo "$service|$config_file"
                return 0
            fi
        fi
    done <<< "$services"

    return 1
}

# Find cjdns config files manually (fallback)
list_cjdns_configs() {
    # Only match files like cjdroute_NNNN.conf (not backups)
    find /etc -maxdepth 1 -name 'cjdroute_*.conf' -type f ! -name '*.backup*' ! -name '*.bak*' ! -name '*.old*' 2>/dev/null | sort
}

# Extract admin connection info from config
get_admin_info() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    local bind password
    bind=$(jq -r '.admin.bind // empty' "$config_file" 2>/dev/null)
    password=$(jq -r '.admin.password // empty' "$config_file" 2>/dev/null)

    if [ -z "$bind" ]; then
        return 1
    fi

    echo "$bind|$password"
    return 0
}

# Check cjdnstool version and availability
check_cjdnstool() {
    if ! command -v cjdnstool &>/dev/null; then
        return 1
    fi

    local version
    version=$(cjdnstool --version 2>/dev/null | head -1 || echo "unknown")
    echo "$version"
    return 0
}

# Validate that cjdnstool can connect to cjdns
test_cjdnstool_connection() {
    local admin_ip="$1"
    local admin_port="$2"
    local admin_password="$3"

    # Try to get peer stats (page 0)
    if cjdnstool -a "$admin_ip" -p "$admin_port" -P "$admin_password" cexec InterfaceController_peerStats --page=0 2>/dev/null | jq empty 2>/dev/null; then
        return 0
    fi

    return 1
}

# Auto-detect cjdroute binary location
detect_cjdroute_binary() {
    local cjdroute_path=""

    # Method 1: Check if cjdroute is in PATH
    if cjdroute_path=$(command -v cjdroute 2>/dev/null); then
        echo "$cjdroute_path"
        return 0
    fi

    # Method 2: Extract from systemd service file (if service is known)
    if [ -n "${1:-}" ]; then
        local service_name="$1"
        local service_file="/etc/systemd/system/$service_name"

        if [ -f "$service_file" ]; then
            # Extract cjdroute path from ExecStart line
            # Example: ExecStart=/bin/sh -c /usr/local/bin/cjdroute < /etc/cjdroute.conf
            cjdroute_path=$(grep -oP 'ExecStart=.*?\K(/[^ ]+/cjdroute)\b' "$service_file" 2>/dev/null | head -1)

            if [ -n "$cjdroute_path" ] && [ -x "$cjdroute_path" ]; then
                echo "$cjdroute_path"
                return 0
            fi
        fi

        # Also try systemctl show to get ExecStart
        local exec_start=$(systemctl show "$service_name" -p ExecStart --value 2>/dev/null)
        if [ -n "$exec_start" ]; then
            # Parse out the cjdroute path from the ExecStart command
            cjdroute_path=$(echo "$exec_start" | grep -oP '/[^ ]+/cjdroute\b' | head -1)

            if [ -n "$cjdroute_path" ] && [ -x "$cjdroute_path" ]; then
                echo "$cjdroute_path"
                return 0
            fi
        fi
    fi

    # Method 3: Find in common installation directories
    local search_dirs=("/usr/local/bin" "/usr/bin" "/opt/cjdns" "/opt/cjdns/bin")
    for dir in "${search_dirs[@]}"; do
        if [ -x "$dir/cjdroute" ]; then
            echo "$dir/cjdroute"
            return 0
        fi
    done

    # Method 4: Use find as last resort (slower but comprehensive)
    # Search in /usr, /opt, and /home but limit depth to avoid slow scans
    for base_dir in /usr /opt; do
        if [ -d "$base_dir" ]; then
            cjdroute_path=$(find "$base_dir" -maxdepth 4 -type f -name "cjdroute" -executable 2>/dev/null | head -1)
            if [ -n "$cjdroute_path" ]; then
                echo "$cjdroute_path"
                return 0
            fi
        fi
    done

    # Not found
    return 1
}
