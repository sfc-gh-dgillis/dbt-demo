-- Errors and warnings only, from the most recent run of the dbt project object.
--
-- Run with `task dbt-project-logs-errors`. This is the one to reach for when a run
-- fails: identical to telemetry-last-run-logs.sql except for the severity filter,
-- which drops the couple of hundred INFO lines a full build emits.
--
-- See telemetry-last-run-logs.sql for why the run is identified via
-- DBT_PROJECT_EXECUTION_HISTORY and why the timestamp predicate is present.
--
-- Empty output means the run logged nothing at WARN or above. Confirm that is
-- actually success before believing it, because a run that fails before dbt
-- starts, on a bad profiles.yml or an unresolvable environment, may never emit a
-- dbt log line at all:
--
--   SELECT state, error_code, error_message
--   FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.DBT_PROJECT_EXECUTION_HISTORY(
--       DATABASE => 'UTIL', SCHEMA => 'DBT_PROJECT_ARCHIVE',
--       OBJECT_NAME => 'TASTY_BYTES'))
--   ORDER BY query_start_time DESC LIMIT 1;

WITH latest_run AS (
    SELECT
        query_id,
        query_start_time
    FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.DBT_PROJECT_EXECUTION_HISTORY(
        DATABASE => UPPER('<% DBT_PROJECT_DATABASE %>'),
        SCHEMA => UPPER('<% DBT_PROJECT_SCHEMA %>'),
        OBJECT_NAME => UPPER('<% DBT_PROJECT_OBJECT_NAME %>')))
    ORDER BY query_start_time DESC
    LIMIT 1
)

SELECT
    e.timestamp,
    e.record:"severity_text"::STRING AS severity,
    e.value::STRING AS message
FROM SNOWFLAKE.TELEMETRY.EVENTS AS e
INNER JOIN latest_run AS r
    ON e.resource_attributes:"snow.query.id"::STRING = r.query_id
WHERE e.resource_attributes:"snow.executable.type"::STRING = 'DBT_PROJECT'
  AND e.scope:"name"::STRING = 'snow.dbt.logger'
  AND e.record:"severity_text"::STRING IN ('ERROR', 'WARN')
  AND e.timestamp >= r.query_start_time
ORDER BY e.timestamp ASC
LIMIT <% ROW_LIMIT %>;
