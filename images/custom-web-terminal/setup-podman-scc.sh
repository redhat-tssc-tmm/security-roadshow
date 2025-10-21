#!/bin/bash

# Create Podman configuration in runtime-owned directory
mkdir -p $XDG_CONFIG_HOME/containers
cat > $XDG_CONFIG_HOME/containers/storage.conf << 'EOF'
[storage]
driver = "vfs"
runroot = "/tmp/run-containers"
graphroot = "/tmp/containers-storage"
EOF

# Get current service account
SA_NAME=$(cat /var/run/secrets/kubernetes.io/serviceaccount/../../serviceaccount/name 2>/dev/null || echo "web-terminal-exec")
NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null || oc project -q 2>/dev/null)

echo "Configuring Podman support..."
# Add SCC for Podman
oc adm policy add-scc-to-user privileged -z "$SA_NAME" -n "$NAMESPACE" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✓ SCC configured successfully - Podman is ready to use"
else
    echo "⚠ Failed to configure SCC for Podman"
fi