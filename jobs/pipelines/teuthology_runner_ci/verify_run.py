#!/usr/bin/env python3
"""
Verify that a teuthology run exists on the server and has jobs.
Exits 0 on success, 1 on failure.
"""
import argparse
import os
import sys


def main():
    parser = argparse.ArgumentParser(description="Verify teuthology run exists with jobs")
    parser.add_argument(
        "run_name",
        nargs="?",
        default=os.environ.get("RUN_NAME", ""),
        help="Run name (or set RUN_NAME env)",
    )
    args = parser.parse_args()
    run_name = args.run_name

    if not run_name:
        print("Error: run_name required (argument or RUN_NAME env)")
        sys.exit(1)

    try:
        from teuthology.report import ResultsReporter

        reporter = ResultsReporter()
        jobs = reporter.get_jobs(run_name, fields=["job_id"])
        if jobs is not None and len(jobs) > 0:
            print("Run found with {} jobs".format(len(jobs)))
            sys.exit(0)
        else:
            print("Run found but has no jobs")
            sys.exit(1)
    except Exception as e:
        error_msg = str(e)
        if "404" in error_msg or "Not Found" in error_msg:
            print("404 Not Found: {}".format(error_msg))
            sys.exit(1)
        else:
            print("Error checking run: {}".format(error_msg))
            sys.exit(1)


if __name__ == "__main__":
    main()
