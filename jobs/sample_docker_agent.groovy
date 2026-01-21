pipelineJob("sample-docker-pipeline") {
    displayName("Test: Sample Docker Agent Pipeline")
    description("A sample job to verify the Docker agent environment.")
    
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url("https://github.com/vamahaja/ceph-jenkins.git")
                    }
                    branches("main")
                }
            }
            scriptPath("jobs/pipelines/sample_docker_agent/Jenkinsfile")
        }
    }
}
