-- Databases and schemas.
--
-- DCM also creates a PUBLIC schema for every defined database. That is implicit
-- and does not need declaring.

DEFINE DATABASE {{ base }}
    COMMENT = 'dbt {{ env_label }} database';

{% for schema in schemas %}
DEFINE SCHEMA {{ base }}.{{ schema.name }}
    COMMENT = 'dbt {{ env_label }} - {{ schema.comment }}';
{% endfor %}
