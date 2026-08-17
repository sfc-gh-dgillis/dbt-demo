-- Log entries emitted by the most recent run of the dbt project object.
--
-- Run with `task dbt-project-logs`. Requires LOG_LEVEL on the schema holding the
-- project object; see the telemetry block in sql/bootstrap/001-create_util_database.sql.
--
-- Templated by `snow sql -f ... -D`, so <% NAME %> placeholders are substituted
-- client-side before the statement is sent.
--
-- The run is identified rather than typed in: DBT_PROJECT_EXECUTION_HISTORY gives
-- the query_id of the latest execution, and every event carries the query id that
-- produced it in RESOURCE_ATTRIBUTES. Ordering is on query_start_time, not
-- query_end_time, because end time is NULL while a run is still in flight and
-- would sort unpredictably.
--
-- UPPER() on the arguments because object names are stored uppercase and the .env
-- values are lowercase.
--
-- CAVEAT on "most recent": DBT_PROJECT_EXECUTION_HISTORY reports runs of this
-- object by ANY user, not just yours -- it returns a user_name column precisely
-- because it is account-wide. On a shared demo account, if a colleague runs the
-- same project object after you, this returns their run rather than yours. Add
-- `AND user_name = CURRENT_USER()` inside the CTE if that matters.
--
-- Attribution itself is exact regardless: query ids are globally unique, so the
-- join below can never mix events from two runs together.
--
-- NOTE: event table writes lag by up to 10 seconds. A query issued the instant a
-- run finishes can come back short; re-run it.

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
  -- Correctness comes from the query_id join above. This predicate exists only
  -- to prune partitions: without it the scan covers the event table's full
  -- retention rather than the window the run occupied.
  AND e.timestamp >= r.query_start_time
ORDER BY e.timestamp ASC
LIMIT <% ROW_LIMIT %>;
