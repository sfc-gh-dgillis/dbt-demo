#!/usr/bin/env bash
set -euo pipefail

# Mints a programmatic access token (PAT) and exports it from your shell rc file
# so local dbt runs can authenticate with the `dev-pat-auth` profile target.
#
# Why this exists: a PAT secret is returned exactly once, by the ALTER USER ...
# ADD PROGRAMMATIC ACCESS TOKEN command that creates it. No other SQL command or
# function will ever print it again. So the create and the "write it somewhere
# useful" step cannot be separated -- if the secret is not captured in the same
# breath as the create, it is gone and the only recovery is another new token.
#
# Why remove-then-add rather than rotate: ROTATE also returns a fresh secret, but
# it leaves behind a token object representing the prior secret, and that object
# counts against the hard limit of 15 tokens per user. Re-running this task a few
# times would quietly consume the budget. REMOVE + ADD keeps exactly one token.
#
# The role restriction is load-bearing, not decoration. A PAT pinned to a role
# that is later dropped or revoked stops authenticating, and SHOW USER
# PROGRAMMATIC ACCESS TOKENS reports its role_restriction as "<dropped>". That is
# precisely how the previous dev_dbt_demo_pat died: it was pinned to the old
# pre-DCM `dbt_demo_data_engineer`, which the environment-prefixing rename
# dropped. Hence the preflight check below.
#
# Secret hygiene, all deliberate:
#   - the secret only ever lives in a shell variable and an exported env var
#   - it is never passed as a command-line argument, because argv is visible to
#     any other process on the box via `ps`
#   - `set -x` is never enabled
#   - on a parse failure the raw `snow sql` payload is NOT echoed, because that
#     payload is the secret
#
# Caveat: this cannot run over a connection that itself authenticated with a PAT.
# Snowflake forbids removing or rotating a token in such a session. Use the key
# pair connection.
#
# Usage: cmd/create-pat.sh CONNECTION USER TOKEN_NAME ROLE_RESTRICTION DAYS_TO_EXPIRY [RC_FILE]
# Run from tasks/snow-cli (the Taskfile include sets that working directory).

SNOW_CLI_ADMIN_CONNECTION_NAME="${1:-}"
PAT_USER="${2:-}"
PAT_NAME="${3:-}"
PAT_ROLE_RESTRICTION="${4:-}"
PAT_DAYS_TO_EXPIRY="${5:-}"
RC_FILE="${6:-$HOME/.zshrc}"

# The env var name is the contract with profiles.yml and the README's
# dev-pat-auth target, so it is fixed rather than configurable.
ENV_VAR_NAME="DBT_ENV_SECRET_PAT"

for required in SNOW_CLI_ADMIN_CONNECTION_NAME PAT_USER PAT_NAME PAT_ROLE_RESTRICTION PAT_DAYS_TO_EXPIRY; do
    if [ -z "${!required}" ]; then
        echo "Error: $required is required but was empty." >&2
        exit 1
    fi
done

if ! [[ "$PAT_DAYS_TO_EXPIRY" =~ ^[0-9]+$ ]]; then
    echo "Error: PAT_DAYS_TO_EXPIRY must be an integer, got '$PAT_DAYS_TO_EXPIRY'." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Preflight: resolve the restriction role to the exact name Snowflake stores.
#
# Two jobs in one query. First, the role must already be granted to the user:
# Snowflake does not grant it as a side effect of ADD PAT, and a token whose role
# the user does not hold cannot authenticate. Second, ROLE_RESTRICTION takes a
# quoted STRING LITERAL, not an identifier, so it is matched case-sensitively
# against the stored name. Passing 'dev_dbt_demo_data_engineer' for a role stored
# as DEV_DBT_DEMO_DATA_ENGINEER fails with "Role ... does not exist in account",
# which is thoroughly misleading. Echoing back the name SHOW GRANTS reports keeps
# this correct for any casing without blindly upper-casing what the caller passed.
# ---------------------------------------------------------------------------
echo "Resolving role $PAT_ROLE_RESTRICTION for user $PAT_USER..."

RESOLVED_ROLE="$(
    snow sql \
        --connection "$SNOW_CLI_ADMIN_CONNECTION_NAME" \
        --format json \
        --query "SHOW GRANTS TO USER $PAT_USER;" 2>/dev/null |
        python3 -c '
import json, sys

want = sys.argv[1].upper()
try:
    rows = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(1)

# SHOW GRANTS TO USER reports the granted role in both "name" and "role".
for row in rows:
    for key in ("name", "role", "NAME", "ROLE"):
        value = row.get(key)
        if isinstance(value, str) and value.upper() == want:
            sys.stdout.write(value)
            sys.exit(0)
sys.exit(1)
' "$PAT_ROLE_RESTRICTION" || true
)"

if [ -z "$RESOLVED_ROLE" ]; then
    echo "Error: role '$PAT_ROLE_RESTRICTION' is not granted to user '$PAT_USER'." >&2
    echo "       A PAT restricted to a role its user does not hold cannot authenticate." >&2
    echo "       Grant it first, then re-run. For the demo roles this is driven by" >&2
    echo "       admin_users in tasks/snow-cli/dcm/manifest.yml." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Replace any existing token of the same name.
# ---------------------------------------------------------------------------
echo "Removing any existing token $PAT_NAME for $PAT_USER..."

snow sql \
    --connection "$SNOW_CLI_ADMIN_CONNECTION_NAME" \
    --query "ALTER USER IF EXISTS $PAT_USER REMOVE PROGRAMMATIC ACCESS TOKEN IF EXISTS $PAT_NAME;" \
    >/dev/null

