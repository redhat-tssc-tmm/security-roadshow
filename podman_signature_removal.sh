#!/bin/bash

# Script to remove all signatures from a Quay repository using podman/skopeo
# Usage: ./remove_signatures_podman.sh [username] [password]

# Note: Removed 'set -e' to handle errors more explicitly

# Configuration
QUAY_URL=$(oc -n quay-enterprise get route quay-quay -o jsonpath='{.spec.host}')
NAMESPACE="quayadmin"
REPOSITORY="frontend"
FULL_REPO="$QUAY_URL/$NAMESPACE/$REPOSITORY"
CREDENTIALS_FILE="quay-credentials.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is required but not installed."
        case "$1" in
            "podman")
                echo "Install with: sudo dnf install podman (RHEL/Fedora) or sudo apt install podman (Ubuntu)"
                ;;
            "skopeo")
                echo "Install with: sudo dnf install skopeo (RHEL/Fedora) or sudo apt install skopeo (Ubuntu)"
                ;;
            "jq")
                echo "Install with: sudo dnf install jq (RHEL/Fedora) or sudo apt install jq (Ubuntu)"
                ;;
        esac
        exit 1
    fi
}

# Check required commands
check_command "podman"
check_command "skopeo"
check_command "jq"

# Function to get password from OpenShift secret
get_password_from_openshift() {
    # Send debug info to stderr so it doesn't get captured in command substitution
    echo "[INFO] Retrieving password from OpenShift secret..." >&2
    echo "[INFO] Executing: oc get secret argocd-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d" >&2
    
    local password
    
    # Get and decode the password in one step
    if password=$(oc get secret argocd-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d 2>/dev/null); then
        if [[ -n "$password" ]]; then
            echo "[INFO] Successfully retrieved and decoded password (length: ${#password})" >&2
            # Trim any whitespace/newlines
            password=$(echo "$password" | tr -d '\n\r\t ')
            echo "[INFO] Trimmed password (length: ${#password})" >&2
            # Only output the password to stdout
            echo "$password"
            return 0
        else
            echo "[ERROR] Retrieved empty password from OpenShift secret" >&2
            return 1
        fi
    else
        echo "[ERROR] Failed to execute oc command or decode password" >&2
        return 1
    fi
}

# Function to test credentials
test_credentials() {
    local test_username="$1"
    local test_password="$2"
    
    print_info "Testing credentials for user: $test_username"
    
    # Debug info
    if [[ -z "$test_password" ]]; then
        print_error "Password is empty, cannot test credentials"
        return 1
    fi
    
    print_info "Password length: ${#test_password}"
    
    # Add a small delay to avoid rate limiting
    sleep 2
    
    # Try to login with the provided credentials
    local login_output
    if login_output=$(echo "$test_password" | podman login --username "$test_username" --password-stdin "$QUAY_URL" 2>&1); then
        print_info "Credentials validated successfully"
        print_info "Login output: $login_output"
        podman logout "$QUAY_URL" 2>/dev/null || true
        return 0
    else
        print_warning "Credential test failed"
        print_warning "Login error: $login_output"
        return 1
    fi
}
create_credentials_file() {
    local file_path="$1"
    print_info "Creating credentials file: $file_path"
    
    # Use /dev/tty to read from terminal even when script is piped
    echo -n "Enter Quay username: " > /dev/tty
    read -r username < /dev/tty
    
    echo -n "Enter Quay password: " > /dev/tty
    read -s password < /dev/tty
    echo  # New line after hidden password input
    
    # Create the credentials file
    cat > "$file_path" << EOF
USERNAME=$username
PASSWORD=$password
EOF
    
    # Set secure permissions
    chmod 600 "$file_path"
    print_info "Credentials file created with secure permissions (600)"
}

