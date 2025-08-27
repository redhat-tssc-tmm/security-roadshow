#!/bin/bash

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check & verify if target dir is in PATH
clitools_in_path() {
    local clitools_dir="$HOME/clitools"
    
    # Check if already in PATH
    if [[ ":$PATH:" == *":$clitools_dir:"* ]]; then
        print_status "~/clitools is already in PATH, all good"
        return 0
    fi
    
    print_status "Adding ~/clitools to PATH"
    
    # Add to current session
    export PATH="$clitools_dir:$PATH"
    
    # Add to .profile for persistence
    echo "" >> "$HOME/.profile"
    echo "# Added by your script - clitools directory" >> "$HOME/.profile"
    echo "export PATH=\"\$HOME/clitools:\$PATH\"" >> "$HOME/.profile"
    
    print_status "~/clitools added to PATH. Please restart your shell or run 'source ~/.profile'"
}


# Function to cleanup on exit
cleanup() {
    if [[ -f "cosign-amd64.gz" ]]; then
        rm -f cosign-amd64.gz
    fi
    if [[ -f "gitsign-amd64.gz" ]]; then
        rm -f gitsign-amd64.gz
    fi
    if [[ -f "cosign-amd64" ]]; then
        rm -f cosign-amd64
    fi
    if [[ -f "gitsign-amd64" ]]; then
        rm -f gitsign-amd64
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

main() {
    print_status "Starting cosign and gitsign installation..."
    
    # Check if oc command exists
    if ! command -v oc &> /dev/null; then
        print_error "oc command not found. Please install OpenShift CLI first."
        exit 1
    fi
    
    # Get the route hostname
    print_status "Getting client server route..."
    ROUTE_HOST=$(oc get routes -l app.kubernetes.io/component=client-server -n trusted-artifact-signer --no-headers 2>/dev/null | tail -n 1 | awk '{print $2}')
    
    if [[ -z "$ROUTE_HOST" ]]; then
        print_error "Could not find client-server route in trusted-artifact-signer namespace"
        exit 1
    fi
    
    print_status "Found route host: $ROUTE_HOST"
    
    # Construct URLs
    COSIGN_CLI_URL="https://${ROUTE_HOST}/clients/linux/cosign-amd64.gz"
    GITSIGN_CLI_URL="https://${ROUTE_HOST}/clients/linux/gitsign-amd64.gz"
    
    print_status "Cosign URL: $COSIGN_CLI_URL"
    print_status "Gitsign URL: $GITSIGN_CLI_URL"
    
    mkdir -p "$HOME/clitools"
    clitools_in_path

    # Download files
    # need to use curl, as the default image for the terminal operator doesn't have wget
    print_status "Downloading cosign..."
    if ! curl -fsSL -o "$(basename "$COSIGN_CLI_URL")" "$COSIGN_CLI_URL"; then
        print_error "Failed to download cosign from $COSIGN_CLI_URL"
        exit 1
    fi

    print_status "Downloading gitsign..."
    if ! curl -fsSL -o "$(basename "$GITSIGN_CLI_URL")" "$GITSIGN_CLI_URL"; then
        print_error "Failed to download gitsign from $GITSIGN_CLI_URL"
        exit 1
    fi
    
    # Extract and install cosign
    print_status "Installing cosign..."
    if ! gunzip cosign-amd64.gz; then
        print_error "Failed to extract cosign-amd64.gz"
        exit 1
    fi
    
    chmod +x cosign-amd64
    
    if ! mv cosign-amd64 $HOME/clitools/cosign; then
        print_error "Failed to install cosign to $HOME/clitools"
        exit 1
    fi
    
    # Extract and install gitsign
    print_status "Installing gitsign..."
    if ! gunzip gitsign-amd64.gz; then
        print_error "Failed to extract gitsign-amd64.gz"
        exit 1
    fi
    
    chmod +x gitsign-amd64
    
    if ! mv gitsign-amd64 $HOME/clitools/gitsign; then
        print_error "Failed to install gitsign to $HOME/clitools"
        exit 1
    fi
    
    # Verify installations
    print_status "Verifying installations..."
    
    if command -v cosign &> /dev/null; then
        print_status "Cosign installed successfully:"
        cosign version
    else
        print_error "Cosign installation failed"
        exit 1
    fi
    
    if command -v gitsign &> /dev/null; then
        print_status "Gitsign installed successfully:"
        gitsign version
    else
        print_error "Gitsign installation failed"
        exit 1
    fi
    
    print_status "Installation completed successfully!"
}

# Run main function
main "$@"