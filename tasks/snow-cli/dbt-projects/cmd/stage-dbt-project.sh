#!/usr/bin/env bash
set -euo pipefail

# Stages a clean copy of the dbt project for `snow dbt deploy`.
#
# Why this exists: the dbt project lives at the repo root, alongside .venv
# (~9,700 files), .git, .idea, cmd/, tasks/, target/ and logs/. Deploying with
# `--source .` would sweep all of that into the dbt project object, which counts
# against the 20,000-file limit and makes every deploy slow.
#
# Relying on .gitignore is not an option either: it ignores .venv (which we want
# excluded) but also dbt_packages/ (which we need included). An explicit
# whitelist is deterministic in both directions.
#
# Usage: cmd/stage-dbt-project.sh [BUILD_DIR]
# Run from tasks/snow-cli/dbt-projects (the Taskfile include sets that working
# directory), which is why PROJECT_ROOT is three levels up.

BUILD_DIR="${1:-../../../.build/dbt}"
PROJECT_ROOT="../../.."

# Everything the dbt project object needs, and nothing else.
FILES=(
    dbt_project.yml
    profiles.yml
    env.yml
    packages.yml
    package-lock.yml
)

DIRS=(
    models
    macros
    seeds
    data-tests
    dbt_packages
)

# Start from a clean slate so deletions upstream are reflected in the payload.
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

for f in "${FILES[@]}"; do
    if [ -f "$PROJECT_ROOT/$f" ]; then
        cp "$PROJECT_ROOT/$f" "$BUILD_DIR/$f"
    else
        # profiles.yml and env.yml are required by dbt Projects on Snowflake.
        case "$f" in
            dbt_project.yml|profiles.yml)
                echo "Error: required file not found: $f" >&2
                exit 1
                ;;
            *)
                echo "Note: $f not present, skipping."
                ;;
        esac
    fi
done

for d in "${DIRS[@]}"; do
    if [ -d "$PROJECT_ROOT/$d" ]; then
        cp -R "$PROJECT_ROOT/$d" "$BUILD_DIR/$d"
    else
        echo "Note: $d/ not present, skipping."
    fi
done

# Drop caches and OS cruft that add file count without adding value.
find "$BUILD_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
find "$BUILD_DIR" -type f -name '.DS_Store' -delete 2>/dev/null || true

FILE_COUNT=$(find "$BUILD_DIR" -type f | wc -l | tr -d ' ')

echo "Staged dbt project at $BUILD_DIR ($FILE_COUNT files)"

# Fail loudly rather than shipping a virtualenv.
if find "$BUILD_DIR" -type d -name '.venv' -o -type d -name '.git' | grep -q .; then
    echo "Error: staged payload contains .venv or .git" >&2
    exit 1
fi

if [ "$FILE_COUNT" -gt 20000 ]; then
    echo "Error: $FILE_COUNT files exceeds the 20,000-file dbt project limit" >&2
    exit 1
fi
