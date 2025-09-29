# Student .bashrc additions for OpenShift terminal environment

# Enable bash completion
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

# OpenShift CLI completion
if command -v oc >/dev/null 2>&1; then
    source <(oc completion bash)
fi

# Useful aliases
alias ll='ls -al'

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

# Set git-aware prompt with colors applied in PS1
export PS1="\[\033[01;32m\]student@openshift\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\[\033[01;33m\]\$(git_branch)\[\033[00m\]\[\033[01;31m\]\$(git_status)\[\033[00m\]\$ "