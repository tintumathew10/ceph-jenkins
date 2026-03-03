pipelineJob("sample-ceph-container-pipeline") {
    displayName("Test: Sample Ceph Container Pipeline")
    description("A sample job to verify the Ceph container build creation.")
    
    definition {
        // Checkout the code from the repository
        cpsScm {
            scm {
                git {
                    remote {
                        url("https://github.com/vamahaja/ceph-jenkins.git")
                    }
                    branches("main")
                }
            }
            scriptPath("jobs/pipelines/sample_ceph_container_ci/Jenkinsfile")
        }

        // Add the required parameters for the job
        parameters {
            stringParam("CEPH_BRANCH", "main", "Ceph branch to build")
            stringParam("DISTRO", "centos9 rocky10", "Distribution to build")
            stringParam("ARCH", "x86_64", "Architecture to build")
            choiceParam("FLAVOR", ["default"], "Build flavor")
        }
    }
}
