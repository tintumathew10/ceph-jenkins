FROM jenkins/jenkins:lts

# Jenkins configurations
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

# Copy the plugin list
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt

# Install plugins using the plugin manager CLI
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Create the config directory
USER root
RUN mkdir -p /var/jenkins_home/casc_configs && \
    chown -R jenkins:jenkins /var/jenkins_home/casc_configs
USER jenkins

# Copy the BASE template (the one with ${VAR} placeholders)
COPY casc.yaml /var/jenkins_home/casc_configs/01-base-casc.yaml

# Copy the configuration files into the container
COPY jobs/seed.groovy /var/jenkins_home/seed.groovy

# Set jenkins config directory
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc_configs
