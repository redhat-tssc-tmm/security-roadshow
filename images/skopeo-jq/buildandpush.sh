#!/bin/bash

# Set variables
IMAGE_NAME="skopeo-jq"
IMAGE_TAG="latest"
QUAY_ORG="tssc_demos"
FULL_IMAGE_NAME="quay.io/${QUAY_ORG}/${IMAGE_NAME}:${IMAGE_TAG}"

# Build the image
echo "Building image: ${FULL_IMAGE_NAME}"
podman build -t ${FULL_IMAGE_NAME} -f Containerfile .

# Verify the build
echo "Verifying the built image..."
podman run --rm ${FULL_IMAGE_NAME} jq --version
podman run --rm ${FULL_IMAGE_NAME} skopeo --version

# Login to Quay (you'll be prompted for credentials)
echo "Logging into Quay.io..."
podman login quay.io

# Push the image
echo "Pushing image to Quay.io..."
podman push ${FULL_IMAGE_NAME}

# Optional: Tag and push a version with date
DATE_TAG=$(date +%Y%m%d)
DATED_IMAGE_NAME="quay.io/${QUAY_ORG}/${IMAGE_NAME}:${DATE_TAG}"
echo "Creating dated tag: ${DATED_IMAGE_NAME}"
podman tag ${FULL_IMAGE_NAME} ${DATED_IMAGE_NAME}
podman push ${DATED_IMAGE_NAME}

echo "Image successfully built and pushed!"
echo "Available at: ${FULL_IMAGE_NAME}"
echo "Dated version: ${DATED_IMAGE_NAME}"