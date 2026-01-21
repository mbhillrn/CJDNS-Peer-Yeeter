#!/usr/bin/env bash
# Prerequisites Module - Check and install required tools

# Check if gum is installed
check_gum() {
    if command -v gum &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Install gum via charm.sh repository
install_gum() {
    print_info "Installing gum from charm.sh repository..."
    echo

    # Check if running as root or with sudo
    if [ "$EUID" -ne 0 ]; then
        print_error "This installation requires root privileges"
        print_info "Please run this script with sudo or as root"
        return 1
    fi

    # Add GPG key
    print_working "Adding Charm repository GPG key..."
    if ! mkdir -p /etc/apt/keyrings 2>/dev/null; then
        print_complete "Failed to create keyrings directory" "failed"
        return 1
    fi

    if ! curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null; then
        print_complete "Failed to add GPG key" "failed"
        return 1
    fi
    print_complete "GPG key added" "success"

    # Add repository
    print_working "Adding Charm repository..."
    if ! echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | tee /etc/apt/sources.list.d/charm.list >/dev/null; then
        print_complete "Failed to add repository" "failed"
        return 1
    fi
    print_complete "Repository added" "success"

    # Update package list
    print_working "Updating package lists..."
    if ! apt update >/dev/null 2>&1; then
        print_complete "Failed to update packages" "failed"
        return 1
    fi
    print_complete "Package lists updated" "success"

    # Install gum
    print_working "Installing gum..."
    if ! apt install -y gum >/dev/null 2>&1; then
        print_complete "Failed to install gum" "failed"
        return 1
    fi
    print_complete "gum installed successfully!" "success"

    return 0
}

# Check if fzf is installed (optional)
check_fzf() {
    if command -v fzf &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Install fzf via apt
install_fzf() {
    print_info "Installing fzf..."
    echo

    if [ "$EUID" -ne 0 ]; then
        print_error "This installation requires root privileges"
        return 1
    fi

    if apt install -y fzf >/dev/null 2>&1; then
        print_success "fzf installed successfully!"
        return 0
    else
        print_error "Failed to install fzf"
        return 1
    fi
}

# Check if fx is installed (optional but recommended for JSON editing)
check_fx() {
    if command -v fx &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Install fx via precompiled binary
install_fx() {
    print_info "Installing fx (interactive JSON viewer/editor)..."
    echo

    if [ "$EUID" -ne 0 ]; then
        print_error "This installation requires root privileges"
        return 1
    fi

    local temp_dir=$(mktemp -d)
    cd "$temp_dir" || return 1

    print_working "Downloading fx binary..."

    # Detect architecture
    local arch=$(uname -m)
    local fx_binary

    case "$arch" in
        x86_64)
            fx_binary="fx_linux_amd64"
            ;;
        aarch64|arm64)
            fx_binary="fx_linux_arm64"
            ;;
        *)
            print_complete "Unsupported architecture: $arch" "failed"
            cd - >/dev/null
            rm -rf "$temp_dir"
            return 1
            ;;
    esac

    # Download latest fx release
    if ! wget -q "https://github.com/antonmedv/fx/releases/latest/download/$fx_binary" -O fx 2>/dev/null; then
        print_complete "Failed to download fx" "failed"
        cd - >/dev/null
        rm -rf "$temp_dir"
        return 1
    fi
    print_complete "Downloaded fx binary" "success"

    # Install to /usr/local/bin
    print_working "Installing fx to /usr/local/bin..."
    chmod +x fx
    if ! mv fx /usr/local/bin/fx 2>/dev/null; then
        print_complete "Failed to install fx" "failed"
        cd - >/dev/null
        rm -rf "$temp_dir"
        return 1
    fi
    print_complete "fx installed successfully!" "success"

    cd - >/dev/null
    rm -rf "$temp_dir"
    return 0
}

# Check all prerequisites
check_prerequisites() {
    local missing_tools=()
    local optional_missing=()

    # Check required tools
    if ! check_gum; then
        missing_tools+=("gum")
    fi

    # Check optional tools
    if ! check_fzf; then
        optional_missing+=("fzf")
    fi

    if ! check_fx; then
        optional_missing+=("fx")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_warning "Missing required tools: ${missing_tools[*]}"
        echo
        print_info "PeerYeeter requires 'gum' for interactive menus and enhanced user experience"
        echo
        print_info "Installation command:"
        echo "  sudo mkdir -p /etc/apt/keyrings"
        echo "  curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg"
        echo "  echo \"deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *\" | sudo tee /etc/apt/sources.list.d/charm.list"
        echo "  sudo apt update && sudo apt install gum"
        echo

        if ask_yes_no "Would you like to install gum now?"; then
            echo
            if install_gum; then
                print_success "Installation complete!"
            else
                print_error "Installation failed"
                echo
                print_error "Cannot proceed without gum. Please install it manually and try again."
                return 1
            fi
        else
            print_error "Cannot proceed without gum"
            echo
            print_info "Please install gum manually and run PeerYeeter again"
            return 1
        fi
    fi

    # Inform about optional tools and offer installation
    if [ ${#optional_missing[@]} -gt 0 ]; then
        echo
        print_info "Optional tools not installed: ${optional_missing[*]}"
        echo
        print_info "fx: Interactive JSON viewer/editor with mouse support"
        print_info "fzf: Fuzzy finder for enhanced file selection"
        echo

        # Offer to install fx if missing
        if ! check_fx; then
            if ask_yes_no "Would you like to install fx now? (recommended for JSON editing)"; then
                echo
                if install_fx; then
                    print_success "fx installed successfully!"
                else
                    print_warning "fx installation failed - you can install it manually later"
                fi
            fi
        fi

        # Offer to install fzf if missing
        if ! check_fzf; then
            echo
            if ask_yes_no "Would you like to install fzf now? (useful for file selection)"; then
                echo
                if install_fzf; then
                    print_success "fzf installed successfully!"
                else
                    print_warning "fzf installation failed - you can install it manually later"
                fi
            fi
        fi
    fi

    return 0
}
