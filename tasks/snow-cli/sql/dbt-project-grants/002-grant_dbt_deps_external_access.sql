-- Lets the sandbox role fetch remote dbt packages.
--
-- packages.yml pulls dbt-labs/codegen from the dbt hub, so `dbt deps` needs
-- outbound network access. In Snowflake-managed execution -- CoCo Desktop,
-- Workspaces, or a deployed project object -- that access comes from an
-- EXTERNAL ACCESS INTEGRATION, and the executing role needs USAGE on it.
-- CoCo Desktop only lists integrations the active role holds USAGE or
-- OWNERSHIP on, so without this grant the EAI is not even selectable in the
-- execution popover and `dbt deps` fails.
--
-- The integration itself is account-level and is created once, by
-- sql/prod-ci-cd-step-2/002-create-dbt-deps-network-rule.sql, which grants
-- USAGE only to dbt_prod_data_engineer. This file extends the same grant to a
-- sandbox role without recreating the integration: CREATE OR REPLACE here would
-- clobber the shared object that prod and CI depend on.
--
-- Consequence: this depends on `task demo-up-prod` having run at least once on
-- the account. On an account with no prod deployment the integration does not
-- exist and this grant fails.

USE ROLE accountadmin;

GRANT USAGE ON INTEGRATION dbt_deps_ext_access
    TO ROLE <% base %>_data_engineer;
