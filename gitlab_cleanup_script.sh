#!/bin/bash

# GitLab Repository Cleanup Script with Token Creation
# This script can create a personal access token and then delete repositories

# Note: Removed 'set -e' to prevent silent exits during token creation
# set -e  # Exit on any error

# Configuration
GITLAB_URL=""                 # Will be extracted from git remote
GITLAB_TOKEN=""               # Will be retrieved from OpenShift secret
DRY_RUN=true                 # Set to false to actually delete repositories
GITLAB_NAMESPACE="gitlab"     # Namespace containing the GitLab secret
SECRET_NAME="root-user-personal-token"  # Secret name containing the token
SECRET_KEY="token"            # Key within the secret

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to get GitLab token from OpenShift secret
get_token_from_openshift() {
    local namespace="$1"
    local secret_name="$2"
    local secret_key="$3"
    
    print_info "Retrieving GitLab token from OpenShift secret..." >&2
    print_info "Namespace: $namespace" >&2
    print_info "Secret: $secret_name" >&2
    print_info "Key: $secret_key" >&2
    
    # Check if oc command is available
    if ! command -v oc &> /dev/null; then
        print_error "OpenShift CLI (oc) is not installed or not in PATH" >&2
        print_error "Please install the OpenShift CLI: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html" >&2
        return 1
    fi
    
    # Check if logged in to OpenShift
    if ! oc whoami &> /dev/null; then
        print_error "Not logged in to OpenShift cluster" >&2
        print_error "Please log in using: oc login <cluster-url>" >&2
        return 1
    fi
    
    local current_user=$(oc whoami 2>/dev/null)
    print_info "Logged in to OpenShift as: $current_user" >&2
    
    # Check if the namespace exists and is accessible
    if ! oc get namespace "$namespace" &> /dev/null; then
        print_error "Cannot access namespace '$namespace'" >&2
        print_error "Either the namespace doesn't exist or you don't have access to it" >&2
        return 1
    fi
    
    # Check if the secret exists
    if ! oc get secret "$secret_name" -n "$namespace" &> /dev/null; then
        print_error "Secret '$secret_name' not found in namespace '$namespace'" >&2
        print_error "Available secrets in namespace:" >&2
        oc get secrets -n "$namespace" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null >&2 || echo "  (unable to list secrets)" >&2
        return 1
    fi
    
    # Extract the token from the secret
    local token=$(oc get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.$secret_key}" 2>/dev/null | base64 -d 2>/dev/null)
    
    if [ -z "$token" ]; then
        print_error "Could not extract token from secret '$secret_name' key '$secret_key'" >&2
        print_error "Available keys in secret:" >&2
        oc get secret "$secret_name" -n "$namespace" -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[]' 2>/dev/null >&2 || echo "  (unable to list keys)" >&2
        return 1
    fi
    
    # Validate token format (GitLab personal access tokens should start with glpat-)
    if [[ ! "$token" =~ ^glpat- ]]; then
        print_warn "Token doesn't start with 'glpat-' - this might not be a GitLab personal access token" >&2
        print_info "Token starts with: ${token:0:10}..." >&2
    else
        print_info "Successfully retrieved GitLab token: ${token:0:10}..." >&2
    fi
    
    # Output only the token to stdout
    echo "$token"
    return 0
}
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not in a git repository!"
        exit 1
    fi
}

# Function to check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not in a git repository!"
        exit 1
    fi
}

# Function to cleanup temporary files (minimal now)
cleanup_temp_files() {
    # No temporary files to clean up anymore
    :
}

