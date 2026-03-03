#!/bin/bash

# Set strict mode
set -euxo pipefail

# Initialize the working container based on the parsed FROM_IMAGE
CEPH_CNTR=$(sudo buildah from ${FROM_IMAGE})

# Execute build steps inside the container
sudo buildah run $CEPH_CNTR -- dnf install -y epel-release dnf-plugins-core

# Enable CodeReady Builder (CRB) for Ceph build dependencies
sudo buildah run $CEPH_CNTR -- dnf config-manager --set-enabled crb

# Fetch repo file from $REPO_URL and add to /etc/yum.repos.d/ceph.repo
sudo buildah run $CEPH_CNTR -- curl -sL "${REPO_URL}" -o /etc/yum.repos.d/ceph.repo

# Install Ceph packages
sudo buildah run $CEPH_CNTR -- dnf install -y ceph ceph-common ceph-osd ceph-mon ceph-mgr

# Set OCI image configurations
sudo buildah config --env CEPH_SHA1="${SHA1}" $CEPH_CNTR
sudo buildah config --label "ceph.version=${VERSION}" $CEPH_CNTR
sudo buildah config --label "maintainer=Ceph CI/CD" $CEPH_CNTR
sudo buildah config --cmd '["/usr/bin/ceph"]' $CEPH_CNTR

# Commit the image locally
IMAGE_TAG="${DISTRO}-${RELEASE}-${ARCH}-${SHA1}"
sudo buildah commit $CEPH_CNTR $IMAGE_TAG

# List the created image
sudo buildah images $IMAGE_TAG

echo "Successfully built ${IMAGE_TAG}"
