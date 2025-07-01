

# from project root, project will be created
snow project create dbt_demo_sysadmin -c demo_dgillis_keypair_auth --dbname dcm --schemaname projects

snow project dry-run dbt_demo_sysadmin -c demo_dgillis_keypair_auth --dbname dcm --schemaname projects

snow project execute dbt_demo_sysadmin -c demo_dgillis_keypair_auth --dbname dcm --schemaname projects
