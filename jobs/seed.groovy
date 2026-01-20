// Seed job created during the jenkins initialization
job('seed-job') {
    displayName('Seed Job')
    description('Dynamic seed job for Ceph Jenkins pipelines')

    // Build retention policy
    logRotator {
        numToKeep(10)
    }

    // Label to restrict where the job can run
    // TODO: Update this label to `infra` node
    label('controller')

    // Repo and Branch parameters
    parameters {
        stringParam('REPO_URL', 'https://github.com/vamahaja/ceph-jenkins.git', 'The Git repository containing your DSL scripts')
        stringParam('BRANCH_NAME', 'main', 'The branch to check out and process')
    }

    // Clone user repo
    scm {
        git {
            remote {
                url('${REPO_URL}')
            }
            branch('${BRANCH_NAME}')
        }
    }

    // Process DSL scripts present in the repository
    steps {
        jobDsl {
            // Targets the DSL files from `jobs` directory in the repo
            targets 'jobs/*.groovy'
            
            // Clean up jobs that are no longer present in the DSL scripts
            removedJobAction('DELETE')
            removedViewAction('DELETE')
            lookupStrategy('SEED_JOB')
        }
    }
}