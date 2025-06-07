USE ROLE sysadmin;

CREATE DATABASE IF NOT EXISTS dbt_demo
    COMMENT = 'dbt demo database';

CREATE SCHEMA IF NOT EXISTS dbt_demo.raw
    COMMENT = 'dbt demo - RAW data landing schema';

CREATE SCHEMA IF NOT EXISTS dbt_demo.curated
    COMMENT = 'dbt demo - Curated object schema';

CREATE SCHEMA IF NOT EXISTS dbt_demo.modeled
    COMMENT = 'dbt demo - Modeled object schema';

SHOW DATABASES;

USE DATABASE dbt_demo;
SHOW SCHEMAS;
