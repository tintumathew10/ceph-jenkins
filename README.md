# Ceph Jenkins

This repository provides the configuration and deployment logic for a containerized Jenkins controller used in Ceph Storage pipelines.

## Getting Started

### Prerequisites

Before deploying the containerized controller, ensure the following requirements are met:

* **Container Runtime**: Podman or Docker must be installed on the host machine.

* **Configuration Files:** The following files important configuration files -
    * `Containerfile`: To build the custom Jenkins image.
    * `plugins.txt`: Listing required plugins.
    * `casc.yaml`: Defining system-level configurations.
    * `jobs/seed.groovy`: The initial script to bootstrap the job-processing logic.

### Deployment Steps

Deployment follows "Configuration as Code" workflow to maintain the repository as the single source of truth.

1. **Build the Image:** Create the custom controller image using the provided `Containerfile`. This process pre-installs all plugins from `plugins.txt`:
    ```sh
    podman build -t ceph-jenkins-controller:latest .
    ```
2. **Launch the Controller:** Start the container with port mappings for the UI and agent communication. Ensure the persistent volume is mounted:
    ```
    podman run -d \
        --name jenkins-controller \
        -p 8080:8080 -p 50000:50000 \
        -v jenkins_home:/var/jenkins_home \
        ceph-jenkins-controller:latest
    ```
3. **Bootstrap Jobs:** Upon startup, JCasC will automatically execute `seed.groovy` to create the `Seed` job.

4. **Process Project Jobs:** Run the `Seed` from the Jenkins UI, providing the relative path to your project's Groovy definitions to generate project-specific pipelines.

### Logging

The Ceph CI environment utilizes multiple logging layers to ensure visibility across the "controller/builder" architecture.

* **Controller Logs:** Monitor the startup and JCasC initialization via `podman logs -f jenkins-controller`.

* **Builder Logs:** Detailed system logs are often captured during build execution using `journalctl`.