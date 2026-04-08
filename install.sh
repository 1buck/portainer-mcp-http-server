#!/bin/bash

###############################################################################
# Portainer MCP HTTP Server Installation Script
# 
# This script automatically detects your platform and installs the correct
# portainer-mcp-server binary.
#
# Supported platforms:
#   - Linux AMD64 (x86_64)
#   - Linux ARM64 (aarch64)
#   - macOS ARM64 (Apple Silicon M1/M2/M3)
#
# Usage: curl -fsSL https://raw.githubusercontent.com/1buck/portainer-mcp-http-server/main/install.sh | bash
# Or:    curl -fsSL https://raw.githubusercontent.com/1buck/portainer-mcp-http-server/main/install.sh | bash -s -- --version v0.7.0
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO="1buck/portainer-mcp-http-server"
INSTALL_DIR="/usr/local/bin"
DEFAULT_VERSION="v0.7.0"

# Parse command line arguments
VERSION=""
DOWNLOAD_DIR="/tmp"
FORCE_MODE=false
VERBOSE_MODE=false

print_help() {
    cat << EOF
Portainer MCP HTTP Server Installer

Usage:
  $(basename "$0") [OPTIONS]

Options:
  -v, --version VERSION    Specify version to install (default: ${DEFAULT_VERSION})
  -d, --download-dir DIR   Download directory (default: /tmp)
  -i, --install-dir DIR    Installation directory (default: /usr/local/bin)
  -f, --force              Force reinstall even if already installed
  -V, --verbose            Verbose output
  -h, --help               Show this help message

Examples:
  $(basename "$0")                          # Install latest version
  $(basename "$0") --version v0.7.0         # Install specific version
  $(basename "$0") --force                  # Reinstall
  $(basename "$0") --verbose --version v0.7.0

EOF
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_verbose() {
    if [ "$VERBOSE_MODE" = true ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -d|--download-dir)
            DOWNLOAD_DIR="$2"
            shift 2
            ;;
        -i|--install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        -V|--verbose)
            VERBOSE_MODE=true
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
done

# Set default version if not specified
if [ -z "$VERSION" ]; then
    VERSION="${DEFAULT_VERSION}"
fi

# Check if running as root (required for /usr/local/bin installation)
check_permissions() {
    if [ "$EUID" -ne 0 ] && [ "$INSTALL_DIR" = "/usr/local/bin" ]; then
        if [ "$FORCE_MODE" = false ]; then
            log_warn "Installation to $INSTALL_DIR requires root privileges"
            log_info "Script will attempt to use sudo for installation"
            log_info "Run with --help for alternative installation options"
        fi
    fi
}

# Detect OS
detect_os() {
    local os
    case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
        linux*)
            os="linux"
            ;;
        darwin*)
            os="darwin"
            ;;
        msys*|mingw*|cygwin*)
            os="windows"
            ;;
        *)
            log_error "Unsupported operating system: $(uname -s)"
            exit 1
            ;;
    esac
    echo "$os"
}

# Detect architecture
detect_arch() {
    local arch
    local machine
    machine="$(uname -m | tr '[:upper:]' '[:lower:]')"
    
    case "$machine" in
        x86_64|amd64)
            arch="amd64"
            ;;
        arm64|aarch64)
            arch="arm64"
            ;;
        armv7l|armhf)
            arch="arm"
            ;;
        *)
            log_error "Unsupported architecture: $machine"
            exit 1
            ;;
    esac
    echo "$arch"
}

# Detect platform
detect_platform() {
    local os=$1
    local arch=$2
    
    local platform_bin
    case "${os}-${arch}" in
        linux-amd64)
            platform_bin="portainer-mcp-server-linux-amd64"
            ;;
        linux-arm64)
            platform_bin="portainer-mcp-server-linux-arm64"
            ;;
        darwin-arm64)
            platform_bin="portainer-mcp-server-darwin-arm64"
            ;;
        darwin-amd64)
            log_error "macOS Intel (darwin-amd64) is not supported"
            log_error "Only Apple Silicon (M1/M2/M3) Macs are supported"
            log_error "See: https://github.com/1buck/portainer-mcp-http-server/releases"
            exit 1
            ;;
        windows-*)
            log_error "Windows is not supported"
            log_error "The portainer-mcp dependency doesn't provide Windows binaries"
            log_error "See: https://github.com/portainer/portainer-mcp/releases"
            exit 1
            ;;
        linux-arm|linux-armhf)
            log_error "Linux ARM (32-bit) is not supported"
            log_error "Only Linux ARM64 (aarch64) is supported"
            exit 1
            ;;
        *)
            log_error "Unsupported platform: ${os}-${arch}"
            log_error "Supported platforms:"
            log_error "  - Linux AMD64 (x86_64)"
            log_error "  - Linux ARM64 (aarch64)"
            log_error "  - macOS ARM64 (Apple Silicon M1/M2/M3)"
            exit 1
            ;;
    esac
    echo "$platform_bin"
}

