#!/bin/bash
#set -euo pipefail

# Configuration variables
NAMESPACE="tssc-acs"
CLUSTER_NAME="ads-cluster"
TOKEN_NAME="setup-script-$(date +%d-%m-%Y_%H-%M-%S)"
TOKEN_ROLE="Admin"

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Prerequisites validation
log_info "Validating prerequisites..."

# Check if oc is available and connected
if ! oc whoami &>/dev/null; then
    log_error "OpenShift CLI not connected. Please login first."
    exit 1
fi

# Check if Central is running
if ! oc get deployment central -n $NAMESPACE &>/dev/null; then
    log_error "RHACS Central not found in namespace $NAMESPACE"
    exit 1
fi

# Wait for Central to be ready
log_info "Waiting for Central to be ready..."
oc wait --for=condition=Available deployment/central -n $NAMESPACE --timeout=300s

# Extract admin credentials
log_info "Extracting admin credentials..."
ADMIN_PASSWORD=$(oc get secret central-htpasswd -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d)

# Determine endpoints based on execution context
# External endpoint for API calls from bastion/external host
EXTERNAL_CENTRAL_ENDPOINT=$(oc get route central -n $NAMESPACE -o jsonpath='{.spec.host}'):443

# Internal endpoint for cluster components communication
INTERNAL_CENTRAL_ENDPOINT="central.${NAMESPACE}.svc.cluster.local:443"

log_info "External Central endpoint: $EXTERNAL_CENTRAL_ENDPOINT"
log_info "Internal Central endpoint: $INTERNAL_CENTRAL_ENDPOINT"

# Test connectivity to external Central endpoint
log_info "Testing connectivity to external Central endpoint..."
if ! curl -k -s --connect-timeout 10 "https://$EXTERNAL_CENTRAL_ENDPOINT" >/dev/null; then
    log_error "Cannot connect to Central at $EXTERNAL_CENTRAL_ENDPOINT"
    exit 1
fi

