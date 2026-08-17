-- Databases and schemas.
--
-- Replaces sql/init/003-create_db_schema.sql. That script created both
-- dev_dbt_demo and prod_dbt_demo in a single run; here each target owns exactly
-- one database, so deploying DEV can never touch prod.
--
-- DCM also creates a PUBLIC schema for every defined database. That is implicit
-- and does not need declaring.

DEFINE DATABASE {{ base }}
    COMMENT = 'dbt {{ env_label }} database';

{% for schema in schemas %}
DEFINE SCHEMA {{ base }}.{{ schema.name }}
    COMMENT = 'dbt {{ env_label }} - {{ schema.comment }}';
{% endfor %}
