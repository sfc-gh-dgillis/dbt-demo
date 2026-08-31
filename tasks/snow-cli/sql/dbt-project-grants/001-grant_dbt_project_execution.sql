USE ROLE accountadmin;

GRANT USAGE ON DATABASE <% dbt_project_database %>
    TO ROLE <% base %>_data_engineer;

GRANT USAGE ON SCHEMA <% dbt_project_database %>.<% dbt_project_schema %>
    TO ROLE <% base %>_data_engineer;

GRANT USAGE, MONITOR ON DBT PROJECT
    <% dbt_project_database %>.<% dbt_project_schema %>.<% dbt_project_object_name %>
    TO ROLE <% base %>_data_engineer;
