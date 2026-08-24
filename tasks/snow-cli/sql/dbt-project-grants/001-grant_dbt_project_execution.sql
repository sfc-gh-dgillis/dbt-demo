USE ROLE accountadmin;

-- -----------------------------------------------------------------------
-- Lets the sandbox's data engineer role execute the DBT PROJECT object.
--
-- Why this file exists at all: dbt Projects on Snowflake splits deployment from
-- execution, and the two use different roles. `snow dbt deploy` runs as the role
-- in the CLI connection (ACCOUNTADMIN here, which owns the object), while
-- EXECUTE DBT PROJECT runs the dbt command as the role in profiles.yml and is
-- further restricted to the privileges of the USER who called it. So the
-- sandbox's own data engineer role -- the one env.yml resolves and the one the
-- tastyb PAT connection authenticates as -- needs to reach an object that lives
-- outside the sandbox entirely, in the shared util database.
--
-- Per the EXECUTE DBT PROJECT reference, the executing role needs USAGE on the
-- dbt project, and "operating on an object in a schema requires at least one
-- privilege on the parent database and at least one privilege on the parent
-- schema" -- hence three grants, not one. MONITOR is added so the same role can
-- open the project's run history in Snowsight; without it the object is
-- executable but invisible there.
--
-- Deliberately imperative rather than declarative. Two independent reasons:
--   - DCM has no DEFINE for a DBT PROJECT object, and the object is not in any
--     DCM project's managed set, so a grant on it cannot be declared.
--   - util and util.dbt_project_archive are created by sql/bootstrap, precisely
--     because DCM cannot manage the schema that holds its own project object.
--
-- Deliberately NOT in sql/bootstrap either, even though that folder is also
-- imperative and admin-run. bootstrap executes for DEV, PROD and DBT_PDB alike
-- and is passed no template variables, so a file that requires <% base %> would
-- leave an unresolved placeholder in a role name on the dev and prod paths. This
-- folder is invoked only by demo-up-pdb, which knows the sandbox name.
--
-- Note these grants are to the ROLE, so they survive a PAT being re-minted, and
-- they are scoped to one specific project object rather than the schema, so a
-- second DBT PROJECT deployed alongside it is not implicitly executable.
--
-- Telemetry is deliberately absent. Reading run logs means selecting from
-- SNOWFLAKE.TELEMETRY.EVENTS, which requires ACCOUNTADMIN or the
-- SNOWFLAKE.EVENTS_VIEWER application role. That event table is ACCOUNT-WIDE, so
-- granting it here would hand a per-developer sandbox role read access to every
-- other workload's telemetry on the account. The dbt-project-logs / -errors /
-- -spans tasks stay on the admin connection instead.
-- -----------------------------------------------------------------------

GRANT USAGE ON DATABASE <% dbt_project_database %>
    TO ROLE <% base %>_data_engineer;

GRANT USAGE ON SCHEMA <% dbt_project_database %>.<% dbt_project_schema %>
    TO ROLE <% base %>_data_engineer;

GRANT USAGE, MONITOR ON DBT PROJECT
    <% dbt_project_database %>.<% dbt_project_schema %>.<% dbt_project_object_name %>
    TO ROLE <% base %>_data_engineer;
