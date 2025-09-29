#!/bin/bash

# Configure oc CLI with service account token
export KUBECONFIG=/home/student/.kube/config

# Get the service account token
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)

# Get cluster info
KUBERNETES_SERVICE_HOST=${KUBERNETES_SERVICE_HOST:-kubernetes.default.svc}
KUBERNETES_SERVICE_PORT=${KUBERNETES_SERVICE_PORT:-443}

# Configure oc with the service account
oc config set-cluster openshift \
  --server=https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT} \
  --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

oc config set-credentials terminal-admin \
  --token=${TOKEN}

oc config set-context openshift \
  --cluster=openshift \
  --user=terminal-admin \
  --namespace=${NAMESPACE}

oc config use-context openshift

# Verify connection
echo "OpenShift CLI configured successfully!"
echo "Current user: $(oc whoami)"
echo "Current context: $(oc config current-context)"
echo "Available projects: $(oc get projects --no-headers | wc -l)"

# Start ttyd with bash
exec /usr/local/bin/ttyd \
    --port 7681 \
    --interface 0.0.0.0 \
    --writable \
    --client-option fontFamily="'Courier New', monospace" \
    --client-option fontSize=18 \
    --client-option titleFixed="OpenShift Terminal" \
    --client-option disableReconnect=true \
    bash 
