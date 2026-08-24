#!/usr/bin/env bash
set -euo pipefail

# Runs a dbt command on the deployed project object and tails its log events as
# they land, rather than waiting for the whole run and reading the output at the
# end.
#
# Why a script rather than a Taskfile one-liner: the tail needs a query id, and
# the query id does not exist until the run has been submitted. So submit and
# poll have to happen in the same process, with the id passed between them.
#
# How it works:
#   1. `snow dbt execute --run-async` submits the run and returns immediately,
#      printing the query id rather than blocking until completion.
#   2. That id filters the event table, which is polled on an interval. Each pass
#      prints only rows newer than the newest already printed.
#   3. Polling stops when query history reports the run is no longer RUNNING.
#
# Requires LOG_LEVEL on the schema holding the project object, or the tail has
# nothing to read and will sit empty for the whole run. See the telemetry block in
# sql/bootstrap/001-create_util_database.sql.
#
# TWO LIMITATIONS worth knowing before using this over `task dbt-project-run-marts`:
#
#   - `snow dbt execute` on Snowflake CLI 3.24.1 has no way to pass ENVIRONMENT or
#     ENV_VARS; those exist only on the EXECUTE DBT PROJECT SQL command. This run
#     therefore uses whatever `default_environment` env.yml specifies (currently
#     dbt_pdb). To run any other environment, use the SQL path and read the logs
#     afterwards with `task dbt-project-logs`.
#   - Event table writes lag by up to 10 seconds, so the tail trails the run and
#     the last lines arrive after the run is already reported complete. The script
#     does a final drain pass to catch them.
#
# TWO CONNECTIONS, because the run and the reading of it need different privileges:
#
#   - EXEC_CONNECTION submits the run and polls its status. It authenticates as the
#     sandbox owner with a role-restricted PAT, which is what makes env.yml's
#     CURRENT_USER() resolve to the right sandbox. Its query status is read with
#     query_history_by_user(), which returns only the CALLING user's queries -- so
#     this poll has to happen on the same connection that submitted, not the admin
#     one.
#   - TELEMETRY_CONNECTION reads SNOWFLAKE.TELEMETRY.EVENTS, which requires
#     ACCOUNTADMIN or SNOWFLAKE.EVENTS_VIEWER. That event table is ACCOUNT-WIDE, so
#     granting the sandbox role access to it would expose every other workload's
#     telemetry on the account. An admin connection reads it instead.
#
# Usage: cmd/tail-dbt-project-run.sh EXEC_CONNECTION TELEMETRY_CONNECTION PROJECT_FQN WAREHOUSE DBT_COMMAND [POLL_SECONDS] [MAX_WAIT_SECONDS]
# Run from tasks/snow-cli/dbt-projects (the Taskfile include sets that directory).

EXEC_CONNECTION="${1:-}"
TELEMETRY_CONNECTION="${2:-}"
PROJECT_FQN="${3:-}"
WAREHOUSE="${4:-}"
DBT_COMMAND="${5:-}"
POLL_SECONDS="${6:-5}"
MAX_WAIT_SECONDS="${7:-1800}"

for pair in \
    "EXEC_CONNECTION:$EXEC_CONNECTION" \
    "TELEMETRY_CONNECTION:$TELEMETRY_CONNECTION" \
    "PROJECT_FQN:$PROJECT_FQN" \
    "WAREHOUSE:$WAREHOUSE" \
    "DBT_COMMAND:$DBT_COMMAND"; do
    if [ -z "${pair#*:}" ]; then
        echo "Error: ${pair%%:*} is required." >&2
        echo "Usage: cmd/tail-dbt-project-run.sh EXEC_CONNECTION TELEMETRY_CONNECTION PROJECT_FQN WAREHOUSE DBT_COMMAND [POLL_SECONDS] [MAX_WAIT_SECONDS]" >&2
        exit 1
    fi
done

if [ -z "${DBT_ENV_SECRET_PAT:-}" ]; then
    echo "Error: DBT_ENV_SECRET_PAT is not set, so $EXEC_CONNECTION has no token." >&2
    echo "       Mint one with \`task pat-create\`, then \`source ~/.zshrc\`." >&2
    exit 1
fi

# The execution connection stores no password; the token is supplied here as
# SNOWFLAKE_CONNECTIONS_<CONNECTION>_PASSWORD so it has exactly one home. Note the
# generic SNOWFLAKE_PASSWORD is silently ignored for a named connection. Exported
# rather than passed as an argument, because argv is visible via `ps`.
EXEC_CONNECTION_SUFFIX=$(printf '%s' "$EXEC_CONNECTION" | tr 'a-z-' 'A-Z_')
export "SNOWFLAKE_CONNECTIONS_${EXEC_CONNECTION_SUFFIX}_PASSWORD=$DBT_ENV_SECRET_PAT"


# --------------------------------------------------------------------------
# Submit
# --------------------------------------------------------------------------
# The project name is passed positionally and fully qualified. Do NOT switch this
# to --database/--schema: on CLI 3.24.1 those are connection overrides that never
# reach the session, which is the same defect that breaks `snow dbt list` for any
# project outside the connection's default database.
#
# DBT_COMMAND is deliberately unquoted so that a value like
# "build --select +path:models/marts" splits into the separate arguments that
# `snow dbt execute` expects to forward to dbt.
echo "Submitting: $DBT_COMMAND"

