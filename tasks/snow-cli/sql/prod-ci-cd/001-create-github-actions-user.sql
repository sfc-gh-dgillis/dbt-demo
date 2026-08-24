CREATE USER IF NOT EXISTS github_actions_service_user
  TYPE = SERVICE
  WORKLOAD_IDENTITY = (
    TYPE = OIDC
    ISSUER = 'https://token.actions.githubusercontent.com',
    SUBJECT = 'repo:sfc-gh-dgillis/dbt-demo:environment:prod'
  )
  DEFAULT_ROLE = ACCOUNTADMIN
  COMMENT = 'Service user for GitHub Actions';

GRANT ROLE ACCOUNTADMIN TO USER github_actions_service_user;

ALTER USER github_actions_service_user SET DEFAULT_WAREHOUSE = 'DBT_DEMO_PROD_M_WH';

CREATE NETWORK POLICY github_actions_policy
  ALLOWED_NETWORK_RULE_LIST = ('SNOWFLAKE.NETWORK_SECURITY.GITHUBACTIONS_GLOBAL')
  BLOCKED_NETWORK_RULE_LIST = ();

ALTER USER github_actions_service_user
  SET NETWORK_POLICY = github_actions_policy;
