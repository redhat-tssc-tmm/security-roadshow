#!/bin/bash

# setup-tas-environment.sh: Configure TAS environment variables for student terminal
# Usage: setup-tas-environment.sh [TAS_NAMESPACE]
#   TAS_NAMESPACE: Optional namespace containing TAS installation (default: tssc-tas)

#set -e

# Get TAS namespace from parameter or use default
TAS_NAMESPACE="${1:-tssc-tas}"

# Helper functions for output
print_status() {
    echo "[INFO] $1"
}

print_error() {
    echo "[ERROR] $1" >&2
}

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






print_status "Initializing TAS (Trusted Artifact Signer) environment variables..."
print_status "Using TAS namespace: $TAS_NAMESPACE"

# Check if TAS namespace exists
if ! oc get namespace "$TAS_NAMESPACE" >/dev/null 2>&1; then
    print_error "Namespace '$TAS_NAMESPACE' not found. TAS environment variables will not be configured."
    return 0 2>/dev/null || exit 0
fi

# Check if tssc-keycloak namespace exists
if ! oc get namespace tssc-keycloak >/dev/null 2>&1; then
    print_error "Namespace 'tssc-keycloak' not found. TAS environment variables will not be configured."
    return 0 2>/dev/null || exit 0
fi

print_status "TAS namespaces found. Retrieving configuration..."

# Get environment variable values from OpenShift
print_status "Retrieving TUF URL..."
TUF_URL=$(oc get tuf -o jsonpath='{.items[0].status.url}' -n "$TAS_NAMESPACE" 2>/dev/null)
if [[ -z "$TUF_URL" ]]; then
    print_error "Could not retrieve TUF URL from $TAS_NAMESPACE namespace"
    return 0 2>/dev/null || exit 0
fi

print_status "Retrieving Keycloak route..."
KEYCLOAK_HOST=$(oc get route keycloak -n tssc-keycloak --no-headers 2>/dev/null | tail -n 1 | awk '{print $2}')
if [[ -z "$KEYCLOAK_HOST" ]]; then
    print_error "Could not retrieve Keycloak route from tssc-keycloak namespace"
    return 0 2>/dev/null || exit 0
fi
OIDC_ISSUER_URL="https://${KEYCLOAK_HOST}/realms/trusted-artifact-signer"

print_status "Retrieving Fulcio URL..."
COSIGN_FULCIO_URL=$(oc get fulcio -o jsonpath='{.items[0].status.url}' -n "$TAS_NAMESPACE" 2>/dev/null)
if [[ -z "$COSIGN_FULCIO_URL" ]]; then
    print_error "Could not retrieve Fulcio URL from $TAS_NAMESPACE namespace"
    return 0 2>/dev/null || exit 0
fi

print_status "Retrieving Rekor URL..."
COSIGN_REKOR_URL=$(oc get rekor -o jsonpath='{.items[0].status.url}' -n "$TAS_NAMESPACE" 2>/dev/null)
if [[ -z "$COSIGN_REKOR_URL" ]]; then
    print_error "Could not retrieve Rekor URL from $TAS_NAMESPACE namespace"
    return 0 2>/dev/null || exit 0
fi

# Export all environment variables to current shell session
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
export SIGSTORE_OIDC_ISSUER="$OIDC_ISSUER_URL"
export SIGSTORE_REKOR_URL="$COSIGN_REKOR_URL"
export REKOR_REKOR_SERVER="$COSIGN_REKOR_URL"

# Add environment variables to .bashrc for persistence
print_status "Adding TAS environment variables to ~/.bashrc..."

# Check if variables are already in .bashrc to avoid duplicates
if grep -q "# TAS environment variables" /home/student/.bashrc 2>/dev/null; then
    print_status "TAS environment variables already configured in .bashrc"
else
    # Add a marker comment and the environment variables
    cat >> "/home/student/.bashrc" << EOF

# TAS environment variables - Trusted Artifact Signer configuration
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
export SIGSTORE_OIDC_ISSUER="$OIDC_ISSUER_URL"
export SIGSTORE_REKOR_URL="$COSIGN_REKOR_URL"
export REKOR_REKOR_SERVER="$COSIGN_REKOR_URL"
setup_git
EOF
fi

print_status "TAS environment variables initialized successfully!"
print_status "TUF URL: $TUF_URL"
print_status "OIDC Issuer URL: $OIDC_ISSUER_URL"
print_status "Fulcio URL: $COSIGN_FULCIO_URL"
print_status "Rekor URL: $COSIGN_REKOR_URL"

setup_git
