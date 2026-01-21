#!/usr/bin/env bash
#
# Shell script conversion of runSmokeForBranch() from Jenkinsfile (lines 97-413).
# Usage: ./run_smoke_for_branch.sh [branch]
#   branch defaults to "main" if not provided.
# Environment (from Jenkins parameters):
#   PLATFORM   - Comma-separated platform list (e.g. ubuntu-jammy-default,centos-9-default)
#   ARCH       - Architecture (e.g. x86_64)
#   CLOUD_TYPE - Cloud/machine type for teuthology-suite (e.g. openstack)
#

set -euo pipefail

# --- Helpers ---
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# --- Run smoke for a single branch ---
run_smoke_for_branch() {
    local branch="${1:?branch required}"
    local shaman_id
    local suite="smoke"
    local seed=8446
    local run_name=""
    local suite_output=""
    local tmp_err="${WORKSPACE}/tmp_err_${branch}_$$.txt"
    local suite_output_file="${WORKSPACE}/suite_output_${branch}_$$.txt"
    local exitcode_file="${suite_output_file}.exitcode"

    log "Starting smoke suite for branch: $branch"

    # Get shaman_id for the branch (single call; capture stdout and stderr)
    # PLATFORM, ARCH, CLOUD_TYPE come from Jenkins parameters (defaults below)
    local platform="${PLATFORM:-ubuntu-jammy-default,centos-9-default}"
    local arch="${ARCH:-x86_64}"
    local cloud_type="${CLOUD_TYPE:-openstack}"
    local tmp_out="${WORKSPACE}/tmp_out_${branch}_$$.txt"
    if ! "${VIRTUALENV_PATH}/bin/python3" getUpstreamBuildDetails.py \
        --branch "$branch" \
        --platform "$platform" \
        --arch "$arch" > "$tmp_out" 2>"$tmp_err"; then
        log "ERROR: Failed to get upstream build details for branch $branch:"
        cat "$tmp_err" >> "$LOG_FILE"
        rm -f "$tmp_err" "$tmp_out"
        return 1
    fi
    shaman_id=$(cat "$tmp_out" | xargs)
    rm -f "$tmp_err" "$tmp_out"

    if [[ -z "${shaman_id:-}" ]]; then
        log "ERROR: Failed to get upstream build details for branch $branch"
        return 1
    fi
    log "Using shaman build id for branch $branch: $shaman_id"

    # Upload shaman_id to remote server
    local date_str
    date_str=$(date '+%Y-%m-%d')
    if ! sshpass -p "admin" ssh -o StrictHostKeyChecking=no cloud-user@10.0.196.233 \
        "sudo mkdir -p /data/scheduler/cron && echo '${shaman_id}' | sudo tee /data/scheduler/cron/${branch}-${date_str} > /dev/null" 2>&1 | tee -a "$LOG_FILE"; then
        log "WARNING: Failed to upload shaman_id (continuing anyway)"
    fi

    # Unlock targets before running
    log "Unlocking targets..."
    if ! "${VIRTUALENV_PATH}/bin/teuthology-lock" --list-targets --owner scheduled_ubuntu@teuth-teuthology > ~/locked_targets 2>> "$LOG_FILE"; then
        log "WARNING: Failed to list targets, continuing anyway..."
    fi
    if ! "${VIRTUALENV_PATH}/bin/teuthology-lock" --owner scheduled_ubuntu@teuth-teuthology --unlock -t ~/locked_targets -vvv >> "$LOG_FILE" 2>&1; then
        log "WARNING: Failed to unlock targets, continuing anyway..."
    fi

    log "Starting smoke suite for branch $branch with seed=$seed"
    log "DEBUG: Suite output file path: $suite_output_file"
    mkdir -p "$WORKSPACE"

    # Run teuthology-suite and capture output
    local suite_exit=0
    (
        cd "$SCRIPT_DIR" && \
        ( PYTHONUNBUFFERED=1 "${VIRTUALENV_PATH}/bin/teuthology-suite" \
            --suite "$suite" \
            --machine-type "$cloud_type" \
            --ceph "$branch" \
            --ceph-repo https://github.com/ceph/ceph \
            --priority 50 \
            --force-priority \
            --limit 1 \
            --job-threshold 1 \
            --subset 1/10000 \
            --sha1 "$shaman_id" \
            --owner "test" \
            "${OVERRIDE_YAML}" > "$suite_output_file" 2>&1
          echo $? > "$exitcode_file"
        )
    ) || true
    sync

    if [[ -f "$suite_output_file" ]]; then
        suite_output=$(cat "$suite_output_file")
        cat "$suite_output_file" >> "$LOG_FILE"
    else
        log "WARNING: Suite output file does not exist: $suite_output_file"
        local files_check
        files_check=$(ls -la "${WORKSPACE}"/*.txt 2>&1 | head -5 || true)
        log "DEBUG: Files in workspace: $files_check"
    fi

    local actual_exit_code=0
    if [[ -f "$exitcode_file" ]]; then
        actual_exit_code=$(cat "$exitcode_file")
    fi

    if [[ "$actual_exit_code" -ne 0 ]]; then
        log "ERROR: Failed to schedule smoke suite for branch $branch (exit code: $actual_exit_code)"
        [[ -n "${suite_output:-}" ]] && log "Command output: $suite_output"
        rm -f "$suite_output_file" "$exitcode_file"
        return 1
    fi
    rm -f "$suite_output_file" "$exitcode_file"

    # Extract run name from "Job scheduled with name <run_name>"
    # End at first space, newline, " and", or carriage return (match Jenkinsfile)
    local pattern="Job scheduled with name "
    if [[ -n "${suite_output:-}" && "$suite_output" == *"$pattern"* ]]; then
        local after_pattern="${suite_output#*"$pattern"}"
        run_name=$(echo "$after_pattern" | head -n1 | awk '{print $1}')
        run_name=$(echo "$run_name" | xargs)
    fi

    log "Using run name: ${run_name:-<could not parse>}"

    # Wait for run to be registered
    log "Waiting 10 seconds for run to be registered on server..."
    sleep 10

    # Verify run exists (up to 6 attempts, 5 sec apart)
    log "Verifying run exists on server..."
    local run_exists=false
    local max_attempts=6
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        local verify_output_file="${WORKSPACE}/verify_run_${branch}_$$.txt"
        RUN_NAME="$run_name" "${VIRTUALENV_PATH}/bin/python3" <<'VERIFY_EOF' > "$verify_output_file" 2>&1
from teuthology.report import ResultsReporter
import os
import sys
run_name = os.environ.get('RUN_NAME', '')
try:
    reporter = ResultsReporter()
    jobs = reporter.get_jobs(run_name, fields=['job_id'])
    if jobs is not None and len(jobs) > 0:
        print("Run found with {} jobs".format(len(jobs)))
        sys.exit(0)
    else:
        print("Run found but has no jobs")
        sys.exit(1)
except Exception as e:
    error_msg = str(e)
    if '404' in error_msg or 'Not Found' in error_msg:
        print("404 Not Found: {}".format(error_msg))
        sys.exit(1)
    else:
        print("Error checking run: {}".format(error_msg))
        sys.exit(1)
VERIFY_EOF
        local verify_exit=$?

        if [[ -f "$verify_output_file" ]]; then
            local verify_out
            verify_out=$(cat "$verify_output_file")
            [[ -n "${verify_out// }" ]] && log "Verification attempt $((attempt + 1)): ${verify_out}"
            rm -f "$verify_output_file"
        fi

        if [[ $verify_exit -eq 0 ]]; then
            run_exists=true
            break
        fi

        attempt=$((attempt + 1))
        if [[ $attempt -lt $max_attempts ]]; then
            log "Run not found yet, waiting 5 seconds... (attempt $attempt/$max_attempts)"
            sleep 5
        fi
    done

    if [[ "$run_exists" != "true" ]]; then
        log "ERROR: Could not verify run '$run_name' exists after $max_attempts attempts."
        log "The run may not have been scheduled properly or may have a different name."
        return 1
    fi
    log "Run verified on server: $run_name"

    # Record run name for rerun_failed_smoke.sh (same path used by rerun script)
    local script_dir runs_file
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    runs_file="${script_dir}/logs/smoke-runs-$(date '+%Y-%m-%d')"
    mkdir -p "${script_dir}/logs"
    echo "$run_name" >> "$runs_file"
    log "Appended run name to $runs_file"

    # Wait for suite to complete using teuthology-wait
    log "Waiting for smoke suite (branch: $branch, run: $run_name) to complete using teuthology-wait..."
    local wait_output_file="${WORKSPACE}/teuthology_wait_${branch}_$$.txt"
    local wait_exit=0
    "${VIRTUALENV_PATH}/bin/teuthology-wait" --run "$run_name" > "$wait_output_file" 2>&1 || wait_exit=$?

    local wait_output=""
    if [[ -f "$wait_output_file" ]]; then
        wait_output=$(cat "$wait_output_file")
        echo "teuthology-wait output:"
        echo "$wait_output"
        rm -f "$wait_output_file"
    else
        log "WARNING: teuthology-wait output file not found: $wait_output_file"
    fi

    if [[ $wait_exit -ne 0 ]]; then
        if [[ -n "$wait_output" ]] && { [[ "$wait_output" == *"404"* ]] || [[ "$wait_output" == *"Not Found"* ]]; }; then
            log "ERROR: Run '$run_name' not found on server (404 error)"
            log "This may indicate the run was not properly scheduled or has a different name."
            log "teuthology-wait output: $wait_output"
            return 1
        else
            log "WARNING: Smoke suite for branch $branch completed with failures or errors"
            log "teuthology-wait exit code: $wait_exit"
            [[ -n "$wait_output" ]] && log "teuthology-wait output: $wait_output"
            return 1
        fi
    fi

    log "Smoke suite for branch $branch completed successfully (teuthology-wait confirmed completion)"
    return 0
}

# --- Main: run from SCRIPT_DIR and invoke for given branch ---
main() {
    local branch="${1:-main}"
    log "Log file: $LOG_FILE"
    cd "$SCRIPT_DIR" || exit 1
    if run_smoke_for_branch "$branch"; then
        log "Smoke suite for '$branch' branch completed"
        exit 0
    else
        log "Smoke suite for '$branch' branch had errors"
        exit 1
    fi
}

main "$@"
