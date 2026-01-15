// Seed job created during the jenkins initialization
freeStyleJob("Seed") {
    description("Seed Job to process DSL scripts")

    parameters {
        // Default path to project directory
        stringParam("DSL_PATH", "jobs/*.groovy", "Relative path to the project DSL script")
    }

    steps {
        dsl {
            // Path to process DSL scripts
            external("${DSL_PATH}")
            
            // Standard persistence settings
            removeAction("IGNORE")
            removeViewAction("IGNORE")
            lookupStrategy("SEED_JOB")
        }
    }
}