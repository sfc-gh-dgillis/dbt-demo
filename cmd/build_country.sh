#!/usr/bin/env bash

export DBT_ENV_SECRET_PAT="op://Employee/demo-tastyb/password"
op run -- dbt build --target dev-tastyb --project-dir . --select stg_pos__country