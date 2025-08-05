#!/bin/bash

# Unset all environment variables related to trusted-artifact-signer and cosign
# To use with curl | bash, run: eval "$(curl -s https://your-github-url/unset_vars.sh)"
unset TUF_URL
unset OIDC_ISSUER_URL
unset COSIGN_FULCIO_URL
unset COSIGN_REKOR_URL
unset COSIGN_MIRROR
unset COSIGN_ROOT
unset COSIGN_OIDC_CLIENT_ID
unset COSIGN_OIDC_ISSUER
unset COSIGN_CERTIFICATE_OIDC_ISSUER
unset COSIGN_YES
unset SIGSTORE_FULCIO_URL
unset SIGSTORE_OIDC_ISSUER
unset SIGSTORE_REKOR_URL
unset REKOR_REKOR_SERVER

echo "All environment variables have been unset."