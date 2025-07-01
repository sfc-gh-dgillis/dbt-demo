USE ROLE ACCOUNTADMIN;
CREATE ROLE myco_secrets_admin;
GRANT CREATE SECRET ON SCHEMA myco_db.integrations TO ROLE myco_secrets_admin;

USE ROLE myco_db_owner;
GRANT USAGE ON DATABASE myco_db TO ROLE myco_secrets_admin;
GRANT USAGE ON SCHEMA myco_db.integrations TO ROLE myco_secrets_admin;

USE ROLE myco_secrets_admin;
USE DATABASE myco_db;
USE SCHEMA myco_db.integrations;

CREATE OR REPLACE SECRET myco_git_secret
  TYPE = password
  USERNAME = 'gladyskravitz'
  PASSWORD = 'ghp_token';