/**
 * Jenkins Job DSL script for daily smoke suite execution
 */ 

// Job configuration placeholder
def jobsConfiguration = []

// Method to generate required job metadata
def generate_jobs(data) {
    def platforms = "ubuntu-jammy-default,centos-9-default"
    def cloudType = "openstack"
    def arch = "x86_64"

    // For creating job configuration for each fg under each platform
    data.jobsConfiguration.add([
        "name": "daily-smoke-${data.branch}",
        "displayName": "Daily Smoke - ${data.branch}",
        "platform": platforms,
        "arch": arch,
        "branch": data.branch,
        "cloudType": cloudType,
        "cronExpr": data.cronExpr   
        ])
}

// Create jobs specific to tentacle branch
generate_jobs(
    jobsConfiguration: jobsConfiguration,
    branch: "tentacle",
    cronExpr: '00 05 * * 1,3'
)

// Create jobs specific main branch
generate_jobs(
    jobsConfiguration: jobsConfiguration,
    branch: "main",
    cronExpr: '00 02 * * *'
)

for (job in jobsConfiguration) {
    pipelineJob(job.name) {
        displayName(job.displayName)
        description('Runs daily smoke suite for Ceph Main branch.')

        definition {
            cpsScm {
                scm {
                    git {
                        remote {
                            url("https://github.com/tintumathew10/ceph-jenkins.git")
                        }
                        branches("cronjob")
                    }
                }
                scriptPath("jobs/pipelines/daily_smoke/Jenkinsfile")
            }
        }

        parameters {
            stringParam('PLATFORM', job.platform,
                'Comma-separated platform list for getUpstreamBuildDetails (e.g. ubuntu-jammy-default,centos-9-default)')
            stringParam('ARCH', job.arch,
                'Architecture for getUpstreamBuildDetails (e.g. x86_64)')
            stringParam('BRANCH', job.branch,
                'Branch for smoke suite (e.g. tentacle or main)')
            stringParam('CLOUD_TYPE', job.cloudType,
                'Cloud type for smoke suite (e.g. openstack)')
        }

        // Add trigger for cron job
        triggers {
            cron(job.cronExpr)
        }
    }
}
