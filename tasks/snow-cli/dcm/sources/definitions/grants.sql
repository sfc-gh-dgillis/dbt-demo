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
-- public preview feature; sql/bootstrap/001-create_util_database.sql enables it, and
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
GRANT EXECUTE TASK ON ACCOUNT TO ROLE {{ base }}_rw;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE {{ base }}_rw;

-- -----------------------------------------------------------------------
-- Warehouse Usage Grants
--
-- Warehouses live outside any database or schema, so warehouse USAGE cannot be
-- inherited either.
-- -----------------------------------------------------------------------
{% for wh in warehouses %}
GRANT USAGE ON WAREHOUSE {{ base }}_{{ wh.suffix }}_wh TO ROLE {{ base }}_rw;
{% endfor %}

-- -----------------------------------------------------------------------
-- Database and Schema Usage Grants
--
-- USAGE on the container itself is a grant ON the container, not a grant
-- inherited BY objects inside it, so these remain standard grants.
-- -----------------------------------------------------------------------
GRANT USAGE ON DATABASE {{ base }} TO ROLE {{ base }}_ro;
GRANT USAGE ON DATABASE {{ base }} TO ROLE {{ base }}_rw;

-- CREATE SCHEMA is what makes per-developer isolation work. The `dev_user`
-- environment in env.yml points DBT_CURRENT_SCHEMA at a schema derived from
-- CURRENT_USER(), and dbt issues `create schema if not exists` for it on the
-- first run. Without this privilege that run fails, and the schemas below are
-- the only ones a developer could ever build into.
--
-- Deliberately not declared as DEFINE SCHEMA per developer: that would mean
-- editing manifest.yml and redeploying for every new engineer. Granting the
-- privilege once lets the set of developer schemas grow on its own.
--
-- The creating role owns what it creates, so a developer schema needs no
-- further grants for its owner to build in it.
GRANT CREATE SCHEMA ON DATABASE {{ base }} TO ROLE {{ base }}_rw;

{% for schema in schemas %}
GRANT USAGE ON SCHEMA {{ base }}.{{ schema.name }} TO ROLE {{ base }}_ro;
GRANT USAGE ON SCHEMA {{ base }}.{{ schema.name }} TO ROLE {{ base }}_rw;
{% endfor %}

-- -----------------------------------------------------------------------
-- Inherited Data Access Grants: Read/Write
--
-- Uniform across every schema, which is exactly the case inherited grants are
-- designed for. One statement per object type per schema, covering current and
-- future objects.
-- -----------------------------------------------------------------------
{% for schema in schemas %}
GRANT INHERITED SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA {{ base }}.{{ schema.name }} TO ROLE {{ base }}_rw;
GRANT INHERITED SELECT ON ALL VIEWS IN SCHEMA {{ base }}.{{ schema.name }} TO ROLE {{ base }}_rw;
{% endfor %}

GRANT INHERITED USAGE ON ALL STAGES IN SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
GRANT INHERITED USAGE ON ALL FUNCTIONS IN SCHEMA {{ base }}.utilities TO ROLE {{ base }}_rw;

-- Collapses the old pair of `OPERATE ON ALL TASKS` plus
-- `OPERATE ON FUTURE TASKS` into one statement. The ON ALL half was always a
-- no-op on a fresh deploy: it resolved against tasks existing at that moment,
-- of which there were none, and vanished from the changeset.
GRANT INHERITED OPERATE ON ALL TASKS IN DATABASE {{ base }} TO ROLE {{ base }}_rw;

-- -----------------------------------------------------------------------
-- Inherited Data Access Grants: Read Only
--
-- Views are deliberately readable only in modeled and utilities, matching the
-- original grants: raw and curated views are implementation detail.
-- -----------------------------------------------------------------------
{% for schema in schemas %}
GRANT INHERITED SELECT ON ALL TABLES IN SCHEMA {{ base }}.{{ schema.name }} TO ROLE {{ base }}_ro;
{% endfor %}

GRANT INHERITED SELECT ON ALL VIEWS IN SCHEMA {{ base }}.modeled TO ROLE {{ base }}_ro;
GRANT INHERITED SELECT ON ALL VIEWS IN SCHEMA {{ base }}.utilities TO ROLE {{ base }}_ro;
GRANT INHERITED USAGE ON ALL FUNCTIONS IN SCHEMA {{ base }}.utilities TO ROLE {{ base }}_ro;

-- -----------------------------------------------------------------------
-- Schema DDL Privileges
--
-- These are grants ON each schema, not inheritable privileges, and they differ
-- per schema by design: only raw ingests files, only curated schedules tasks,
-- only modeled and utilities build dynamic tables, only utilities defines
-- functions. Kept explicit per schema so the differences stay visible.
-- -----------------------------------------------------------------------

-- RAW: the landing zone, so it gets the full ingestion surface.
GRANT CREATE FILE FORMAT ON SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
GRANT CREATE TABLE ON SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
GRANT CREATE VIEW ON SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
GRANT CREATE STAGE ON SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
GRANT CREATE PIPE ON SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
GRANT CREATE STREAM ON SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
GRANT CREATE EXTERNAL TABLE ON SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;

-- CURATED: tables, views, and the scheduled work that maintains them.
GRANT CREATE TABLE ON SCHEMA {{ base }}.curated TO ROLE {{ base }}_rw;
GRANT CREATE VIEW ON SCHEMA {{ base }}.curated TO ROLE {{ base }}_rw;
GRANT CREATE TASK ON SCHEMA {{ base }}.curated TO ROLE {{ base }}_rw;

-- MODELED: where the dbt marts land.
GRANT CREATE TABLE ON SCHEMA {{ base }}.modeled TO ROLE {{ base }}_rw;
GRANT CREATE VIEW ON SCHEMA {{ base }}.modeled TO ROLE {{ base }}_rw;
GRANT CREATE DYNAMIC TABLE ON SCHEMA {{ base }}.modeled TO ROLE {{ base }}_rw;

-- UTILITIES: shared UDFs, so it is the only schema granted CREATE FUNCTION.
GRANT CREATE TABLE ON SCHEMA {{ base }}.utilities TO ROLE {{ base }}_rw;
GRANT CREATE VIEW ON SCHEMA {{ base }}.utilities TO ROLE {{ base }}_rw;
GRANT CREATE DYNAMIC TABLE ON SCHEMA {{ base }}.utilities TO ROLE {{ base }}_rw;
GRANT CREATE FUNCTION ON SCHEMA {{ base }}.utilities TO ROLE {{ base }}_rw;
