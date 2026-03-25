#!/bin/bash

# --- Default Configuration ---
JENKINS_CONFIG_DIR="$HOME/jenkins_config"
JENKINS_PROPERTIES="$JENKINS_CONFIG_DIR/properties.yaml"

# --- Volume Configuration ---
SHARED_WORKSPACE_VOLUME="jenkins_shared_workspace"
SHARED_WORKSPACE_PATH="$JENKINS_CONFIG_DIR/shared_workspace"
JENKINS_HOME_VOLUME="jenkins_home"
JENKINS_HOME_PATH="$JENKINS_CONFIG_DIR/jenkins_home"

# --- Create Jenkins Config Directory ---
if [ ! -d "$JENKINS_CONFIG_DIR" ]; then
    echo "Jenkins config directory does not exist."
    exit 1
fi

# --- Check if Jenkins Properties File Exists ---
if [ ! -f "$JENKINS_PROPERTIES" ]; then
    echo "Jenkins properties file does not exist."
    exit 1
fi

# --- Podman Configuration ---
SOCKET_PATH="/run/user/$(id -u)/podman/podman.sock"
SOCKET_GID=$(stat -c '%g' $SOCKET_PATH)
HOST_UID=$(id -u)
JENKINS_URL="http://localhost:8080"

echo "--- Initializing Deployment for Ceph-Jenkins ---"
echo "Detected Socket GID: $SOCKET_GID"
echo "Detected Host UID: $HOST_UID"

# --- Build Images ---
echo "Building Jenkins Controller..."
podman build --pull=always -t ceph-jenkins-controller ./containers/controller

echo "Building Seed Agent (with dynamic permissions)..."
podman build \
    --build-arg USER_ID=$HOST_UID \
    --build-arg GROUP_ID=$SOCKET_GID \
    -t ceph-jenkins-seed-agent ./containers/agents/seed

echo "Building Fedora 39 Build Agent (with dynamic permissions)..."
podman build \
    --build-arg USER_ID=$HOST_UID \
    --build-arg GROUP_ID=$SOCKET_GID \
    -t ceph-jenkins-fedora39-agent ./containers/agents/build/fedora/39

echo "Building CentOS 9 Build Agent (with dynamic permissions)..."
podman build \
    --build-arg USER_ID=$HOST_UID \
    --build-arg GROUP_ID=$SOCKET_GID \
    -t ceph-jenkins-centos9-agent ./containers/agents/build/centos/9.stream

echo "Building Rocky 10 Build Agent (with dynamic permissions)..."
podman build \
    --build-arg USER_ID=$HOST_UID \
    --build-arg GROUP_ID=$SOCKET_GID \
    -t ceph-jenkins-rocky10-agent ./containers/agents/build/rocky-10

echo "Building Ubuntu Noble Build Agent (with dynamic permissions)..."
podman build \
    --build-arg USER_ID=$HOST_UID \
    --build-arg GROUP_ID=$SOCKET_GID \
    -t ceph-jenkins-ubuntu-noble-agent ./containers/agents/build/ubuntu/noble

echo "Building Ubuntu Jammy Build Agent (with dynamic permissions)..."
podman build \
    --build-arg USER_ID=$HOST_UID \
    --build-arg GROUP_ID=$SOCKET_GID \
    -t ceph-jenkins-ubuntu-jammy-agent ./containers/agents/build/ubuntu/jammy

echo "Building Buildah Build Agent (with dynamic permissions)..."
podman build \
    --build-arg USER_ID=$HOST_UID \
    --build-arg GROUP_ID=$SOCKET_GID \
    -t ceph-jenkins-buildah-agent ./containers/agents/build/buildah

# --- Cleanup Existing Container ---
if [ "$(podman ps -aq -f name=jenkins-controller)" ]; then
    echo "Stopping and removing existing jenkins-controller..."
    podman stop jenkins-controller
    podman rm jenkins-controller
    podman volume rm jenkins_home
fi

# --- Verify Built Images ---
echo "Verifying built images..."
REQUIRED_IMAGES=(
    "ceph-jenkins-controller:latest"
    "ceph-jenkins-seed-agent:latest"
    "ceph-jenkins-fedora39-agent:latest"
    "ceph-jenkins-centos9-agent:latest"
    "ceph-jenkins-rocky10-agent:latest"
    "ceph-jenkins-ubuntu-noble-agent:latest"
    "ceph-jenkins-ubuntu-jammy-agent:latest"
    "ceph-jenkins-buildah-agent:latest"
)
MISSING=()