# Create API token programmatically using external endpoint
log_info "Creating API token: $TOKEN_NAME"
API_TOKEN_RESPONSE=$(curl -k -X POST \
  -u "admin:$ADMIN_PASSWORD" \
  -H "Content-Type: application/json" \
  --data "{\"name\":\"$TOKEN_NAME\",\"role\":\"$TOKEN_ROLE\"}" \
  "https://$EXTERNAL_CENTRAL_ENDPOINT/v1/apitokens/generate" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$API_TOKEN_RESPONSE" ]; then
    log_error "Failed to create API token"
    exit 1
fi

API_TOKEN=$(echo "$API_TOKEN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['token'])" 2>/dev/null)

if [ -z "$API_TOKEN" ]; then
    log_error "Failed to extract API token from response"
    echo $API_TOKEN_RESPONSE
    exit 1
fi

# Export environment variables for roxctl (using external endpoint)
export ROX_API_TOKEN="$API_TOKEN"
export ROX_ENDPOINT="$EXTERNAL_CENTRAL_ENDPOINT"

log_info "API token created successfully"

# Download roxctl if not available
if ! command -v roxctl &>/dev/null; then
    log_info "Downloading roxctl CLI..."
    curl -L -f -o /tmp/roxctl "https://mirror.openshift.com/pub/rhacs/assets/4.8.3/bin/Linux/roxctl"
    chmod +x /tmp/roxctl
    ROXCTL_CMD="/tmp/roxctl"
else
    ROXCTL_CMD="roxctl"
fi

# Test roxctl connectivity using external endpoint
log_info "Testing roxctl connectivity..."
if ! $ROXCTL_CMD central whoami --insecure-skip-tls-verify >/dev/null 2>&1; then
    log_error "roxctl authentication failed"
    exit 1
fi

# Generate init bundle using external endpoint
log_info "Generating init bundle for cluster: $CLUSTER_NAME"
$ROXCTL_CMD central init-bundles generate $CLUSTER_NAME \
  --output-secrets cluster_init_bundle.yaml --insecure-skip-tls-verify

if [ ! -f cluster_init_bundle.yaml ]; then
    log_error "Failed to generate init bundle"
    exit 1
fi

# Apply init bundle
log_info "Applying init bundle secrets..."
oc apply -f cluster_init_bundle.yaml -n $NAMESPACE

# Create SecuredCluster resource with INTERNAL endpoint
log_info "Creating SecuredCluster resource with internal endpoint..."
cat <<EOF | oc apply -f -
apiVersion: platform.stackrox.io/v1alpha1
kind: SecuredCluster
metadata:
  name: same-cluster-secured-services
  namespace: $NAMESPACE
spec:
  clusterName: "$CLUSTER_NAME"
  centralEndpoint: "$INTERNAL_CENTRAL_ENDPOINT"
  admissionControl:
    listenOnCreates: true
    listenOnEvents: true 
    listenOnUpdates: true
    enforceOnCreates: false
    enforceOnUpdates: false
    scanInline: true
    disableBypass: false
    timeoutSeconds: 20
  auditLogs:
    collection: Auto
  perNode:
    collector:
      collection: EBPF
      imageFlavor: Regular
      resources:
        limits:
          cpu: 750m
          memory: 1Gi
        requests:
          cpu: 50m
          memory: 320Mi
    taintToleration: TolerateTaints
  scanner:
    analyzer:
      scaling:
        autoScaling: Enabled
        maxReplicas: 5
        minReplicas: 1
        replicas: 3
      resources:
        limits:
          cpu: 2000m
          memory: 4Gi
        requests:
          cpu: 1000m
          memory: 1500Mi
    scannerComponent: AutoSense
EOF

# Wait for deployment
log_info "Waiting for SecuredCluster components to be ready..."


# Function to wait for resource to exist and then be ready
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local condition=$3
    local timeout=${4:-300}
    
    log_info "Waiting for $resource_type/$resource_name to be created..."
    local wait_count=0
    while ! oc get $resource_type $resource_name -n $NAMESPACE >/dev/null 2>&1; do
        if [ $wait_count -ge 60 ]; then  # 5 minutes max wait for creation
            log_warn "$resource_type/$resource_name was not created within 5 minutes"
            return 1
        fi
        sleep 5
        wait_count=$((wait_count + 1))
        echo -n "."
    done
    echo ""
    
    if [ "$resource_type" = "daemonset" ]; then
        # For DaemonSets, check if desired number of pods are scheduled and ready
        log_info "$resource_type/$resource_name created, waiting for all pods to be ready..."
        local ready_timeout=$((timeout / 5))  # Check every 5 seconds
        local check_count=0
        
        while [ $check_count -lt $ready_timeout ]; do
            local status=$(oc get daemonset $resource_name -n $NAMESPACE -o jsonpath='{.status.desiredNumberScheduled},{.status.numberReady}' 2>/dev/null)
            local desired=$(echo $status | cut -d',' -f1)
            local ready=$(echo $status | cut -d',' -f2)
            
            if [ -n "$desired" ] && [ -n "$ready" ] && [ "$desired" = "$ready" ] && [ "$desired" != "0" ]; then
                log_info "✓ $resource_type/$resource_name is ready ($ready/$desired pods running)"
                return 0
            fi
            
            if [ -n "$desired" ] && [ -n "$ready" ]; then
                log_info "DaemonSet $resource_name: $ready/$desired pods ready..."
            fi
            
            sleep 5
            check_count=$((check_count + 1))
        done
        
        log_warn "$resource_type/$resource_name readiness timeout (not all pods ready within ${timeout}s)"
        return 1
    else
        # For other resources (Deployments), use standard condition waiting
        log_info "$resource_type/$resource_name created, waiting for $condition condition..."
        if oc wait --for=condition=$condition $resource_type/$resource_name -n $NAMESPACE --timeout=${timeout}s; then
            log_info "✓ $resource_type/$resource_name is ready"
            return 0
        else
            log_warn "$resource_type/$resource_name $condition condition timeout"
            return 1
        fi
    fi
}

# Wait for sensor deployment
wait_for_resource "deployment" "sensor" "Available" 300

# Wait for admission-control deployment  
wait_for_resource "deployment" "admission-control" "Available" 300

# Wait for collector daemonset
wait_for_resource "daemonset" "collector" "" 300
# Verification
log_info "Verifying deployment..."

# Check pod status
FAILED_PODS=$(oc get pods -n $NAMESPACE --field-selector=status.phase!=Running,status.phase!=Succeeded -o name | wc -l)
if [ "$FAILED_PODS" -gt 0 ]; then
    log_warn "$FAILED_PODS pods are not in Running/Succeeded state"
    oc get pods -n $NAMESPACE
fi



# Clean up temporary files
rm -f cluster_init_bundle.yaml
[ "$ROXCTL_CMD" = "/tmp/roxctl" ] && rm -f /tmp/roxctl

log_info "RHACS same-cluster configuration completed successfully!"
log_info "Have a nice day 🍻🍻🍻"