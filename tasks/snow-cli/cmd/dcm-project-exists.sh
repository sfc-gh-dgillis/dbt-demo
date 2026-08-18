#!/usr/bin/env bash
set -euo pipefail

# Exits 0 if the DCM project object for a target exists, 1 if it does not.
#
# Why this exists: `snow dcm drop` takes --if-exists, but `snow dcm purge` does
# not. On Snowflake CLI 3.24.1 a purge against a missing project fails hard:
#
#   002003: SQL compilation error:
#   DCM Project 'UTIL.DCM_PROJECT_ARCHIVE.DBT_DEMO_DEV' does not exist or not
#   authorized.
#
# That makes teardown non-idempotent, because purge runs before drop: the second
# `task demo-teardown-dev` dies on the first step even though there is nothing left
# to tear down. dcm-purge uses this as a Task `status:` check so it SKIPS instead
# of failing when the project is already gone.
#
# It resolves the identifier the same way the DCM commands do, so the check can
# never disagree with the command it guards: an explicit identifier wins, and
# otherwise the target's project_name comes out of manifest.yml. That matters for
# DBT_PDB, where the manifest value is the deliberate dummy `dbt_demo_pdb_unset`
# and the real name is always passed in.
#
# Usage: cmd/dcm-project-exists.sh CONNECTION TARGET [IDENTIFIER] [PROJECT_DIR]
# Run from tasks/snow-cli (the Taskfile include sets that working directory).

CLI_CONNECTION_NAME="${1:-}"
DCM_TARGET="${2:-}"
DCM_IDENTIFIER="${3:-}"
DCM_PROJECT_DIR="${4:-dcm}"

for required in CLI_CONNECTION_NAME DCM_TARGET; do
    if [ -z "${!required}" ]; then
        echo "Error: $required is required but was empty." >&2
        exit 2
    fi
done

MANIFEST="$DCM_PROJECT_DIR/manifest.yml"

if [ -z "$DCM_IDENTIFIER" ]; then
    if [ ! -f "$MANIFEST" ]; then
        echo "Error: $MANIFEST not found, and no identifier was passed." >&2
        exit 2
    fi

    DCM_IDENTIFIER="$(
        DCM_TARGET="$DCM_TARGET" MANIFEST="$MANIFEST" python3 <<'PY'
import os
import sys

import yaml

target = os.environ["DCM_TARGET"]
with open(os.environ["MANIFEST"], encoding="utf-8") as handle:
    manifest = yaml.safe_load(handle)

targets = (manifest or {}).get("targets") or {}
if target not in targets:
    sys.stderr.write(
        f"Error: target '{target}' is not defined in {os.environ['MANIFEST']}.\n"
    )
    sys.exit(2)

name = (targets[target] or {}).get("project_name")
if not name:
    sys.stderr.write(f"Error: target '{target}' has no project_name.\n")
    sys.exit(2)

sys.stdout.write(name)
PY
    )"
fi

# DESCRIBE rather than SHOW ... LIKE: it takes the fully qualified name as-is, so
# there is no pattern quoting to get wrong and no need to split the FQN apart.
# Output is discarded; only the exit status is of interest.
if snow sql \
    --connection "$CLI_CONNECTION_NAME" \
    --query "DESCRIBE DCM PROJECT $DCM_IDENTIFIER;" \
    >/dev/null 2>&1; then
    exit 0
fi

exit 1