# shellcheck disable=SC2086
SUBMIT_OUTPUT=$(snow dbt execute \
    --run-async \
    --connection "$EXEC_CONNECTION" \
    --warehouse "$WAREHOUSE" \
    "$PROJECT_FQN" \
    $DBT_COMMAND 2>&1) || {
    echo "Error: submission failed." >&2
    echo "$SUBMIT_OUTPUT" >&2
    exit 1
}

# The id is recovered by shape, not by position, because the surrounding prose in
# the CLI's confirmation message is not a stable contract.
QUERY_ID=$(printf '%s' "$SUBMIT_OUTPUT" \
    | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
    | head -1 || true)

if [ -z "$QUERY_ID" ]; then
    echo "Error: could not find a query id in the submission output." >&2
    echo "$SUBMIT_OUTPUT" >&2
    exit 1
fi

echo "Query id: $QUERY_ID"
echo "Tailing events every ${POLL_SECONDS}s. Ctrl-C to stop the tail (the run continues)."
echo

# --------------------------------------------------------------------------
# Tail
# --------------------------------------------------------------------------
# Watermark of the newest event already printed. Advancing it each pass is what
# keeps the output from repeating rows on every poll.
LAST_TS="1970-01-01 00:00:00.000"

fetch_new_events() {
    # Ordered ASC so the run reads chronologically, and so the final row is the
    # newest and can be used as the next watermark.
    #
    # Admin connection: the event table is account-wide and reading it needs
    # ACCOUNTADMIN or EVENTS_VIEWER, which the sandbox role deliberately lacks.
    snow sql \
        --connection "$TELEMETRY_CONNECTION" \
        --format json \
        --query "
            SELECT
                TO_CHAR(timestamp, 'YYYY-MM-DD HH24:MI:SS.FF3') AS ts,
                record:\"severity_text\"::STRING AS severity,
                value::STRING AS message
            FROM SNOWFLAKE.TELEMETRY.EVENTS
            WHERE resource_attributes:\"snow.query.id\"::STRING = '$QUERY_ID'
              AND resource_attributes:\"snow.executable.type\"::STRING = 'DBT_PROJECT'
              AND scope:\"name\"::STRING = 'snow.dbt.logger'
              AND timestamp > '$LAST_TS'::TIMESTAMP_LTZ
            ORDER BY timestamp ASC
            LIMIT 500;" 2>/dev/null || true
}

print_new_events() {
    local json="$1"
    [ -z "$json" ] && return 0

    # python3 rather than jq: jq is not guaranteed present, python3 is, and the
    # repo already leans on it for pyutil.
    printf '%s' "$json" | python3 -c '
import json, sys

try:
    rows = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if not isinstance(rows, list):
    sys.exit(0)

newest = ""
for row in rows:
    ts = row.get("TS") or ""
    severity = row.get("SEVERITY") or ""
    message = row.get("MESSAGE") or ""
    print(f"{ts}  {severity:<5}  {message}")
    if ts > newest:
        newest = ts

# Emitted on stderr so the watermark stays out of the printed log stream on
# stdout, and can be redirected to a file by the caller below.
if newest:
    print(newest, file=sys.stderr)
' 2>"$WATERMARK_FILE"

    # Advance the watermark only if this pass actually returned something.
    if [ -s "$WATERMARK_FILE" ]; then
        LAST_TS=$(cat "$WATERMARK_FILE")
    fi
}

run_state() {
    # Execution connection, not the admin one: query_history_by_user() returns only
    # the CALLING user's queries, so the submitting connection is the only one that
    # can see this run.
    snow sql \
        --connection "$EXEC_CONNECTION" \
        --format json \
        --query "
            SELECT execution_status
            FROM TABLE(information_schema.query_history_by_user())
            WHERE query_id = '$QUERY_ID';" 2>/dev/null \
        | python3 -c '
import json, sys
try:
    rows = json.load(sys.stdin)
    print(rows[0]["EXECUTION_STATUS"] if rows else "UNKNOWN")
except Exception:
    print("UNKNOWN")
' 2>/dev/null || echo "UNKNOWN"
}

WATERMARK_FILE=$(mktemp)
trap 'rm -f "$WATERMARK_FILE"' EXIT

ELAPSED=0
STATUS="RUNNING"

while [ "$ELAPSED" -lt "$MAX_WAIT_SECONDS" ]; do
    print_new_events "$(fetch_new_events)"

    STATUS=$(run_state)
    # UNKNOWN is treated as still-running: query_history_by_user can briefly not
    # show a just-submitted query, and giving up on that would end the tail
    # immediately.
    if [ "$STATUS" != "RUNNING" ] && [ "$STATUS" != "UNKNOWN" ]; then
        break
    fi

    sleep "$POLL_SECONDS"
    ELAPSED=$((ELAPSED + POLL_SECONDS))
done

# Final drain: events lag the run by up to 10 seconds, so the tail is guaranteed
# to be behind at the moment the run is reported finished.
sleep 10
print_new_events "$(fetch_new_events)"

echo
echo "Run finished with status: $STATUS"

if [ "$STATUS" = "RUNNING" ] || [ "$STATUS" = "UNKNOWN" ]; then
    echo "Note: stopped tailing after ${MAX_WAIT_SECONDS}s; the run may still be going." >&2
    exit 0
fi

# A failed dbt run should fail the task, so CI or a shell chain notices.
if [ "$STATUS" != "SUCCESS" ]; then
    echo "Read the failure with: task dbt-project-logs-errors" >&2
    exit 1
fi
