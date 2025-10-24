#!/bin/bash

# Generate timestamp tag
TIMESTAMP=$(date +%d-%m-%Y-%H-%M)

echo "Building custom-web-terminal with tags:"
echo "  - latest"
echo "  - $TIMESTAMP"

# Build with both tags
podman build -t quay.io/tssc_demos/ttyd-admin-terminal:latest -t quay.io/tssc_demos/ttyd-admin-terminal:$TIMESTAMP -f Containerfile .

echo ""
echo "Build complete! Images tagged as:"
podman images ttyd-admin-terminal
podman push quay.io/tssc_demos/ttyd-admin-terminal:latest
podman push quay.io/tssc_demos/ttyd-admin-terminal:$TIMESTAMP 
