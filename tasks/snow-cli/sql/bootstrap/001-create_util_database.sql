USE ROLE accountadmin;

-- -----------------------------------------------------------------------
-- The util database: home for the objects that manage the demo, as opposed
-- to the objects the demo manages.
--
-- This is the one piece of setup that cannot be declarative. A DCM project may
-- not define its own parent database or schema, so the container it lives in has
-- to exist before `snow dcm create` runs. Keeping it outside the databases the
-- project manages also means `task demo-teardown-dev` can purge every managed object
-- without destroying the project that manages them. The DBT PROJECT object sits
-- here for the same reason: it survives a teardown of dev_dbt_demo.
--
-- util is a SHARED database that predates this demo and holds unrelated objects
-- in other schemas. Only the two archive schemas below belong to it:
--   - ACCOUNTADMIN, not SYSADMIN, because ACCOUNTADMIN owns the database and
--     SYSADMIN has no CREATE SCHEMA on it
--   - the CREATE DATABASE below is a no-op on this account and exists only so
--     the demo still bootstraps on a fresh one
--   - teardown drops the dcm_project_archive SCHEMA only, never the database,
--     and never dbt_project_archive
--
-- Everything else that used to live in sql/init is now declared in
-- tasks/snow-cli/dcm/sources/definitions.
-- -----------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS util
    COMMENT = 'Utilities database.';

-- Home for the DCM project objects: dbt_demo_dev and dbt_demo_prod. Referenced
-- by the target project_name values in dcm/manifest.yml.
CREATE SCHEMA IF NOT EXISTS util.dcm_project_archive
    COMMENT = 'DCM projects for the dbt demo: dbt_demo_dev and dbt_demo_prod.';

-- Home for the DBT PROJECT object. Referenced by DBT_PROJECT_DATABASE and
-- DBT_PROJECT_SCHEMA in .env, which the dbt-project-* tasks pass through.
--
-- Deliberately NOT dropped by teardown: the object accumulates a version history
-- across deploys, and there is no reason to lose it just because the databases
-- it builds into were rebuilt.
CREATE SCHEMA IF NOT EXISTS util.dbt_project_archive
    COMMENT = 'DBT PROJECT objects for the dbt demo.';

-- -----------------------------------------------------------------------
-- Telemetry for dbt project runs
--
-- Every EXECUTE DBT PROJECT emits OpenTelemetry logs and trace spans, but only
-- if these three levels are set. Without them the event table stays empty and a
-- failed run leaves nothing behind to read.
--
-- Scoped to this schema and nothing else. The object parameter hierarchy is
-- account -> database -> schema -> object, where each level OVERRIDES the one
-- above rather than adding to it, so a schema-level setting is complete on its
-- own; there is no database-level setting that it needs to supplement. That
-- matters here because util is a SHARED database, and setting the levels on it
-- would start emitting telemetry for unrelated schemas that other teams own.
--
-- These live here, imperatively, because DCM cannot manage the schema that
-- holds its own project object, and this is the schema that holds the DBT
-- PROJECT object. See the note at the top of this file.
--
-- Destination is the account's active event table (SNOWFLAKE.TELEMETRY.EVENTS
-- unless overridden). Confirm with:
--   SHOW PARAMETERS LIKE 'EVENT_TABLE' IN ACCOUNT;
--
-- Volume: TRACE_LEVEL = ALWAYS and METRIC_LEVEL = ALL are the most verbose
-- settings available, which is what makes the demo worth looking at. They are
-- also billed as storage in the event table. Lower TRACE_LEVEL to ON_EVENT if
-- that becomes a concern.
-- -----------------------------------------------------------------------
ALTER SCHEMA util.dbt_project_archive SET LOG_LEVEL = 'INFO';
ALTER SCHEMA util.dbt_project_archive SET TRACE_LEVEL = 'ALWAYS';
ALTER SCHEMA util.dbt_project_archive SET METRIC_LEVEL = 'ALL';

-- -----------------------------------------------------------------------
-- Inherited grants (public preview)
--
-- dcm/sources/definitions/grants.sql expresses all data access with
-- `GRANT INHERITED ... ON ALL <type> IN <container>`, which is only valid syntax
-- while this account-level parameter is ENABLED. Without it the DCM deploy fails
-- with an unhelpful SQL compilation error, so it is enabled here rather than
-- left as a manual prerequisite.
--
-- Account-level and therefore broader than this demo. Remove this statement if
-- you would rather opt in deliberately, and see the note at the top of
-- grants.sql for why inherited grants are used at all.
-- -----------------------------------------------------------------------
ALTER ACCOUNT SET FEATURE_RBAC_INHERITED_GRANTS = 'ENABLED';