# Function to find credentials file
find_credentials_file() {
    # Check current directory first
    if [[ -f "./$CREDENTIALS_FILE" ]]; then
        echo "./$CREDENTIALS_FILE"
        return 0
    fi
    
    # Check home directory
    if [[ -f "$HOME/$CREDENTIALS_FILE" ]]; then
        echo "$HOME/$CREDENTIALS_FILE"
        return 0
    fi
    
    return 1
}

# Get credentials from command line arguments or other sources
CMD_USERNAME="$1"
CMD_PASSWORD="$2"

# Initialize credentials
USERNAME=""
PASSWORD=""

# Try different credential sources in order of preference
if [[ -n "$CMD_USERNAME" && -n "$CMD_PASSWORD" ]]; then
    print_info "Using credentials from command line arguments"
    if test_credentials "$CMD_USERNAME" "$CMD_PASSWORD"; then
        USERNAME="$CMD_USERNAME"
        PASSWORD="$CMD_PASSWORD"
        print_info "Command line credentials validated"
    else
        print_warning "Command line credentials failed validation, trying other sources..."
    fi
fi

# If no valid credentials yet, try credentials file
if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
    CREDS_PATH=""
    if CREDS_PATH=$(find_credentials_file); then
        print_info "Found credentials file: $CREDS_PATH"
        source "$CREDS_PATH"
        
        # Validate credentials from file
        if [[ -n "$USERNAME" && -n "$PASSWORD" ]]; then
            if test_credentials "$USERNAME" "$PASSWORD"; then
                print_info "Credentials file validated"
            else
                print_warning "Credentials from file failed validation, trying other sources..."
                USERNAME=""
                PASSWORD=""
            fi
        fi
    fi
fi

# If still no valid credentials, try OpenShift secret
if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
    print_info "Trying OpenShift secret for quayadmin user..."
    if OC_PASSWORD=$(get_password_from_openshift); then
        print_info "Retrieved password from OpenShift, testing credentials..."
        if test_credentials "quayadmin" "$OC_PASSWORD"; then
            USERNAME="quayadmin"
            PASSWORD="$OC_PASSWORD"
            print_info "OpenShift secret credentials validated"
            
            # Save to credentials file for future use
            if [[ -w "." ]]; then
                CREDS_PATH="./$CREDENTIALS_FILE"
                print_info "Saving validated credentials to file: $CREDS_PATH"
                cat > "$CREDS_PATH" << EOF
USERNAME=$USERNAME
PASSWORD=$PASSWORD
EOF
                chmod 600 "$CREDS_PATH"
                print_info "Credentials saved with secure permissions (600)"
            elif [[ -w "$HOME" ]]; then
                CREDS_PATH="$HOME/$CREDENTIALS_FILE"
                print_info "Saving validated credentials to file: $CREDS_PATH"
                cat > "$CREDS_PATH" << EOF
USERNAME=$USERNAME
PASSWORD=$PASSWORD
EOF
                chmod 600 "$CREDS_PATH"
                print_info "Credentials saved with secure permissions (600)"
            fi
        else
            print_warning "OpenShift secret credentials failed validation"
            print_info "Password retrieved but login test failed"
        fi
    else
        print_warning "Could not retrieve password from OpenShift secret"
    fi
fi

# If still no valid credentials, prompt interactively
if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
    print_warning "No valid credentials found from any source"
    print_info "Please provide your Quay credentials interactively:"
    
    # Try to create in current directory first
    if [[ -w "." ]]; then
        CREDS_PATH="./$CREDENTIALS_FILE"
        create_credentials_file "$CREDS_PATH"
    elif [[ -w "$HOME" ]]; then
        CREDS_PATH="$HOME/$CREDENTIALS_FILE"
        create_credentials_file "$CREDS_PATH"
    else
        print_error "Cannot write credentials file to current directory or home directory"
        exit 1
    fi
    
    # Read the newly created credentials
    source "$CREDS_PATH"
fi

# Validate final credentials
if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
    print_error "USERNAME or PASSWORD not found from any source!"
    exit 1
fi

print_info "Using username: $USERNAME"
print_info "Target repository: $FULL_REPO"