# Check if portainer-mcp binary is available (separate download for unsupported platforms)
check_portainer_mcp() {
    local os=$1
    local arch=$2
    
    local mcp_bin="portainer-mcp"
    if [ "$os" = "windows" ]; then
        mcp_bin="portainer-mcp.exe"
    fi
    
    if command -v "$mcp_bin" &> /dev/null; then
        log_verbose "Found portainer-mcp in PATH: $(command -v "$mcp_bin")"
        return 0
    else
        log_warn "portainer-mcp binary not found in PATH"
        return 1
    fi
}

# Download binary from GitHub Releases
download_binary() {
    local version=$1
    local platform_bin=$2
    local download_path=$3
    
    local download_url="https://github.com/${REPO}/releases/download/${version}/${platform_bin}"
    
    log_info "Downloading ${platform_bin} from GitHub Releases..."
    log_verbose "URL: ${download_url}"
    
    if command -v curl &> /dev/null; then
        log_verbose "Using curl for download"
        if [ "$VERBOSE_MODE" = true ]; then
            curl -L "$download_url" -o "$download_path"
        else
            curl -sL "$download_url" -o "$download_path"
        fi
    elif command -v wget &> /dev/null; then
        log_verbose "Using wget for download"
        if [ "$VERBOSE_MODE" = true ]; then
            wget "$download_url" -O "$download_path"
        else
            wget -q "$download_url" -O "$download_path"
        fi
    else
        log_error "Neither curl nor wget is available. Please install one of them."
        exit 1
    fi
    
    if [ ! -f "$download_path" ] || [ ! -s "$download_path" ]; then
        log_error "Download failed. The file is missing or empty."
        log_error "Please check if version ${version} exists at: https://github.com/${REPO}/releases"
        exit 1
    fi
}

# Verify download (checksum verification if available)
verify_binary() {
    local download_path=$1
    local platform_bin=$2
    local version=$3
    
    log_verbose "Verifying binary integrity..."
    
    # Try to download checksum file
    local checksum_url="https://github.com/${REPO}/releases/download/${version}/${platform_bin}.sha256"
    local checksum_path="/tmp/checksum.tmp"
    
    if command -v curl &> /dev/null; then
        curl -sL "$checksum_url" -o "$checksum_path" 2>/dev/null || true
    elif command -v wget &> /dev/null; then
        wget -q "$checksum_url" -O "$checksum_path" 2>/dev/null || true
    fi
    
    if [ -f "$checksum_path" ] && [ -s "$checksum_path" ]; then
        log_verbose "Checksum file found, verifying..."
        if command -v sha256sum &> /dev/null; then
            cd "$(dirname "$download_path")"
            if sha256sum -c "$(basename "$checksum_path")" &> /dev/null; then
                log_verbose "Checksum verification passed"
                cd - > /dev/null
                return 0
            else
                log_warn "Checksum verification failed (continuing anyway)"
                cd - > /dev/null
                return 0
            fi
        elif command -v shasum &> /dev/null; then
            cd "$(dirname "$download_path")"
            if shasum -a 256 -c "$(basename "$checksum_path")" &> /dev/null; then
                log_verbose "Checksum verification passed"
                cd - > /dev/null
                return 0
            else
                log_warn "Checksum verification failed (continuing anyway)"
                cd - > /dev/null
                return 0
            fi
        fi
    else
        log_verbose "No checksum file available, skipping verification"
    fi
    
    return 0
}

# Install binary to system location
install_binary() {
    local download_path=$1
    local platform_bin=$2
    local install_path="${INSTALL_DIR}/${platform_bin}"
    
    if [ "$FORCE_MODE" = true ] && [ -f "$install_path" ]; then
        log_info "Removing existing installation at ${install_path}"
        if [ "$EUID" -ne 0 ]; then
            if ! sudo rm -f "$install_path" 2>/dev/null; then
                sudo -v && sudo rm -f "$install_path" || {
                    log_error "Failed to remove existing installation. Try running with sudo."
                    exit 1
                }
            fi
        else
            rm -f "$install_path"
        fi
    fi
    
    # Create installation directory if it doesn't exist
    if [ ! -d "$INSTALL_DIR" ]; then
        log_info "Creating installation directory: ${INSTALL_DIR}"
        
        # First try without sudo
        if mkdir -p "$INSTALL_DIR" 2>/dev/null; then
            log_verbose "Created directory without sudo"
        else
            # Try with sudo
            if ! sudo mkdir -p "$INSTALL_DIR" 2>/dev/null; then
                # Use askpass-friendly sudo or show error
                sudo -k 2>/dev/null  # Don't prompt for password
                if ! sudo mkdir -p "$INSTALL_DIR"; then
                    log_error "Cannot create directory ${INSTALL_DIR}"
                    log_error "Try one of the following:"
                    log_error "  1. Run with: sudo $0 [options]"
                    log_error "  2. Use a user-writable directory: $0 --install-dir \$HOME/.local/bin"
                    exit 1
                fi
            fi
        fi
    fi
    
    # Install the binary
    log_info "Installing ${platform_bin} to ${install_path}"
    
    # Try installation without sudo first
    if install -m 755 "$download_path" "$install_path" 2>/dev/null; then
        log_verbose "Installed binary without sudo"
    else
        # Try with sudo
        if ! sudo install -m 755 "$download_path" "$install_path" 2>/dev/null; then
            sudo -k 2>/dev/null  # Don't prompt
            if ! sudo install -m 755 "$download_path" "$install_path"; then
                log_error "Failed to install binary to ${install_path}"
                log_error "Try one of the following:"
                log_error "  1. Run with: sudo $0 [options]"
                log_error "  2. Use a user-writable directory: $0 --install-dir \$HOME/.local/bin"
                exit 1
            fi
        fi
    fi
    
    log_success "Binary installed successfully"
}

