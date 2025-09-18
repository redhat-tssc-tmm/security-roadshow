This image is used in the Platform Engineering Roadshow / workshop, copying an image from the internal registry to the deployed Quay instance. 

Since `skopeo` uses the `REGISTRY_AUTH_FILE`, we need to merge two `auths` (one from the serviceAccount and one passed in from a secret)which is easiest with `jq`

The image can be pulled from https://quay.io/repository/tssc_demos/skopeo-jq 