# Function to login to registry
login_to_registry() {
    print_info "Logging into Quay registry..."
    
    # Try podman login
    if echo "$PASSWORD" | podman login --username "$USERNAME" --password-stdin "$QUAY_URL" 2>/dev/null; then
        print_info "Successfully logged in with podman"
        return 0
    fi
    
    # Try skopeo login as fallback
    if echo "$PASSWORD" | skopeo login --username "$USERNAME" --password-stdin "$QUAY_URL" 2>/dev/null; then
        print_info "Successfully logged in with skopeo"
        return 0
    fi
    
    print_error "Failed to login to registry"
    return 1
}

# Function to get repository tags
get_repository_tags() {
    local tags_json
    if tags_json=$(skopeo list-tags "docker://$FULL_REPO" 2>/dev/null); then
        local all_tags=$(echo "$tags_json" | jq -r '.Tags[]?' 2>/dev/null)
        
        if [[ -n "$all_tags" ]]; then
            # Filter out signature files (they end with .sig)
            local filtered_tags=""
            while IFS= read -r tag; do
                if [[ -n "$tag" && ! "$tag" =~ \.sig$ ]]; then
                    if [[ -n "$filtered_tags" ]]; then
                        filtered_tags="$filtered_tags"$'\n'"$tag"
                    else
                        filtered_tags="$tag"
                    fi
                fi
            done <<< "$all_tags"
            
            if [[ -n "$filtered_tags" ]]; then
                echo "$filtered_tags"
                return 0
            else
                print_error "No valid image tags found (only signature files present)"
                return 1
            fi
        else
            print_error "No tags found in repository or unable to parse tags"
            return 1
        fi
    else
        print_error "Failed to fetch repository tags"
        return 1
    fi
}

# Function to check if image has signatures
check_image_signatures() {
    local tag="$1"
    local source_image="docker://$FULL_REPO:$tag"
    
    print_info "Checking signatures for tag: $tag"
    
    # Use skopeo inspect to check for signatures
    local inspect_output
    if inspect_output=$(skopeo inspect --raw "$source_image" 2>/dev/null); then
        # Check if the image manifest contains signature references
        if echo "$inspect_output" | jq -e '.signatures // empty' >/dev/null 2>&1; then
            print_info "Tag $tag has signatures"
            return 0  # Has signatures
        else
            print_info "Tag $tag has no signatures"
            return 1  # No signatures
        fi
    else
        print_warning "Failed to inspect tag $tag, assuming no signatures"
        return 1  # Cannot determine, assume no signatures
    fi
}

# Function to remove signature files
remove_signature_files() {
    if [[ -n "$SIG_FILES" ]]; then
        print_info "Removing signature files..."
        local sig_success=0
        local sig_failed=0
        
        while IFS= read -r sig_file; do
            if [[ -n "$sig_file" ]]; then
                print_info "Removing signature file: $sig_file"
                if skopeo delete "docker://$FULL_REPO:$sig_file" 2>/dev/null; then
                    print_info "✓ Successfully removed signature file: $sig_file"
                    sig_success=$((sig_success + 1))
                else
                    print_warning "✗ Failed to remove signature file: $sig_file"
                    sig_failed=$((sig_failed + 1))
                fi
            fi
        done <<< "$SIG_FILES"
        
        print_info "Signature files - Success: $sig_success, Failed: $sig_failed"
    fi
}

# Function to remove signatures from a specific tag
remove_signatures_from_tag() {
    local tag="$1"
    local source_image="docker://$FULL_REPO:$tag"
    
    print_info "Processing image tag: $tag"
    
    # First check if the image actually has signatures
    if ! check_image_signatures "$tag"; then
        print_info "ℹ️  Tag $tag has no signatures to remove"
        return 2  # Special return code for no signatures
    fi
    
    # Use skopeo to copy the image to itself without signatures
    if skopeo copy --remove-signatures "$source_image" "$source_image" 2>/dev/null; then
        print_info "✅ Successfully removed signatures from tag: $tag"
        return 0
    else
        print_warning "❌ Failed to remove signatures from tag: $tag"
        return 1
    fi
}

