/**
 * Jenkins Job DSL script for daily smoke suite execution
 * Converts the cron job to Jenkins pipeline
 * 
 * Original cron:
 * 00 02 * * * /bin/bash -c "source /home/ubuntu/teuthology/virtualenv/bin/activate && 
 *   cd /home/ubuntu/teuthology && nohup /home/ubuntu/teuthology/run-daily-smoke.sh 
 *   /home/ubuntu/override.yaml" >> /home/ubuntu/archive/logs/cron-smoke-$(date +\%Y\%m\%d).log 2>&1 &
 */

pipelineJob('daily_smoke_suite') {
    displayName('Daily Smoke Suite')
    description('Runs daily smoke suite for Ceph branches (tentacle and main). Converts cron job to Jenkins pipeline.')
    
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
            scriptPath("jobs/pipelines/daily_smoke_suite/Jenkinsfile")
        }
    }
    
    // Configure job properties
    properties {
        pipelineTriggers {
            triggers {
                cron {
                    spec('00 02 * * *')  // Daily at 2:00 AM (matches original cron)
                }
            }
        }
    }
}
