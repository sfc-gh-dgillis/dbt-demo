use role sysadmin;

drop project dcm.projects.dbt_demo_sysadmin;

create project if not exists dcm.projects.dbt_demo_sysadmin;

alter project dcm.projects.dbt_demo_sysadmin
      SET LOG_LEVEL = 'INFO';

DESCRIBE project dcm.projects.dbt_demo_sysadmin;

