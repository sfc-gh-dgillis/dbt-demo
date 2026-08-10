-- Grants.
--
-- Replaces sql/init/004-grants.sql. The old script opened with
-- `USE ROLE accountadmin` then switched to `USE ROLE securityadmin`; DCM applies
-- grants with the project owner role, so no USE ROLE statements are needed.
--
-- The role-to-role and role-to-user grants that 004 duplicated from
-- 002-init_roles.sql now live once, in roles.sql.
--
-- ---------------------------------------------------------------------------
-- Data access uses INHERITED grants
--
-- dbt creates the tables and views in these schemas at run time, so the access
-- roles must be entitled to objects that do not exist yet. This used to be
-- expressed with FUTURE grants. It is now expressed with inherited grants:
--
--   GRANT INHERITED SELECT ON ALL TABLES IN SCHEMA x TO ROLE r;
--
-- An inherited grant attaches to the CONTAINER rather than to each object, and
-- covers every matching object in it -- existing and future, permanently. That
-- fixes a real gap in the FUTURE-grant version: a FUTURE grant only covers
-- objects created after the grant, so any table that already existed when the
-- project was first deployed (a re-clone, a partially torn down account, a
-- pre-seeded schema) silently received no grant at all.
--
-- Requires FEATURE_RBAC_INHERITED_GRANTS = 'ENABLED' on the account. This is a
-- public preview feature; sql/bootstrap/001-create_dcm_home.sql enables it, and
-- deploys fail with a syntax error if it is off.
--
-- Not everything can be inherited. OWNERSHIP, account-only privileges such as
-- EXECUTE TASK, USAGE on ROLE, and USAGE on WAREHOUSE are all ineligible, so
-- those sections below keep standard grant syntax.
--
-- Caveat worth knowing: the inherited grants documentation states that
-- Information Schema views do not yet account for inherited grants, so an object
-- reachable ONLY through one would not appear in INFORMATION_SCHEMA for that
-- role. That did NOT reproduce when this project was deployed: dev_dbt_demo_ro,
-- which holds nothing on raw but schema USAGE and an inherited SELECT, saw all 9
-- tables and 118 columns in INFORMATION_SCHEMA. Treat the caveat as something to
-- retest rather than a known failure.
--
-- Even if it does bite, the exposure is narrow for dbt. dbt-snowflake 1.9.4 uses
-- INFORMATION_SCHEMA in only three places: get_catalog (dbt docs generate),
-- get_relation_last_modified (metadata-based source freshness, which this project
-- does not configure), and check_schema_exists. Model building is unaffected --
-- relation discovery goes through `show objects` and `describe table`, which are
-- privilege-checked differently. Use SHOW GRANTS or ACCOUNT_USAGE.GRANTS_TO_ROLES
-- to audit inherited grants, since those always reflect them.
-- ---------------------------------------------------------------------------

-- -----------------------------------------------------------------------
-- Account Grants
--
-- Privileges whose only target is the account cannot be inherited, so these stay
-- as standard grants. DCM executes them on deploy but does not track them in
-- project state, so they will not show as drift and survive a purge.
-- -----------------------------------------------------------------------
GRANT EXECUTE TASK ON ACCOUNT TO ROLE {{ env }}_dbt_demo_rw;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE {{ env }}_dbt_demo_rw;

-- -----------------------------------------------------------------------
-- Warehouse Usage Grants
--
-- Warehouses live outside any database or schema, so warehouse USAGE cannot be
-- inherited either.
-- -----------------------------------------------------------------------
{% for wh in warehouses %}
GRANT USAGE ON WAREHOUSE {{ env }}_dbt_demo_{{ wh.suffix }}_wh TO ROLE {{ env }}_dbt_demo_rw;
{% endfor %}

-- -----------------------------------------------------------------------
-- Database and Schema Usage Grants
--
-- USAGE on the container itself is a grant ON the container, not a grant
-- inherited BY objects inside it, so these remain standard grants.
-- -----------------------------------------------------------------------
GRANT USAGE ON DATABASE {{ env }}_dbt_demo TO ROLE {{ env }}_dbt_demo_ro;
GRANT USAGE ON DATABASE {{ env }}_dbt_demo TO ROLE {{ env }}_dbt_demo_rw;

