-- Trace spans from the most recent run of the dbt project object, slowest first.
--
-- Run with `task dbt-project-spans`. This is the payoff for TRACE_LEVEL = 'ALWAYS':
-- spans carry the per-step timings, so this answers "which part of the build was
-- slow", which the logs cannot.
--
-- Ordered by duration rather than chronologically, on the grounds that the reason
-- to open this is usually a slow run. Swap to `ORDER BY e.timestamp ASC` to read
-- the run in sequence instead.
--
-- RECORD_TYPE = 'SPAN' is what separates spans from log rows; both live in the
-- same event table.
--
-- See telemetry-last-run-logs.sql for why the run is identified via
-- DBT_PROJECT_EXECUTION_HISTORY and why the timestamp predicate is present.

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
    e.record:"name"::STRING AS span_name,
    DATEDIFF('millisecond', e.start_timestamp, e.timestamp) AS duration_ms,
    e.start_timestamp,
    e.timestamp AS end_timestamp
FROM SNOWFLAKE.TELEMETRY.EVENTS AS e
INNER JOIN latest_run AS r
    ON e.resource_attributes:"snow.query.id"::STRING = r.query_id
WHERE e.record_type = 'SPAN'
  AND e.resource_attributes:"snow.executable.type"::STRING = 'DBT_PROJECT'
  AND e.timestamp >= r.query_start_time
ORDER BY duration_ms DESC
LIMIT <% ROW_LIMIT %>;
