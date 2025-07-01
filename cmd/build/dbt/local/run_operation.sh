#!/usr/bin/env bash

export DBT_ENV_SECRET_PAT="op://Employee/demo-tastyb/password"
op run -- dbt run-operation --target dev-tastyb --project-dir .