for img in "${REQUIRED_IMAGES[@]}"; do
        if ! podman image exists "$img"; then
            echo " [MISSING] $img"
            MISSING+=("$img")
        else
            echo " [OK] $img"
        fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
        echo "One or more required images are missing. Build may have failed."
        echo "Missing images: ${MISSING[*]}"
        echo "Inspect build output above for errors."
        exit 1
fi

# --- Create Jenkins Home Volume ---
if podman volume exists jenkins_home 2>/dev/null; then
    echo "Jenkins home volume already exists."
else
    echo "Creating jenkins home directory..."
    mkdir -p "$JENKINS_HOME_PATH"

    echo "Creating jenkins home volume..."
    podman volume create jenkins_home \
        --opt type=dir \
        --opt device=$JENKINS_HOME_PATH \
        --opt o=bind
fi

# --- Create Shared Workspace Volume ---
if podman volume exists jenkins_shared_workspace 2>/dev/null; then
    echo "Shared workspace volume already exists."
else
    echo "Creating shared workspace directory..."
    mkdir -p "$SHARED_WORKSPACE_PATH"

    echo "Creating shared workspace volume..."
    podman volume create jenkins_shared_workspace \
        --opt type=dir \
        --opt device=$SHARED_WORKSPACE_PATH \
        --opt o=bind
fi

# --- Deploy Jenkins Server ---
echo "Launching Jenkins Controller..."
podman run -d \
    --name jenkins-controller \
    --cpus 4 \
    --memory 12g \
    --memory-reservation 4g \
    --oom-score-adj -500 \
    -p 8080:8080 -p 50000:50000 \
    -e JAVA_OPTS="-Xms4g -Xmx8g \
       -XX:+UseG1GC \
       -XX:+ExplicitGCInvokesConcurrent \
       -Djenkins.install.runSetupWizard=false \
       -Djava.awt.headless=true \
       -Dcasc.jenkins.config=/var/jenkins_home/casc_configs/" \
    -v $JENKINS_HOME_VOLUME:/var/jenkins_home \
    -v $(pwd)/casc.yaml:/var/jenkins_home/casc_configs/01-casc.yaml:z \
    -v $JENKINS_CONFIG_DIR/properties.yaml:/var/jenkins_home/casc_configs/02-properties.yaml:z \
    -v $(pwd)/jobs/seed.groovy:/var/jenkins_home/seed.groovy:z \
    -v $SOCKET_PATH:/var/run/podman.sock:z \
    --group-add $SOCKET_GID \
    --userns=keep-id \
    ceph-jenkins-controller:latest

# --- Health Check Step ---
echo "--- Post-Deployment Validation ---"

# A. Check if Container is actually Running
echo -n "Checking container status..."
if [ "$(podman inspect -f '{{.State.Running}}' jenkins-controller)" == "true" ]; then
    echo " [OK] Container is running."
else
    echo " [FAILED] Container failed to start."
    echo " Check 'podman logs jenkins-controller'."
    exit 1
fi

# Check if Jenkins Server is Up
echo "Waiting for Jenkins to be ready at $JENKINS_URL ..."
MAX_RETRIES=30
WAIT_INTERVAL=5
COUNT=0
SUCCESS=false

while [ $COUNT -lt $MAX_RETRIES ]; do
    # Check for a 200 (Success) or 
    # 403 (Forbidden, indicating Jenkins is up but needs login)
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $JENKINS_URL/login || echo "000")
    
    if [ "$HTTP_STATUS" == "200" ] || [ "$HTTP_STATUS" == "403" ]; then
        echo " [OK] Jenkins is up and responding (Status: $HTTP_STATUS)."
        SUCCESS=true
        break
    fi
    
    echo -n "."
    sleep $WAIT_INTERVAL
    ((COUNT++))
done

if [ "$SUCCESS" = false ]; then
    echo " [TIMEOUT] Jenkins did not start within 150 seconds."
    echo "Here is the last 60 lines of logs:"
    podman logs jenkins-controller --tail 60
    exit 1
fi

echo "--- Deployment Verified & Success! ---"
echo "Login at $JENKINS_URL"
