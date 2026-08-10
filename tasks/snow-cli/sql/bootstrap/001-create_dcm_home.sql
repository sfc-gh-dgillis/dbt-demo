USE ROLE accountadmin;

-- -----------------------------------------------------------------------
-- Home for the DCM project objects.
--
-- This is the one piece of setup that cannot be declarative. A DCM project may
-- not define its own parent database or schema, so the container it lives in has
-- to exist before `snow dcm create` runs. Keeping it outside the databases the
-- project manages also means `task demo-teardown` can purge every managed object
-- without destroying the project that manages them.
--
-- dcm_projects is a SHARED database that already holds unrelated DCM projects in
-- other schemas. Only the dbt_demo schema belongs to this demo:
--   - ACCOUNTADMIN, not SYSADMIN, because ACCOUNTADMIN owns the database and
--     SYSADMIN has no CREATE SCHEMA on it
--   - the CREATE DATABASE below is a no-op on this account and exists only so
--     the demo still bootstraps on a fresh one
--   - teardown drops the dbt_demo SCHEMA only, never the database
--
-- Everything else that used to live in sql/init is now declared in
-- tasks/snow-cli/dcm/sources/definitions.
-- -----------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS dcm_projects
    COMMENT = 'Home for DCM project objects.';

CREATE SCHEMA IF NOT EXISTS dcm_projects.dbt_demo
    COMMENT = 'DCM projects for the dbt demo: dbt_demo_dev and dbt_demo_prod.';
