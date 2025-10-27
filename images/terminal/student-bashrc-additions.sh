# Student .bashrc additions for OpenShift terminal environment

# Add TAS CLI tools to PATH if directory exists
if [ -d "/home/student/clitools" ]; then
    export PATH="/home/student/clitools:$PATH"
fi

# RHACS Central endpoint
export ROX_ENDPOINT=central.tssc-acs.svc.cluster.local:443

# Enable bash completion
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

# OpenShift CLI completion
if command -v oc >/dev/null 2>&1; then
    source <(oc completion bash)
fi

# Function to display TAS environment variables
show_tas_env() {
    echo "=== Trusted Artifact Signer (TAS) Environment Variables ==="
    echo ""
    echo "TUF Configuration:"
    echo "  TUF_URL: $TUF_URL"
    echo "  COSIGN_MIRROR: $COSIGN_MIRROR"
    echo "  COSIGN_ROOT: $COSIGN_ROOT"
    echo ""
    echo "OIDC Configuration:"
    echo "  OIDC_ISSUER_URL: $OIDC_ISSUER_URL"
    echo "  COSIGN_OIDC_CLIENT_ID: $COSIGN_OIDC_CLIENT_ID"
    echo "  COSIGN_OIDC_ISSUER: $COSIGN_OIDC_ISSUER"
    echo "  COSIGN_CERTIFICATE_OIDC_ISSUER: $COSIGN_CERTIFICATE_OIDC_ISSUER"
    echo "  SIGSTORE_OIDC_ISSUER: $SIGSTORE_OIDC_ISSUER"
    echo ""
    echo "Fulcio Configuration:"
    echo "  COSIGN_FULCIO_URL: $COSIGN_FULCIO_URL"
    echo "  SIGSTORE_FULCIO_URL: $SIGSTORE_FULCIO_URL"
    echo ""
    echo "Rekor Configuration:"
    echo "  COSIGN_REKOR_URL: $COSIGN_REKOR_URL"
    echo "  SIGSTORE_REKOR_URL: $SIGSTORE_REKOR_URL"
    echo "  REKOR_REKOR_SERVER: $REKOR_REKOR_SERVER"
    echo ""
    echo "Other Settings:"
    echo "  COSIGN_YES: $COSIGN_YES"
    echo ""
    echo "TIP: "
    echo "You can set these variables to endpoints from a different TAS installation"
    echo "by calling \"source ~/setup-tas-environment.sh <your namespace>\""
    echo "i.e. \"source ~/setup-tas-environment.sh student-tas\""
    echo ""
    echo "You can reset to the default TAS installation by either"
    echo ""
    echo "-- run \"source ~/setup-tas-environment.sh tssc-tas\" "
    echo "-- type 'exit' and reconnect to the terminal"
    echo "-- nuking the terminal pod using the 'terminal-reset' command"
    echo ""

}

# Useful aliases
alias ll='ls -al'
alias help='show_tas_env'

# Git-aware prompt function
git_branch() {
    local branch
    if branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); then
        if [[ $branch == "HEAD" ]]; then
            branch="detached*"
        fi
        echo " ($branch)"
    fi
}

# Git status indicators
git_status() {
    if git rev-parse --git-dir >/dev/null 2>&1; then
        local status=""
        if ! git diff --quiet 2>/dev/null; then
            status+="*"  # Modified files
        fi
        if ! git diff --cached --quiet 2>/dev/null; then
            status+="+"  # Staged files
        fi
        if [[ -n $(git ls-files --other --exclude-standard 2>/dev/null) ]]; then
            status+="?"  # Untracked files
        fi
        if [[ -n $status ]]; then
            echo " [$status]"
        fi
    fi
}

setup_git() {
    # Check if git command exists
    if ! command -v git &> /dev/null; then
        print_error "git command not found. Please install git first."
        exit 1
    fi


    # Configure gitsign settings with dynamic values
    # Default settings have been configured on container startup. If a user logs out and in again
    # after changing the TAS settings (~/setup-tas-environment.sh) we also need to reset the
    # git config to the current values (in the .bashrc)
    git config --global gitsign.fulcio "$COSIGN_FULCIO_URL"
    git config --global gitsign.issuer "$OIDC_ISSUER_URL"
    git config --global gitsign.rekor "$COSIGN_REKOR_URL"


}

# Set git-aware prompt with colors applied in PS1
export PS1="\[\033[01;32m\]podman-terminal\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\[\033[01;33m\]\$(git_branch)\[\033[00m\]\[\033[01;31m\]\$(git_status)\[\033[00m\]\$ "

echo "Welcome to the Podman on OpenShift Web Terminal."
echo ""
echo -n "The currently installed podman is "
podman --version
echo "To see your currently configured TAS endpoints, type 'help' "
