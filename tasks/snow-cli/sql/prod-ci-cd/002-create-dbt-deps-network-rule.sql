USE DATABASE <% base %>;
USE SCHEMA utilities;

-- Create NETWORK RULE for external access integration
CREATE OR REPLACE NETWORK RULE dbt_deps_network_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  -- Minimal URL allowlist that is required for dbt deps
  VALUE_LIST = (
    'hub.getdbt.com',
    'codeload.github.com'
    );

-- Create EXTERNAL ACCESS INTEGRATION for dbt access to external dbt package locations
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION dbt_deps_ext_access
  ALLOWED_NETWORK_RULES = (dbt_deps_network_rule)
  ENABLED = TRUE;

-- Grant USAGE so data engineers can select and use the integration
GRANT USAGE ON INTEGRATION dbt_deps_ext_access TO ROLE <% base %>_data_engineer;
