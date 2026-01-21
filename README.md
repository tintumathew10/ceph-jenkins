# Ceph Jenkins

This repository provides the configuration and deployment logic for a containerized Jenkins controller used in Ceph Storage pipelines.

## Getting Started

### Prerequisites

Before deploying the containerized controller, ensure the following requirements are met:

* **Container Runtime**: Podman or Docker must be installed on the host machine.

* **Configuration Files and Directories:** The following are important files and directories -
    * `containers`: Contains custom Jenkins controller & agent Containerfile and configs.
    * `containers/controller/plugins.txt`: Lists all required plugins.
    * `casc.yaml`: Defines system-level configurations.
    * `properties.yaml`: Actual environment configurations.
    * `jobs/seed.groovy`: The initial script to bootstrap the job-processing logic.
    * `scripts`: `Bash`/`Python` scripts to perform specific operations.

### Deployment Steps

Deployment follows "Configuration as Code" workflow to maintain the repository as the single source of truth.

1. **Update Properties:** Fill out `properties.yaml` with your real-world Jenkins configs. This "hydrates" the `casc.yaml` template with your actual cluster details and secrets.

2. **Start socket service:** This will enable and start the socket for user.
    ```sh
    systemctl --user enable --now podman.socket
    ```

3. **Verify socket exists:** Verify the socket now exists for user id.
    ```sh
    ls -l /run/user/$(id -u)/podman/podman.sock
    ```

4. **Enable "Linger":** This will keep services running after user logout.
    ```sh
    sudo loginctl enable-linger $(id -u)
    ```

5. **Set Execute Permissions:** Set execute permissions to `scripts/deploy.sh` script.
    ```sh
    chmod +x ./scripts/deploy.sh
    ```

6. **Execute `deploy.sh`:** This script will build controller and agent images and deploys `jenkins-controller` container.
    ```sh
    ./scripts/deploy.sh
    ```

7. **Bootstrap Jobs:** Upon startup, JCasC will automatically execute `seed.groovy` to create the `Seed Job` job.

8. **Process Project Jobs:** Run the `Seed` from the Jenkins UI, providing the relative path to your project's Groovy definitions to generate project-specific pipelines.

### Logging

The Ceph Jenkins environment utilizes multiple logging layers to ensure visibility across the "controller/builder" architecture.

* **Controller Logs:** Monitor the startup and JCasC initialization via `podman logs -f jenkins-controller`.

* **Builder Logs:** Detailed system logs are often captured during build execution using `journalctl`.