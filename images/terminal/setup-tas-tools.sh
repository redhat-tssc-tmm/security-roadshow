#!/bin/bash

# setup-tas-tools.sh: Download Trusted Artifact Signer CLI tools if TAS is installed

#set -e

echo "Checking for Trusted Artifact Signer installation..."

# Check if the trusted-artifact-signer namespace exists
if ! oc get namespace trusted-artifact-signer >/dev/null 2>&1; then
    echo "Trusted Artifact Signer namespace not found. Skipping CLI tools setup."
    return 0 2>/dev/null || exit 0
fi

echo "Found trusted-artifact-signer namespace. Setting up CLI tools..."

# Get the cli-server service URL
# Using service internal DNS: <service-name>.<namespace>.svc.cluster.local
CLI_SERVER="cli-server.trusted-artifact-signer.svc.cluster.local"

# Check if service exists
if ! oc get service cli-server -n trusted-artifact-signer >/dev/null 2>&1; then
    echo "Warning: cli-server service not found in trusted-artifact-signer namespace"
    return 0 2>/dev/null || exit 0
fi

# Get the service port
SERVICE_PORT=$(oc get service cli-server -n trusted-artifact-signer -o jsonpath='{.spec.ports[0].port}')

if [[ -z "$SERVICE_PORT" ]]; then
    echo "Warning: Could not determine cli-server service port"
    return 0 2>/dev/null || exit 0
fi

CLI_SERVER_URL="http://${CLI_SERVER}:${SERVICE_PORT}"

echo "CLI Server: $CLI_SERVER_URL"

# Create temporary directory for downloads
DOWNLOAD_DIR="/tmp/tas-cli-downloads"
mkdir -p "$DOWNLOAD_DIR"

# Create target directory for CLI tools
CLI_TOOLS_DIR="/home/student/clitools"
mkdir -p "$CLI_TOOLS_DIR"

# List of binaries to download
BINARIES=(
    "cosign-amd64.gz"
    "ec-amd64.gz"
    "gitsign-amd64.gz"
    "rekor-cli-amd64.gz"
    "tuftool-amd64.gz"
)

# The service can exist while its pod is still starting, and this script runs
# once at container start with no second chance. Wait for the server to answer
# before downloading anything, rather than failing the whole set on a race.
WAIT_ATTEMPTS=60
WAIT_INTERVAL=2

echo "Waiting for CLI server to respond..."
READY=0
for _ in $(seq 1 "$WAIT_ATTEMPTS"); do
    if curl -sf -o /dev/null --max-time 5 -r 0-0 "$CLI_SERVER_URL/clients/linux/${BINARIES[0]}"; then
        READY=1
        break
    fi
    sleep "$WAIT_INTERVAL"
done

if [[ "$READY" -ne 1 ]]; then
    echo "Warning: CLI server did not respond within $((WAIT_ATTEMPTS * WAIT_INTERVAL))s - skipping CLI tools setup."
    echo "Re-run this script once it is reachable:  bash ~/setup-tas-tools.sh"
    rm -rf "$DOWNLOAD_DIR"
    return 0 2>/dev/null || exit 0
fi

INSTALLED=()
FAILED=()

# Download and extract each binary
for binary in "${BINARIES[@]}"; do
    echo "Downloading $binary..."

    # Download the binary
    if curl -f -L --retry 5 --retry-delay 3 --retry-connrefused \
         -o "$DOWNLOAD_DIR/$binary" "$CLI_SERVER_URL/clients/linux/$binary" 2>/dev/null; then
        echo "  ✓ Downloaded $binary"

        # Extract the binary
        gunzip -f "$DOWNLOAD_DIR/$binary"

        # Get the extracted filename (without .gz extension)
        extracted_name="${binary%.gz}"

        # Remove -amd64 suffix for the final binary name
        final_name="${extracted_name%-amd64}"

        # Move to CLI tools directory with clean name and make executable
        mv "$DOWNLOAD_DIR/$extracted_name" "$CLI_TOOLS_DIR/$final_name"
        chmod +x "$CLI_TOOLS_DIR/$final_name"

        echo "  ✓ Installed $final_name"
        INSTALLED+=("$final_name")
    else
        echo "  ✗ Failed to download $binary (skipping)"
        FAILED+=("$binary")
    fi
done

# Clean up download directory
rm -rf "$DOWNLOAD_DIR"

# Verify installations
echo ""
echo "Installed TAS CLI tools in $CLI_TOOLS_DIR:"
ls -lh "$CLI_TOOLS_DIR"

echo ""
if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "WARNING: ${#FAILED[@]} of ${#BINARIES[@]} TAS CLI tools did NOT install:"
    printf '  - %s\n' "${FAILED[@]}"
    echo "Those commands will not be on your PATH."
    echo "Re-run this script to try again:  bash ~/setup-tas-tools.sh"
else
    echo "TAS CLI tools setup complete! The following tools are now available:"
    printf '  - %s\n' "${INSTALLED[@]}"
fi