# ---------------------------------------------------------------------------
# Create the token and capture the one and only copy of the secret.
# ---------------------------------------------------------------------------
echo "Creating token $PAT_NAME (role $RESOLVED_ROLE, ${PAT_DAYS_TO_EXPIRY}d)..."

# Not piped: the JSON body is the secret, so it goes straight into a variable and
# nowhere near a log.
PAT_PAYLOAD="$(
    snow sql \
        --connection "$SNOW_CLI_ADMIN_CONNECTION_NAME" \
        --format json \
        --query "ALTER USER IF EXISTS $PAT_USER ADD PROGRAMMATIC ACCESS TOKEN $PAT_NAME
                     ROLE_RESTRICTION = '$RESOLVED_ROLE'
                     DAYS_TO_EXPIRY = $PAT_DAYS_TO_EXPIRY
                     COMMENT = 'Local dbt PAT auth. Regenerate with: task pat-create';"
)"

PAT_SECRET="$(
    printf '%s' "$PAT_PAYLOAD" | python3 -c '
import json, sys

try:
    rows = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(1)

if not rows:
    sys.exit(1)

# Documented output columns are token_name and token_secret, uppercased by
# `snow sql --format json`.
secret = rows[0].get("TOKEN_SECRET") or rows[0].get("token_secret")
if not secret:
    sys.exit(1)

sys.stdout.write(secret)
' || true
)"

# Never echo PAT_PAYLOAD here. If parsing failed it still holds the secret.
unset PAT_PAYLOAD

if [ -z "$PAT_SECRET" ]; then
    echo "Error: could not read token_secret from the ADD PROGRAMMATIC ACCESS TOKEN response." >&2
    echo "       The token may now exist without its secret having been captured." >&2
    echo "       Re-run this task to replace it with a fresh one." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Upsert `export DBT_ENV_SECRET_PAT="..."` into the shell rc file.
# ---------------------------------------------------------------------------
echo "Writing $ENV_VAR_NAME to $RC_FILE..."

# The secret travels in the environment, never in argv.
PAT_SECRET="$PAT_SECRET" \
RC_FILE="$RC_FILE" \
ENV_VAR_NAME="$ENV_VAR_NAME" \
python3 <<'PY'
import os
import re
import shutil
import stat
import sys

secret = os.environ["PAT_SECRET"]
rc_path = os.path.expanduser(os.environ["RC_FILE"])
var_name = os.environ["ENV_VAR_NAME"]

# Emit the double-quoted form, so escape everything zsh would otherwise expand
# inside double quotes.
escaped = secret
for char in ("\\", '"', "$", "`"):
    escaped = escaped.replace(char, "\\" + char)
new_line = f'export {var_name}="{escaped}"'

original = ""
existed = os.path.exists(rc_path)
if existed:
    with open(rc_path, "r", encoding="utf-8") as handle:
        original = handle.read()

pattern = re.compile(
    rf"^[ \t]*(?:export[ \t]+)?{re.escape(var_name)}[ \t]*=.*$",
    re.MULTILINE,
)
matches = pattern.findall(original)

if matches:
    # Rewrite the first occurrence in place, so the variable keeps its position
    # relative to the rest of the file, and drop any duplicates.
    done = False
    out_lines = []
    for line in original.split("\n"):
        if pattern.fullmatch(line):
            if not done:
                done = True
                out_lines.append(new_line)
            # subsequent duplicates are dropped
        else:
            out_lines.append(line)
    updated = "\n".join(out_lines)
    action = "replaced"
else:
    prefix = original
    if prefix and not prefix.endswith("\n"):
        prefix += "\n"
    updated = (
        prefix
        + "\n# Snowflake programmatic access token for local dbt PAT auth.\n"
        + "# Regenerate with: task pat-create\n"
        + new_line
        + "\n"
    )
    action = "appended"

if not updated.endswith("\n"):
    updated += "\n"

# One rolling backup rather than a timestamped set: each backup holds a live
# secret, and an unbounded pile of them is a liability, not a safety net.
if existed:
    shutil.copy2(rc_path, rc_path + ".bak")

# Write to a sibling temp file then atomically swap, so an interrupted run can
# never leave a truncated rc file.
directory = os.path.dirname(rc_path) or "."
tmp_path = os.path.join(directory, f".{os.path.basename(rc_path)}.pat.tmp")

mode = stat.S_IMODE(os.stat(rc_path).st_mode) if existed else 0o600
with open(tmp_path, "w", encoding="utf-8") as handle:
    handle.write(updated)
os.chmod(tmp_path, mode)
os.replace(tmp_path, rc_path)

# Confirm the write round-trips: exactly one declaration, holding our secret.
with open(rc_path, "r", encoding="utf-8") as handle:
    final = handle.read()

found = pattern.findall(final)
if len(found) != 1:
    sys.stderr.write(
        f"Error: expected exactly 1 {var_name} declaration in {rc_path}, found {len(found)}.\n"
    )
    sys.exit(1)
if new_line not in final:
    sys.stderr.write(f"Error: {var_name} in {rc_path} did not round-trip.\n")
    sys.exit(1)

print(f"  {action} {var_name} ({len(secret)} chars) in {rc_path}")
if existed:
    print(f"  previous contents backed up to {rc_path}.bak")
PY

unset PAT_SECRET

# ---------------------------------------------------------------------------
# Report the token's server-side state. Metadata only, never the secret.
# ---------------------------------------------------------------------------
echo ""
snow sql \
    --connection "$SNOW_CLI_ADMIN_CONNECTION_NAME" \
    --query "SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER $PAT_USER;"

echo ""
echo "Done. Open a new shell or run: source $RC_FILE"
echo "Note: $RC_FILE now holds the token in plain text."
