#!/usr/bin/env bash

export DBT_ENV_SECRET_PAT="op://Employee/demo-tastyb/password"
op run -- dbt docs generate --target dev-tastyb --project-dir .

export DBT_ENV_SECRET_PAT="op://Employee/demo-tastyb/password"
op run -- dbt docs serve --target dev-tastyb --project-dir .