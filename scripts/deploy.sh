#!/bin/bash

# --- Podman Configuration ---
SOCKET_PATH="/run/user/$(id -u)/podman/podman.sock"
SOCKET_GID=$(stat -c '%g' $SOCKET_PATH)
HOST_GROUP=$(id -gn)
HOST_UID=$(id -u)
JENKINS_URL="http://localhost:8080"

echo "--- Initializing Deployment for Ceph-Jenkins ---"
echo "Detected Socket GID: $SOCKET_GID"
echo "Detected Host Group: $HOST_GROUP"

# --- Build Images ---
echo "Building Jenkins Controller..."
podman build -t ceph-jenkins-controller ./containers/controller

echo "Building Seed Agent (with dynamic permissions)..."
podman build \
    --build-arg AGENT_GID=$SOCKET_GID \
    --build-arg AGENT_GROUP=$HOST_GROUP \
    --build-arg AGENT_UID=$HOST_UID \
    -t ceph-jenkins-seed-agent ./containers/agents/seed

echo "Building Build Agent (with dynamic permissions)..."
podman build \
    --build-arg AGENT_GID=$SOCKET_GID \
    --build-arg AGENT_GROUP=$HOST_GROUP \
    --build-arg AGENT_UID=$HOST_UID \
    -t ceph-jenkins-build-agent ./containers/agents/build

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
    "ceph-jenkins-build-agent:latest"
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

# --- Deploy Jenkins Server ---
echo "Launching Jenkins Controller..."
podman run -d \
    --name jenkins-controller \
    -p 8080:8080 -p 50000:50000 \
    -v jenkins_home:/var/jenkins_home \
    -v $(pwd)/casc.yaml:/var/jenkins_home/casc_configs/01-casc.yaml:z \
    -v $(pwd)/properties.yaml:/var/jenkins_home/casc_configs/02-properties.yaml:z \
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