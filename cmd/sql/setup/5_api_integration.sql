USE ROLE ACCOUNTADMIN;

GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE myco_git_admin;

USE ROLE myco_db_owner;
GRANT USAGE ON DATABASE myco_db TO ROLE myco_git_admin;
GRANT USAGE ON SCHEMA myco_db.integrations TO ROLE myco_git_admin;

USE ROLE myco_secrets_admin;
GRANT USAGE ON SECRET myco_git_secret TO ROLE myco_git_admin;

USE ROLE myco_git_admin;
USE DATABASE myco_db;
USE SCHEMA myco_db.integrations;

CREATE OR REPLACE API INTEGRATION git_api_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/my-account')
  ALLOWED_AUTHENTICATION_SECRETS = (myco_git_secret)
  ENABLED = TRUE;