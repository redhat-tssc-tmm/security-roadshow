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
    
    # Add to .bashrc for persistence
    echo "" >> "$HOME/.profile"
    echo "# Added by your script - clitools directory" >> "$HOME/.bashrc"
    echo "export PATH=\"\$HOME/clitools:\$PATH\"" >> "$HOME/.bashrc"
    
    print_status "~/clitools added to PATH. Please restart your shell or run 'source ~/.bashrc'"
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

# Function to initialize TAS environment variables
tas_initialize() {
    print_status "Initializing TAS (Trusted Artifact Signer) environment variables..."
    
    # Check if oc command exists
    if ! command -v oc &> /dev/null; then
        print_error "oc command not found. Please install OpenShift CLI first."
        exit 1
    fi
    
    # Get environment variable values from OpenShift
    print_status "Retrieving TUF URL..."
    local TUF_URL=$(oc get tuf -o jsonpath='{.items[0].status.url}' -n trusted-artifact-signer 2>/dev/null)
    if [[ -z "$TUF_URL" ]]; then
        print_error "Could not retrieve TUF URL from trusted-artifact-signer namespace"
        exit 1
    fi
    
    print_status "Retrieving Keycloak route..."
    local KEYCLOAK_HOST=$(oc get route keycloak -n keycloak --no-headers 2>/dev/null | tail -n 1 | awk '{print $2}')
    if [[ -z "$KEYCLOAK_HOST" ]]; then
        print_error "Could not retrieve Keycloak route from keycloak namespace"
        exit 1
    fi
    local OIDC_ISSUER_URL="https://${KEYCLOAK_HOST}/realms/backstage"
    
    print_status "Retrieving Fulcio URL..."
    local COSIGN_FULCIO_URL=$(oc get fulcio -o jsonpath='{.items[0].status.url}' -n trusted-artifact-signer 2>/dev/null)
    if [[ -z "$COSIGN_FULCIO_URL" ]]; then
        print_error "Could not retrieve Fulcio URL from trusted-artifact-signer namespace"
        exit 1
    fi
    
    print_status "Retrieving Rekor URL..."
    local COSIGN_REKOR_URL=$(oc get rekor -o jsonpath='{.items[0].status.url}' -n trusted-artifact-signer 2>/dev/null)
    if [[ -z "$COSIGN_REKOR_URL" ]]; then
        print_error "Could not retrieve Rekor URL from trusted-artifact-signer namespace"
        exit 1
    fi
    
    # Export environment variables for current session
    print_status "Setting environment variables..."
    export TUF_URL="$TUF_URL"
    export OIDC_ISSUER_URL="$OIDC_ISSUER_URL"
    export COSIGN_FULCIO_URL="$COSIGN_FULCIO_URL"
    export COSIGN_REKOR_URL="$COSIGN_REKOR_URL"
    export COSIGN_MIRROR="$TUF_URL"
    export COSIGN_ROOT="$TUF_URL/root.json"
    export COSIGN_OIDC_CLIENT_ID="trusted-artifact-signer"
    export COSIGN_OIDC_ISSUER="$OIDC_ISSUER_URL"
    export COSIGN_CERTIFICATE_OIDC_ISSUER="$OIDC_ISSUER_URL"
    export COSIGN_YES="true"
    export SIGSTORE_FULCIO_URL="$COSIGN_FULCIO_URL"
    export SIGSTORE_OIDC_ISSUER="$COSIGN_OIDC_ISSUER"
    export SIGSTORE_REKOR_URL="$COSIGN_REKOR_URL"
    export REKOR_REKOR_SERVER="$COSIGN_REKOR_URL"
    
    # Add environment variables to .bashrc for persistence
    print_status "Adding TAS environment variables to ~/.bashrc..."
    
    # Add a marker comment and the environment variables
    cat >> "$HOME/.bashrc" << EOF

# Added by TAS installer script - Trusted Artifact Signer environment variables
export TUF_URL="$TUF_URL"
export OIDC_ISSUER_URL="$OIDC_ISSUER_URL"
export COSIGN_FULCIO_URL="$COSIGN_FULCIO_URL"
export COSIGN_REKOR_URL="$COSIGN_REKOR_URL"
export COSIGN_MIRROR="$TUF_URL"
export COSIGN_ROOT="$TUF_URL/root.json"
export COSIGN_OIDC_CLIENT_ID="trusted-artifact-signer"
export COSIGN_OIDC_ISSUER="$OIDC_ISSUER_URL"
export COSIGN_CERTIFICATE_OIDC_ISSUER="$OIDC_ISSUER_URL"
export COSIGN_YES="true"
export SIGSTORE_FULCIO_URL="$COSIGN_FULCIO_URL"
export SIGSTORE_OIDC_ISSUER="$COSIGN_OIDC_ISSUER"
export SIGSTORE_REKOR_URL="$COSIGN_REKOR_URL"
export REKOR_REKOR_SERVER="$COSIGN_REKOR_URL"
EOF
    
    print_status "TAS environment variables initialized successfully!"
    print_status "TUF URL: $TUF_URL"
    print_status "OIDC Issuer URL: $OIDC_ISSUER_URL"
    print_status "Fulcio URL: $COSIGN_FULCIO_URL"
    print_status "Rekor URL: $COSIGN_REKOR_URL"
}

# Function to setup git configuration
setup_git() {
    print_status "Setting up global git configuration..."
    
    # Check if git command exists
    if ! command -v git &> /dev/null; then
        print_error "git command not found. Please install git first."
        exit 1
    fi
    
    # Configure user information
    print_status "Configuring user information..."
    git config --global user.email "boom@acme.com"
    git config --global user.name "Wile E. Coyote"
    
    # Configure credential helper
    print_status "Configuring credential helper... INSECURE, just for workshop convenience!"
    git config --global credential.helper "store"
    
    # Configure signing settings
    print_status "Configuring signing settings..."
    git config --global commit.gpgsign "true"
    git config --global tag.gpgsign "true"
    git config --global gpg.x509.program "gitsign"
    git config --global gpg.format "x509"
    
    # Configure gitsign settings with dynamic values
    print_status "Configuring gitsign settings..."
    git config --global gitsign.fulcio "$COSIGN_FULCIO_URL"
    git config --global gitsign.issuer "$OIDC_ISSUER_URL"
    git config --global gitsign.rekor "$COSIGN_REKOR_URL"
    git config --global gitsign.clientid "trusted-artifact-signer"
    
    print_status "Git configuration completed successfully!"
    print_status "Configured settings:"
    print_status "  User: Wile E. Coyote <boom@acme.com>"
    print_status "  Fulcio URL: $COSIGN_FULCIO_URL"
    print_status "  OIDC Issuer: $OIDC_ISSUER_URL"
    print_status "  Rekor URL: $COSIGN_REKOR_URL"
    print_status "  Client ID: trusted-artifact-signer"
}

# Function to install CLI tools
install_cli() {
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
    
    print_status "CLI installation completed successfully!"
}

# Set trap to cleanup on exit
trap cleanup EXIT

main() {
    # Run TAS initialization
    tas_initialize
    
    # Run CLI installation
    install_cli
    
    # Setup git configuration
    setup_git
    
    print_status "All installations and configurations completed successfully!"
}

# Run main function
main "$@"