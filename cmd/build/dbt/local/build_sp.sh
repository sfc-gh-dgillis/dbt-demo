#!/usr/bin/env bash

export DBT_ENV_SECRET_PAT="op://Employee/demo-tastyb/password"

op run -- dbt run-operation --target dev-tastyb create_concatenate_object_values --args '{database: dev_dbt_demo, schema: utilities}'
#op run -- \
#  dbt run-operation --target dev-tastyb create_gen_surrogate_key \
#  --args '{database: 'dev_dbt_demo', schema: 'utilities'}'