# Create symlink for easy access
create_symlink() {
    local install_path=$1
    local symlink_path="/usr/local/bin/portainer-mcp-server"
    
    # If binary was installed with platform-specific name, create a symlink
    if [ "${install_path}" != "${symlink_path}" ]; then
        log_verbose "Creating symlink: ${symlink_path} -> ${install_path}"
        
        # Try creating symlink without sudo first
        if ln -sf "$install_path" "$symlink_path" 2>/dev/null; then
            log_verbose "Created symlink successfully"
        else
            # Try with sudo but don't fail if it doesn't work
            if sudo ln -sf "$install_path" "$symlink_path" 2>/dev/null; then
                log_verbose "Created symlink with sudo"
            else
                sudo -k 2>/dev/null
                log_verbose "Could not create global symlink (requires root)"
                log_verbose "Binary is available at: ${install_path}"
            fi
        fi
    fi
}

# Main installation function
main() {
    echo ""
    echo "==============================================="
    echo " Portainer MCP HTTP Server Installer"
    echo "==============================================="
    echo ""
    
    log_info "Checking installation requirements..."
    check_permissions
    
    log_info "Detecting platform..."
    local os=$(detect_os)
    local arch=$(detect_arch)
    local platform_bin=$(detect_platform "$os" "$arch")
    
    echo ""
    log_info "Platform detected:"
    echo "  Operating System: ${os}"
    echo "  Architecture:     ${arch}"
    echo "  Binary:           ${platform_bin}"
    echo "  Version:          ${VERSION}"
    echo "  Install Dir:      ${INSTALL_DIR}"
    echo ""
    
    # Check if already installed
    if command -v portainer-mcp-server &> /dev/null; then
        local current_version=$(portainer-mcp-server --help 2>&1 | grep -i version || echo "unknown")
        log_warn "portainer-mcp-server is already installed"
        echo "  Current path: $(command -v portainer-mcp-server)"
        echo "  Version info: ${current_version}"
        
        if [ "$FORCE_MODE" = false ]; then
            log_warn "Use --force to reinstall"
            exit 0
        else
            log_info "Forcing reinstallation..."
        fi
    fi
    
    # Download directory setup
    local download_path="${DOWNLOAD_DIR}/${platform_bin}"
    mkdir -p "$DOWNLOAD_DIR"
    
    # Download binary
    download_binary "$VERSION" "$platform_bin" "$download_path"
    
    # Verify binary
    verify_binary "$download_path" "$platform_bin" "$VERSION"
    
    # Install binary
    install_binary "$download_path" "$platform_bin"
    
    # Create symlink
    create_symlink "${INSTALL_DIR}/${platform_bin}"
    
    # Cleanup
    if [ -f "$download_path" ]; then
        log_verbose "Cleaning up: removing ${download_path}"
        rm -f "$download_path"
    fi
    
    echo ""
    echo "==============================================="
    echo " Installation Complete!"
    echo "==============================================="
    echo ""
    log_success "Portainer MCP HTTP Server ${VERSION} installed successfully"
    echo ""
    echo "Quick Start:"
    echo "  portainer-mcp-server \\"
    echo "    -portainer-url http://your-portainer:9000 \\"
    echo "    -portainer-token YOUR_API_TOKEN \\"
    echo "    -password YOUR_PASSWORD \\"
    echo "    -base-url 192.168.1.50:8080"
    echo ""
    echo "For more information, visit:"
    echo "  https://github.com/1buck/portainer-mcp-http-server"
    echo ""
    log_info "To get started, run: portainer-mcp-server --help"
    echo ""
}

# Run main function
main
