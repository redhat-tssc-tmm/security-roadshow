## cosign_gitsign_installer.sh

The script installs matching `cosign` and `gitsign` versions from the Red Hat Trusted Artifact Signer (RHTAS) operator-installed client-server.

```
curl -fsSL https://raw.githubusercontent.com/redhat-tssc-tmm/security-roadshow/main/cosign_gitsign_installer.sh | bash
```

### Side note
To verify this code hasn't been tampered with - my commits have been signed using the public-good instance of sigstore (the upstream for RHTAS)

1) Initialize your trust root by issuing 
`cosign initialize`
which will download the trust root and store it under `~/.sigstore`

2) Use `git verify-commit <commit hash>` :

```
git verify-commit 68bf6359be8a4b7a9a9c3073dbaf9c8fd6e0bd62
tlog index: 229774027
gitsign: Signature made using certificate ID 0x6f28e2011cb87de5396caa6e143aa441606fb0b9 | CN=sigstore-intermediate,O=sigstore.dev
gitsign: Good signature from [mnagel@redhat.com](https://github.com/login/oauth)
Validated Git signature: true
Validated Rekor entry: true
Validated Certificate claims: false
WARNING: git verify-commit does not verify cert claims. Prefer using `gitsign verify` instead.
```

This verifies the signature validity but doesn't verify certificate claims 

3) Use `gitsign verify` for verification including claims

```
gitsign verify 68bf6359be8a4b7a9a9c3073dbaf9c8fd6e0bd62 --certificate-identity mnagel@redhat.com --certificate-oidc-issuer https://github\.com/login/oauth
tlog index: 229774027
gitsign: Signature made using certificate ID 0x6f28e2011cb87de5396caa6e143aa441606fb0b9 | CN=sigstore-intermediate,O=sigstore.dev
gitsign: Good signature from [mnagel@redhat.com](https://github.com/login/oauth)
Validated Git signature: true
Validated Rekor entry: true
Validated Certificate claims: true
``` 

4) If you're interested, you can find all details in the Rekor Transparency Log

by log index (see above, `tlog index: 229774027`)

```
curl "https://rekor.sigstore.dev/api/v1/log/entries?logIndex=<entry-index>" | jq
```

or via the Rekor Search UI: https://search.sigstore.dev/?commitSha=68bf6359be8a4b7a9a9c3073dbaf9c8fd6e0bd62 

