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
# Returns: "type|version|path" where type is "nodejs" or "compiled"
check_cjdnstool() {
    if ! command -v cjdnstool &>/dev/null; then
        return 1
    fi

    local cj_path cj_type cj_version

    cj_path=$(command -v cjdnstool)

    # Detect type: Node.js version has 'ping' subcommand, compiled Rust version doesn't
    if cjdnstool ping >/dev/null 2>&1; then
        cj_type="nodejs"
        # Node.js version doesn't support --version, get from package.json
        local real_path=$(readlink -f "$cj_path" 2>/dev/null || echo "$cj_path")
        local pkg_dir=$(dirname "$real_path")
        if [ -f "$pkg_dir/package.json" ]; then
            cj_version=$(jq -r '.version // "unknown"' "$pkg_dir/package.json" 2>/dev/null || echo "unknown")
        else
            cj_version="unknown"
        fi
    else
        cj_type="compiled"
        # Compiled version supports --version
        cj_version=$(cjdnstool --version 2>/dev/null | head -1 | sed 's/cjdnstool //' || echo "unknown")
    fi

    echo "$cj_type|$cj_version|$cj_path"
    return 0
}

# Check if cjdnstool is the recommended Node.js version
# Returns 0 if Node.js version, 1 if compiled/other
is_recommended_cjdnstool() {
    local info
    if ! info=$(check_cjdnstool); then
        return 1
    fi

    local cj_type=$(echo "$info" | cut -d'|' -f1)
    [ "$cj_type" = "nodejs" ]
}

# Install the recommended Node.js cjdnstool
install_nodejs_cjdnstool() {
    # Check if npm is available, if not, try to install it
    if ! command -v npm &>/dev/null; then
        echo "npm not found - attempting to install Node.js and npm..."
        echo

        if ! install_nodejs_npm; then
            echo "Failed to install Node.js and npm."
            echo "Please install them manually, then run: sudo npm install -g cjdnstool"
            return 1
        fi

        # Refresh path
        hash -r 2>/dev/null || true

        if ! command -v npm &>/dev/null; then
            echo "npm still not found after installation attempt."
            echo "Please install Node.js and npm manually."
            return 1
        fi

        echo "Node.js and npm installed successfully!"
        echo
    fi

    # Check if there's an existing non-Node.js cjdnstool that needs to be removed
    local existing_cjdnstool=$(command -v cjdnstool 2>/dev/null || true)
    if [ -n "$existing_cjdnstool" ]; then
        local real_path=$(readlink -f "$existing_cjdnstool" 2>/dev/null || echo "$existing_cjdnstool")
        # If it's NOT a Node.js script (i.e., it's the compiled version), remove it
        if ! file "$real_path" 2>/dev/null | grep -qi "node\|script\|text"; then
            echo "Removing existing compiled cjdnstool at $existing_cjdnstool..."
            if sudo rm -f "$existing_cjdnstool"; then
                echo "Removed successfully."
                hash -r 2>/dev/null || true
            else
                echo "Warning: Could not remove existing cjdnstool. Trying npm install with --force..."
            fi
            echo
        fi
    fi

    echo "Installing cjdnstool via npm..."
    echo

    # Use --force to overwrite any remaining conflicts
    if sudo npm install -g --force cjdnstool 2>&1; then
        echo
        echo "Installation complete!"

        # Verify installation
        hash -r 2>/dev/null || true
        if command -v cjdnstool &>/dev/null; then
            return 0
        else
            echo "Warning: cjdnstool installed but not found in PATH"
            return 1
        fi
    else
        echo "Installation failed"
        return 1
    fi
}

# Install Node.js and npm based on detected package manager
install_nodejs_npm() {
    local pkg_manager=""

    # Detect package manager
    if command -v apt-get &>/dev/null; then
        pkg_manager="apt"
    elif command -v dnf &>/dev/null; then
        pkg_manager="dnf"
    elif command -v yum &>/dev/null; then
        pkg_manager="yum"
    elif command -v pacman &>/dev/null; then
        pkg_manager="pacman"
    elif command -v apk &>/dev/null; then
        pkg_manager="apk"
    else
        echo "Could not detect package manager (apt, dnf, yum, pacman, apk)"
        return 1
    fi

    echo "Detected package manager: $pkg_manager"
    echo "Installing Node.js and npm (this may take a moment)..."
    echo

    case "$pkg_manager" in
        apt)
            sudo apt-get update -qq && sudo apt-get install -y nodejs npm
            ;;
        dnf)
            sudo dnf install -y nodejs npm
            ;;
        yum)
            sudo yum install -y nodejs npm
            ;;
        pacman)
            sudo pacman -Sy --noconfirm nodejs npm
            ;;
        apk)
            sudo apk add --no-cache nodejs npm
            ;;
    esac

    return $?
}

# Get currently connected runtime peers as a fake config JSON (for duplicate checking)
# Returns a JSON file path that mimics the config structure
get_runtime_peers_as_config() {
    local admin_ip="$1"
    local admin_port="$2"
    local admin_password="$3"
    local output_file="$4"

    # Initialize with empty structure
    echo '{"interfaces":{"UDPInterface":[{"connectTo":{}},{"connectTo":{}}]}}' > "$output_file"

    local page=0
    local ipv4_peers="{}"
    local ipv6_peers="{}"

    while true; do
        local result
        result=$(cjdnstool -a "$admin_ip" -p "$admin_port" -P "$admin_password" cexec InterfaceController_peerStats --page=$page 2>/dev/null)

        if [ -z "$result" ]; then
            break
        fi

        # Extract peers and categorize by IP type
        while IFS='|' read -r state lladdr pubkey; do
            [ -z "$lladdr" ] && continue

            # Create a minimal peer entry (we only need address for duplicate checking)
            local peer_entry='{"publicKey":"'"$pubkey"'","password":""}'

            if [[ "$lladdr" =~ ^\[ ]]; then
                # IPv6 peer
                ipv6_peers=$(echo "$ipv6_peers" | jq --arg addr "$lladdr" --argjson peer "$peer_entry" '. + {($addr): $peer}')
            else
                # IPv4 peer
                ipv4_peers=$(echo "$ipv4_peers" | jq --arg addr "$lladdr" --argjson peer "$peer_entry" '. + {($addr): $peer}')
            fi
        done < <(echo "$result" | jq -r '.peers[]? | "\(.state)|\(.lladdr)|\(.publicKey)"' 2>/dev/null)

        local peer_count
        peer_count=$(echo "$result" | jq '.peers | length' 2>/dev/null || echo 0)

        if [ "$peer_count" -eq 0 ]; then
            break
        fi

        page=$((page + 1))
    done

    # Build the fake config structure
    jq -n --argjson ipv4 "$ipv4_peers" --argjson ipv6 "$ipv6_peers" \
        '{"interfaces":{"UDPInterface":[{"connectTo":$ipv4},{"connectTo":$ipv6}]}}' > "$output_file"

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