# Function to extract GitLab URL from remote
extract_gitlab_url() {
    local remote_name=${1:-origin}
    
    # Get the remote URL
    local remote_url=$(git remote get-url "$remote_name" 2>/dev/null || echo "")
    
    if [ -z "$remote_url" ]; then
        print_error "No remote '$remote_name' found!" >&2
        return 1
    fi
    
    print_info "Remote URL: $remote_url" >&2
    
    # Extract GitLab base URL from remote URL
    local gitlab_url=""
    if [[ $remote_url =~ git@([^:]+): ]]; then
        # SSH format: git@gitlab.example.com:user/repo.git
        gitlab_url="https://${BASH_REMATCH[1]}"
    elif [[ $remote_url =~ (https?://[^/]+)/ ]]; then
        # HTTPS format: https://gitlab.example.com/user/repo.git
        gitlab_url="${BASH_REMATCH[1]}"
    else
        print_error "Could not parse GitLab URL from remote: $remote_url" >&2
        return 1
    fi
    
    # Output only the clean URL to stdout
    echo "$gitlab_url"
}

# Function to get remote repository information
get_remote_info() {
    local remote_name=${1:-origin}
    
    # Get the remote URL
    local remote_url=$(git remote get-url "$remote_name" 2>/dev/null || echo "")
    
    if [ -z "$remote_url" ]; then
        print_error "No remote '$remote_name' found!" >&2
        return 1
    fi
    
    print_info "Remote URL: $remote_url" >&2
    
    # Extract project path from GitLab URL
    # Handles both SSH and HTTPS URLs
    local project_path=""
    if [[ $remote_url =~ git@.*:(.+)\.git$ ]]; then
        # SSH format: git@gitlab.com:user/repo.git
        project_path="${BASH_REMATCH[1]}"
    elif [[ $remote_url =~ https?://[^/]+/(.+)\.git$ ]]; then
        # HTTPS format: https://gitlab.com/user/repo.git
        project_path="${BASH_REMATCH[1]}"
    elif [[ $remote_url =~ https?://[^/]+/(.+)$ ]]; then
        # HTTPS format without .git: https://gitlab.com/user/repo
        project_path="${BASH_REMATCH[1]}"
    else
        print_error "Could not parse GitLab project path from URL: $remote_url" >&2
        return 1
    fi
    
    print_info "Project path: $project_path" >&2
    
    # Output only the project path to stdout
    echo "$project_path"
}

# Function to get project ID from GitLab API
get_project_id() {
    local project_path="$1"
    # Remove any trailing whitespace/newlines and then URL encode
    local clean_path=$(echo "$project_path" | tr -d '\n\r' | sed 's/[[:space:]]*$//')
    local encoded_path=$(printf '%s' "$clean_path" | jq -sRr @uri)
    
    print_info "Looking up project ID for: $project_path" >&2
    print_info "Clean path: $clean_path" >&2
    print_info "Encoded path: $encoded_path" >&2
    
    local response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$encoded_path" 2>&1)
    
    local curl_exit_code=$?
    # print_info "Debug: curl exit code for project lookup: $curl_exit_code" >&2
    
    if [ $curl_exit_code -ne 0 ]; then
        print_error "curl command failed for project lookup with exit code: $curl_exit_code" >&2
        return 1
    fi
    
    local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
    local json_response=$(echo "$response" | sed '/HTTP_CODE:/d')
    
    print_info "Project lookup HTTP Code: $http_code" >&2
    
    if [ "$http_code" != "200" ]; then
        print_error "Could not find project $project_path" >&2
        print_error "HTTP Code: $http_code" >&2
        print_error "API Response: $json_response" >&2
        return 1
    fi
    
    local project_id=$(echo "$json_response" | jq -r '.id // empty')
    
    if [ -z "$project_id" ] || [ "$project_id" = "null" ]; then
        print_error "Could not extract project ID from response" >&2
        print_error "API Response: $json_response" >&2
        return 1
    fi
    
    print_info "Found project ID: $project_id" >&2
    
    # Output only the project ID to stdout
    echo "$project_id"
}

# Function to delete repository from GitLab
delete_repository() {
    local project_id="$1"
    local project_path="$2"
    
    if [ "$DRY_RUN" = true ]; then
        print_warn "DRY RUN: Would delete project ID $project_id ($project_path)"
        return 0
    fi
    
    print_warn "Deleting repository: $project_path (ID: $project_id)"

    
    local response=$(curl -s -X DELETE -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$project_id")
    
    if [ $? -eq 0 ]; then
        print_info "Successfully deleted repository: $project_path"
    else
        print_error "Failed to delete repository: $project_path"
        print_error "Response: $response"
        return 1
    fi
}

# Function to validate token
validate_token() {
    if [ -z "$GITLAB_TOKEN" ]; then
        print_error "No GitLab token available!"
        exit 1
    fi
    
    # Test GitLab API connectivity
    print_info "Testing GitLab API connectivity with token..."
    print_info "Using token: ${GITLAB_TOKEN:0:10}..." # Show first 10 chars for debugging
    print_info "GitLab URL: $GITLAB_URL"
    
    # Debug: show the exact curl command being run
    # print_info "Debug: Running curl command..."
    
    local response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/user" 2>&1)
    local curl_exit_code=$?
    
    # print_info "Debug: curl exit code: $curl_exit_code"
    # print_info "Debug: raw response: '$response'"
    
    if [ $curl_exit_code -ne 0 ]; then
        print_error "curl command failed with exit code: $curl_exit_code"
        print_error "This might indicate a network connectivity issue"
        exit 1
    fi
    
    local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
    local json_response=$(echo "$response" | sed '/HTTP_CODE:/d')
    
    print_info "HTTP Code: '$http_code'"
    # print_info "Response: '$json_response'"
    
    if [ "$http_code" = "200" ]; then
        local username=$(echo "$json_response" | jq -r '.username // empty' 2>/dev/null)
        
        if [ -n "$username" ] && [ "$username" != "null" ] && [ "$username" != "empty" ]; then
            print_info "Connected to GitLab as: $username"
            return 0
        else
            print_error "Could not parse username from response"
            print_error "Full response: $json_response"
            exit 1
        fi
    else
        print_error "Could not connect to GitLab API or invalid token"
        print_error "HTTP Code: '$http_code'"
        print_error "Response: '$json_response'"
        
        if [ "$http_code" = "401" ]; then
            print_error "Authentication failed - token might be invalid"
        elif [ "$http_code" = "404" ]; then
            print_error "API endpoint not found - check GitLab URL"
        elif [ -z "$http_code" ]; then
            print_error "No HTTP response received - check network connectivity and GitLab URL"
        fi
        
        exit 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [options] [remote_name]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -n, --dry-run       Show what would be deleted without actually deleting"
    echo "  --execute           Actually delete the repository (overrides dry-run)"
    echo "  --token TOKEN       GitLab personal access token (optional - will use OpenShift secret by default)"
    echo "  --url URL           GitLab instance URL (optional - auto-detected from git remote)"
    echo "  --namespace NS      OpenShift namespace containing GitLab secret (default: gitlab)"
    echo "  --secret NAME       Name of secret containing GitLab token (default: root-user-personal-token)"
    echo "  --secret-key KEY    Key within secret containing token (default: token)"
    echo ""
    echo "Arguments:"
    echo "  remote_name         Git remote name (default: origin)"
    echo ""
    echo "Examples:"
    echo "  $0 --dry-run                           # Show what would be deleted (uses OpenShift secret)"
    echo "  $0 --execute                           # Delete repository using token from OpenShift"
    echo "  $0 --token glpat-xxx --execute         # Delete using manual token (bypasses OpenShift)"
    echo "  $0 --namespace custom --execute        # Use token from 'custom' namespace"
    echo "  $0 --secret my-token --execute         # Use different secret name"
    echo ""
    echo "Note: GitLab URL is automatically extracted from git remote. Use --url to override."
    echo "Token is retrieved from OpenShift secret by default. Requires 'oc' CLI and cluster login."
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --execute)
                DRY_RUN=false
                shift
                ;;
            --token)
                GITLAB_TOKEN="$2"
                shift 2
                ;;
            --namespace)
                GITLAB_NAMESPACE="$2"
                shift 2
                ;;
            --secret)
                SECRET_NAME="$2"
                shift 2
                ;;
            --secret-key)
                SECRET_KEY="$2"
                shift 2
                ;;
            --url)
                GITLAB_URL="$2"
                shift 2
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                REMOTE_NAME="$1"
                shift
                ;;
        esac
    done
    
    # Set default remote name if not provided
    REMOTE_NAME=${REMOTE_NAME:-origin}
    
    # Validate we're in a git repository first
    check_git_repo
    
    # Extract GitLab URL from remote
    print_info "Extracting GitLab URL from remote '$REMOTE_NAME'..."
    GITLAB_URL=$(extract_gitlab_url "$REMOTE_NAME")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    print_info "Starting GitLab repository cleanup..."
    print_info "GitLab URL: $GITLAB_URL"
    print_info "Remote: $REMOTE_NAME"
    print_info "Dry run: $DRY_RUN"
    
    # Setup cleanup trap
    trap cleanup_temp_files EXIT
    
    # Get GitLab token (from OpenShift or manual)
    if [ -n "$GITLAB_TOKEN" ]; then
        print_info "Using provided token"
    else
        print_info "Getting GitLab token from OpenShift secret..."
        # print_info "Debug: About to call get_token_from_openshift with namespace='$GITLAB_NAMESPACE', secret='$SECRET_NAME', key='$SECRET_KEY'"
        
        GITLAB_TOKEN=$(get_token_from_openshift "$GITLAB_NAMESPACE" "$SECRET_NAME" "$SECRET_KEY")
        local token_result=$?
        
        # print_info "Debug: get_token_from_openshift returned code: $token_result"
        # print_info "Debug: Retrieved token value: '$GITLAB_TOKEN'"
        # print_info "Debug: Token length: ${#GITLAB_TOKEN}"
        
        if [ $token_result -ne 0 ] || [ -z "$GITLAB_TOKEN" ]; then
            print_error "Failed to retrieve GitLab token from OpenShift"
            print_error "Return code: $token_result"
            print_error "Token value: '$GITLAB_TOKEN'"
            exit 1
        fi
        print_info "Successfully retrieved GitLab token from OpenShift"
    fi
    
    # Validate token works
    validate_token
    
    # Get remote repository information
    print_info "Getting remote repository information..."
    PROJECT_PATH=$(get_remote_info "$REMOTE_NAME")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    # Get project ID from GitLab
    PROJECT_ID=$(get_project_id "$PROJECT_PATH")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    print_info "Found project: $PROJECT_PATH (ID: $PROJECT_ID)"
    
    # Delete the repository
    delete_repository "$PROJECT_ID" "$PROJECT_PATH"
    
    print_info "Cleanup script completed!"
}

# Check for required dependencies
for cmd in git curl jq; do
    if ! command -v $cmd &> /dev/null; then
        print_error "$cmd is required but not installed."
        exit 1
    fi
done

# Run main function with all arguments
main "$@"