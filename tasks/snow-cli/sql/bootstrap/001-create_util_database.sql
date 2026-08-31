USE ROLE accountadmin;

CREATE DATABASE IF NOT EXISTS util
    COMMENT = 'Utilities database.';

-- Home for the DCM PROJECT objects.
CREATE SCHEMA IF NOT EXISTS util.dcm_project_archive
    COMMENT = 'DCM projects for the dbt demo: dbt_demo_dev and dbt_demo_prod.';

-- Home for the DBT PROJECT objects.
CREATE SCHEMA IF NOT EXISTS util.dbt_project_archive
    COMMENT = 'DBT PROJECT objects for the dbt demo.';

-- -----------------------------------------------------------------------
-- Telemetry for dbt project runs
-- -----------------------------------------------------------------------
ALTER SCHEMA util.dbt_project_archive SET LOG_LEVEL = 'INFO';
ALTER SCHEMA util.dbt_project_archive SET TRACE_LEVEL = 'ALWAYS';
ALTER SCHEMA util.dbt_project_archive SET METRIC_LEVEL = 'ALL';

-- -----------------------------------------------------------------------
-- Inherited grants
-- -----------------------------------------------------------------------
ALTER ACCOUNT SET FEATURE_RBAC_INHERITED_GRANTS = 'ENABLED';
