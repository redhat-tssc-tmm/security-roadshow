#!/bin/bash


# Assign parameters to variables
QUAYUSER="$1"
QUAYPASSWORD="$2"

cd ~/demo-apps

echo "====================================================="
echo "TSSC MODULE CLEANUP SCRIPT"
echo "====================================================="
echo ""
echo "STEP 1 - remove git repo from gitlab"
echo ""
curl -fsSL https://raw.githubusercontent.com/redhat-tssc-tmm/security-roadshow/main/gitlab_cleanup_script.sh | bash -s -- --execute
echo ""
echo "STEP 2 - remove local git repo"
cd 
rm -rf ~/demo-apps
echo ""
echo "STEP 3 - remove signatures from quay repository"
echo ""
curl -fsSL https://raw.githubusercontent.com/redhat-tssc-tmm/security-roadshow/main/podman_signature_removal.sh | bash -s $1 $2
echo ""
echo "====================================================="
echo "END TSSC MODULE CLEANUP SCRIPT"
echo "====================================================="
echo ""
echo ""
echo "=== To cleanup sigstore environment variables, run this command (optional) ==="
echo "eval \"\$(curl -s https://raw.githubusercontent.com/redhat-tssc-tmm/security-roadshow/main/unset_sigstore_env_vars.sh)\""
echo "=================================================="
echo ""
echo ""
curl -s https://raw.githubusercontent.com/redhat-tssc-tmm/security-roadshow/main/banner.txt