# Function to cleanup login sessions
cleanup_login() {
    print_info "Cleaning up login sessions..."
    podman logout "$QUAY_URL" 2>/dev/null || true
    skopeo logout "$QUAY_URL" 2>/dev/null || true
}

# Set trap to cleanup on exit
trap cleanup_login EXIT

# Main execution
print_info "=== Quay Signature Removal Tool (Podman/Skopeo) ==="
print_info "Repository: $FULL_REPO"
echo

# Login to registry
if ! login_to_registry; then
    print_error "Cannot proceed without successful authentication"
    exit 1
fi

# Get repository tags
print_info "Fetching repository tags..."
if ! TAGS=$(get_repository_tags); then
    exit 1
fi

# Count tags and show them properly
TAG_COUNT=$(echo "$TAGS" | wc -l)
TAG_LIST=$(echo "$TAGS" | tr '\n' ' ' | sed 's/ $//')
print_info "Found $TAG_COUNT valid image tag(s): $TAG_LIST"

# Show signature files if any were found
print_info "Checking for signature files..."
ALL_TAGS_JSON=$(skopeo list-tags "docker://$FULL_REPO" 2>/dev/null)
SIG_FILES=$(echo "$ALL_TAGS_JSON" | jq -r '.Tags[]?' 2>/dev/null | grep '\.sig$' || true)

if [[ -n "$SIG_FILES" ]]; then
    SIG_COUNT=$(echo "$SIG_FILES" | wc -l)
    print_warning "Found $SIG_COUNT signature file(s) that will be removed:"
    while IFS= read -r sig_file; do
        if [[ -n "$sig_file" ]]; then
            print_warning "  - $sig_file"
        fi
    done <<< "$SIG_FILES"
else
    print_info "No signature files found"
fi

# Show what will be processed
echo
if [[ -n "$SIG_FILES" ]]; then
    print_info "Will remove signatures from $TAG_COUNT image tag(s) and $SIG_COUNT signature file(s)."
else
    print_info "Will remove signatures from $TAG_COUNT image tag(s)."
fi

# Process signature files first
echo
print_info "Starting signature removal process..."
remove_signature_files

# Process each image tag
echo
print_info "Processing image tags..."
print_info "Tags to process: $TAGS"
print_info "Processing each tag individually..."

successful_removals=0
failed_removals=0
no_signatures=0

while IFS= read -r tag; do
    if [[ -n "$tag" ]]; then
        print_info "Found tag to process: '$tag'"
        remove_signatures_from_tag "$tag"
        exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            successful_removals=$((successful_removals + 1))
        elif [[ $exit_code -eq 2 ]]; then
            no_signatures=$((no_signatures + 1))
        else
            failed_removals=$((failed_removals + 1))
        fi
    else
        print_warning "Empty tag found, skipping"
    fi
done <<< "$TAGS"

print_info "Finished processing all tags"

# Summary
echo
print_info "=== SUMMARY ==="
print_info "Image tags processed: $TAG_COUNT"
print_info "Tags with signatures removed: $successful_removals"
print_info "Tags with no signatures: $no_signatures"
print_info "Failed removals: $failed_removals"

if [[ -n "$SIG_FILES" ]]; then
    print_info "Signature files were also processed (see output above)"
fi

if [[ $failed_removals -eq 0 ]]; then
    if [[ $successful_removals -gt 0 ]]; then
        print_info "🎉 All signatures successfully processed in repository $NAMESPACE/$REPOSITORY"
    else
        print_info "ℹ️  Repository $NAMESPACE/$REPOSITORY had no signatures to remove"
    fi
else
    print_warning "⚠️  Some signature removals failed. Check the output above for details."
fi

print_info "Script completed!"
