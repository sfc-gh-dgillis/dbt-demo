-- Grants.
--
-- Replaces sql/init/004-grants.sql. The old script opened with
-- `USE ROLE accountadmin` then switched to `USE ROLE securityadmin`; DCM applies
-- grants with the project owner role, so no USE ROLE statements are needed.
--
-- FUTURE grants are essential here and are fully supported by DCM. dbt creates
-- the tables and views in these schemas at run time, so the access roles have to
-- be entitled to objects that do not exist yet. Note that FUTURE grants do not
-- appear in the `snow dcm plan` summary table: grants are modelled as a nested
-- property of the grantee role, so read out/plan/plan_result.json to see them.
--
-- The role-to-role and role-to-user grants that 004 duplicated from
-- 002-init_roles.sql now live once, in roles.sql.

-- -----------------------------------------------------------------------
-- Account Grants
--
-- dbt needs these to run its own tasks. DCM executes account-level grants on
-- deploy but does not track them in project state, so they are applied but will
-- not show as drift and will not be revoked by a purge.
-- -----------------------------------------------------------------------
GRANT EXECUTE TASK ON ACCOUNT TO ROLE {{ env }}_dbt_demo_rw;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE {{ env }}_dbt_demo_rw;

-- -----------------------------------------------------------------------
-- Warehouse Usage Grants
-- -----------------------------------------------------------------------
{% for wh in warehouses %}
GRANT USAGE ON WAREHOUSE {{ env }}_dbt_demo_{{ wh.suffix }}_wh TO ROLE {{ env }}_dbt_demo_rw;
{% endfor %}

-- -----------------------------------------------------------------------
-- Database Usage Grants
-- -----------------------------------------------------------------------
GRANT USAGE ON DATABASE {{ env }}_dbt_demo TO ROLE {{ env }}_dbt_demo_ro;
GRANT USAGE ON DATABASE {{ env }}_dbt_demo TO ROLE {{ env }}_dbt_demo_rw;

-- -----------------------------------------------------------------------
-- Database Task Grants
-- -----------------------------------------------------------------------
GRANT OPERATE ON ALL TASKS IN DATABASE {{ env }}_dbt_demo TO ROLE {{ env }}_dbt_demo_rw;
GRANT OPERATE ON FUTURE TASKS IN DATABASE {{ env }}_dbt_demo TO ROLE {{ env }}_dbt_demo_rw;

-- -----------------------------------------------------------------------
-- Schema Usage Grants
-- -----------------------------------------------------------------------
{% for schema in schemas %}
GRANT USAGE ON SCHEMA {{ env }}_dbt_demo.{{ schema.name }} TO ROLE {{ env }}_dbt_demo_ro;
GRANT USAGE ON SCHEMA {{ env }}_dbt_demo.{{ schema.name }} TO ROLE {{ env }}_dbt_demo_rw;
{% endfor %}

GRANT USAGE ON FUTURE STAGES IN SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;

-- -----------------------------------------------------------------------
-- RAW Schema-Level Read/Write Grants
-- -----------------------------------------------------------------------
GRANT CREATE FILE FORMAT ON SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE TABLE ON SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE VIEW ON SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE STAGE ON SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE PIPE ON SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE STREAM ON SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE EXTERNAL TABLE ON SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;

-- -----------------------------------------------------------------------
-- RAW Schema-Level Read Only Grants
-- -----------------------------------------------------------------------
GRANT SELECT ON FUTURE TABLES IN SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_ro;

-- -----------------------------------------------------------------------
-- CURATED Schema-Level Read/Write Grants
-- -----------------------------------------------------------------------
GRANT CREATE TABLE ON SCHEMA {{ env }}_dbt_demo.curated TO ROLE {{ env }}_dbt_demo_rw;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA {{ env }}_dbt_demo.curated TO ROLE {{ env }}_dbt_demo_rw;

GRANT CREATE VIEW ON SCHEMA {{ env }}_dbt_demo.curated TO ROLE {{ env }}_dbt_demo_rw;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA {{ env }}_dbt_demo.curated TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE TASK ON SCHEMA {{ env }}_dbt_demo.curated TO ROLE {{ env }}_dbt_demo_rw;

-- -----------------------------------------------------------------------
-- CURATED Schema-Level Read Only Grants
-- -----------------------------------------------------------------------
GRANT SELECT ON FUTURE TABLES IN SCHEMA {{ env }}_dbt_demo.curated TO ROLE {{ env }}_dbt_demo_ro;

-- -----------------------------------------------------------------------
-- MODELED Schema-Level Read/Write Grants
-- -----------------------------------------------------------------------
GRANT CREATE TABLE ON SCHEMA {{ env }}_dbt_demo.modeled TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE VIEW ON SCHEMA {{ env }}_dbt_demo.modeled TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE DYNAMIC TABLE ON SCHEMA {{ env }}_dbt_demo.modeled TO ROLE {{ env }}_dbt_demo_rw;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA {{ env }}_dbt_demo.modeled TO ROLE {{ env }}_dbt_demo_rw;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA {{ env }}_dbt_demo.modeled TO ROLE {{ env }}_dbt_demo_rw;

-- -----------------------------------------------------------------------
-- MODELED Schema-Level Read Only Grants
-- -----------------------------------------------------------------------
GRANT SELECT ON FUTURE TABLES IN SCHEMA {{ env }}_dbt_demo.modeled TO ROLE {{ env }}_dbt_demo_ro;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA {{ env }}_dbt_demo.modeled TO ROLE {{ env }}_dbt_demo_ro;

-- -----------------------------------------------------------------------
-- UTILITIES Schema-Level Read/Write Grants
-- -----------------------------------------------------------------------
GRANT CREATE TABLE ON SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE VIEW ON SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE DYNAMIC TABLE ON SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_rw;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_rw;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_rw;
GRANT USAGE ON FUTURE FUNCTIONS IN SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE FUNCTION ON SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_rw;

-- -----------------------------------------------------------------------
-- UTILITIES Schema-Level Read Only Grants
-- -----------------------------------------------------------------------
GRANT SELECT ON FUTURE TABLES IN SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_ro;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_ro;
GRANT USAGE ON FUTURE FUNCTIONS IN SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_ro;