{% for schema in schemas %}
GRANT USAGE ON SCHEMA {{ env }}_dbt_demo.{{ schema.name }} TO ROLE {{ env }}_dbt_demo_ro;
GRANT USAGE ON SCHEMA {{ env }}_dbt_demo.{{ schema.name }} TO ROLE {{ env }}_dbt_demo_rw;
{% endfor %}

-- -----------------------------------------------------------------------
-- Inherited Data Access Grants: Read/Write
--
-- Uniform across every schema, which is exactly the case inherited grants are
-- designed for. One statement per object type per schema, covering current and
-- future objects.
-- -----------------------------------------------------------------------
{% for schema in schemas %}
GRANT INHERITED SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA {{ env }}_dbt_demo.{{ schema.name }} TO ROLE {{ env }}_dbt_demo_rw;
GRANT INHERITED SELECT ON ALL VIEWS IN SCHEMA {{ env }}_dbt_demo.{{ schema.name }} TO ROLE {{ env }}_dbt_demo_rw;
{% endfor %}

GRANT INHERITED USAGE ON ALL STAGES IN SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT INHERITED USAGE ON ALL FUNCTIONS IN SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_rw;

-- Collapses the old pair of `OPERATE ON ALL TASKS` plus
-- `OPERATE ON FUTURE TASKS` into one statement. The ON ALL half was always a
-- no-op on a fresh deploy: it resolved against tasks existing at that moment,
-- of which there were none, and vanished from the changeset.
GRANT INHERITED OPERATE ON ALL TASKS IN DATABASE {{ env }}_dbt_demo TO ROLE {{ env }}_dbt_demo_rw;

-- -----------------------------------------------------------------------
-- Inherited Data Access Grants: Read Only
--
-- Views are deliberately readable only in modeled and utilities, matching the
-- original grants: raw and curated views are implementation detail.
-- -----------------------------------------------------------------------
{% for schema in schemas %}
GRANT INHERITED SELECT ON ALL TABLES IN SCHEMA {{ env }}_dbt_demo.{{ schema.name }} TO ROLE {{ env }}_dbt_demo_ro;
{% endfor %}

GRANT INHERITED SELECT ON ALL VIEWS IN SCHEMA {{ env }}_dbt_demo.modeled TO ROLE {{ env }}_dbt_demo_ro;
GRANT INHERITED SELECT ON ALL VIEWS IN SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_ro;
GRANT INHERITED USAGE ON ALL FUNCTIONS IN SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_ro;

-- -----------------------------------------------------------------------
-- Schema DDL Privileges
--
-- These are grants ON each schema, not inheritable privileges, and they differ
-- per schema by design: only raw ingests files, only curated schedules tasks,
-- only modeled and utilities build dynamic tables, only utilities defines
-- functions. Kept explicit per schema so the differences stay visible.
-- -----------------------------------------------------------------------

-- RAW: the landing zone, so it gets the full ingestion surface.
GRANT CREATE FILE FORMAT ON SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE TABLE ON SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE VIEW ON SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE STAGE ON SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE PIPE ON SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE STREAM ON SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE EXTERNAL TABLE ON SCHEMA {{ env }}_dbt_demo.raw TO ROLE {{ env }}_dbt_demo_rw;

-- CURATED: tables, views, and the scheduled work that maintains them.
GRANT CREATE TABLE ON SCHEMA {{ env }}_dbt_demo.curated TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE VIEW ON SCHEMA {{ env }}_dbt_demo.curated TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE TASK ON SCHEMA {{ env }}_dbt_demo.curated TO ROLE {{ env }}_dbt_demo_rw;

-- MODELED: where the dbt marts land.
GRANT CREATE TABLE ON SCHEMA {{ env }}_dbt_demo.modeled TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE VIEW ON SCHEMA {{ env }}_dbt_demo.modeled TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE DYNAMIC TABLE ON SCHEMA {{ env }}_dbt_demo.modeled TO ROLE {{ env }}_dbt_demo_rw;

-- UTILITIES: shared UDFs, so it is the only schema granted CREATE FUNCTION.
GRANT CREATE TABLE ON SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE VIEW ON SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE DYNAMIC TABLE ON SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_rw;
GRANT CREATE FUNCTION ON SCHEMA {{ env }}_dbt_demo.utilities TO ROLE {{ env }}_dbt_demo_rw;
