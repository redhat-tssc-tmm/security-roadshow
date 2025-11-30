## Customised Web Terminal Operator image

This image is used in the RHADS (Red Hat Advanced Developer Suite) L3 technical enablement workshop.

For the RHTPA (Red Hat Trusted Profile Analyzer) `helm`-based installation, `helm` version 3.17+ is required. The default wto image 1.13 only has helm 3.15.

Additionally, for some RHTAS (Red Hat Trusted Artifact Signer) exercises, access to `podman` is helpful.

NOTE: "podman-in-podman" only works in privileged mode or with a custom SCC. For sake of simplicity (and since students are running the terminal as `admin` anyway), the "setup-podman-scc.sh" script that is called from the `.bashrc` on login adds that SCC to the SA running the pod.

The image is available here: `quay.io/tssc_demos/custom-web-terminal:latest`

To try it out, use `wtoctl set image quay.io/tssc_demos/custom-web-terminal:latest`

```
bash-5.1 ~ $ wtoctl set image quay.io/tssc_demos/custom-web-terminal:latest
devworkspace.workspace.devfile.io/terminal-ym2v36 configured
Updated Web Terminal image to quay.io/tssc_demos/custom-web-terminal:latest. Terminal may restart.
bash-5.1 ~ $ 
```