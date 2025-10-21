#!/bin/bash

# Generate timestamp tag
TIMESTAMP=$(date +%d-%m-%Y-%H-%M)

echo "Building custom-web-terminal with tags:"
echo "  - latest"
echo "  - $TIMESTAMP"

# Build with both tags
podman build -t quay.io/tssc_demos/custom-web-terminal:latest -t quay.io/tssc_demos/custom-web-terminal:$TIMESTAMP -f Containerfile .

echo ""
echo "Build complete! Images tagged as:"
podman images custom-web-terminal
podman push quay.io/tssc_demos/custom-web-terminal:latest
podman push quay.io/tssc_demos/custom-web-terminal:$TIMESTAMP 