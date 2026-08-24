# Developer Loop

How the same models in this repo get built in three different places.

The models, tests, and macros never change between stages. What changes is
*where dbt runs*, *which credentials it uses*, and *which schema the output
lands in*. That is the whole idea: promote the code, not a rewrite of it.

## Sections

- [The three stages](#the-three-stages)
- [Stage 1 - Run dbt locally](#stage-1---run-dbt-locally)
  - [Why start here](#why-start-here)
  - [Prerequisites](#prerequisites)
  - [Build the marts](#build-the-marts)
  - [What that selector actually builds](#what-that-selector-actually-builds)
  - [Where the models land](#where-the-models-land)
  - [The tighter inner loop](#the-tighter-inner-loop)
  - [Verify the build](#verify-the-build)
  - [Troubleshooting: insufficient privileges to operate on view](#troubleshooting-insufficient-privileges-to-operate-on-view)
  - [The limitation of this stage](#the-limitation-of-this-stage)
- [Stage 2 - Run dbt inside Snowflake](#stage-2---run-dbt-inside-snowflake)
  - [Why bother, when stage 1 already works](#why-bother-when-stage-1-already-works)
  - [Deploy the project object](#deploy-the-project-object)
  - [Validate before you build](#validate-before-you-build)
  - [Run the shared dev environment](#run-the-shared-dev-environment)
  - [The two-role model](#the-two-role-model)
  - [Per-developer isolation](#per-developer-isolation)
  - [Verify the isolation](#verify-the-isolation)
  - [What isolation does not cover](#what-isolation-does-not-cover)
  - [A note on who can see what](#a-note-on-who-can-see-what)
  - [Clean up your schema](#clean-up-your-schema)
  - [Observability](#observability)
- [Stage 3 - Deploy to production with GitHub Actions](#stage-3---deploy-to-production-with-github-actions)

## The three stages

| | Stage 1 - Local | Stage 2 - dbt Projects on Snowflake | Stage 3 - GitHub Actions |
| --- | --- | --- | --- |
| dbt executes on | your laptop | Snowflake | a CI runner, targeting Snowflake |
| Credentials | a target in `~/.dbt/profiles.yml` | none in the project: the PAT connection that issues `EXECUTE DBT PROJECT` | repo secrets |
| Code source | your working tree, committed or not | a versioned `DBT PROJECT` object | the merged commit |
| Writes to | `dbt_pdb_<user>`, shared schemas | `dbt_pdb_<user>`, shared schemas | `prod_dbt_demo` |
| Entrypoint | `task dbt-build-marts` | `task dbt-project-run-marts` | *(stage 3)* |

Each stage trades feedback speed for reproducibility. Stage 1 will run code you
have not committed, which is exactly what you want while iterating and exactly
what you do not want in production.

## Stage 1 - Run dbt locally

### Why start here

Fastest possible loop. dbt parses your working tree directly, so an edit is one
`task` invocation away from being materialized in Snowflake. Nothing is staged,
uploaded, or versioned, and there is no deploy step to wait on.

The cost is that this stage is unreproducible by anyone else: it runs whatever
is currently on your disk, under your personal credentials.

### Prerequisites

**1. Activate the virtual environment.** dbt is installed there, not globally.

```shell
source ./.venv/bin/activate
```

**2. Have a credentialed target in `~/.dbt/profiles.yml`.** See
[Connection Profile Setup](../README.md#connection-profile-setup) in the README
for the full example. The local tasks default to a target named `dev-tastyb`,
which uses PAT authentication as the user `tastyb` with the role
`dev_dbt_demo_data_engineer`.

If your profile names that target something else, override it per run rather
than editing the Taskfile:

```shell
DBT_TARGET=dev-pat-auth task dbt-build-marts
```

**3. Mint a PAT if you are using PAT authentication.** The `dev-tastyb` target
reads its password from `DBT_ENV_SECRET_PAT`:

```shell
task pat-create
```

That creates the `dev_dbt_demo_pat` token, pins it to
`dev_dbt_demo_data_engineer`, and writes the `export DBT_ENV_SECRET_PAT=...`
line into your `~/.zshrc`, replacing any previous one. Re-run it when the token
expires (90 days by default). Open a new shell, or `source ~/.zshrc`, so the
export is in your environment.

**4. Confirm dbt can connect.**

```shell
dbt debug --target dev-tastyb --project-dir . --profiles-dir ~/.dbt
```

> **Why `--profiles-dir ~/.dbt` is not optional.** There is a `profiles.yml` at
> the project root, and it belongs to stage 2 - it deliberately contains no
> account, user, or credentials, because Snowflake supplies those at run time.
> Local dbt searches the current working directory *before* `~/.dbt/`, so
> without the flag it would load the root file and fail to connect. Every task
> in `tasks/dbt/dbt-tasks.yml` passes the flag for this reason.

### Build the marts

```shell
task dbt-build-marts
```

That is the local counterpart of `task dbt-project-run-marts` in stage 2. Both
run the same selection; only the execution context differs.

Under the hood it runs:

```shell
dbt build --target dev-tastyb --project-dir . --profiles-dir ~/.dbt \
  --select +path:models/marts --exclude f_order f_order_line
```

### What that selector actually builds

`+path:models/marts` selects everything in `models/marts` **plus all upstream
ancestors**, which is what pulls in the staging views and the intermediate
model without naming them.

The two fact tables are excluded on purpose: `f_order` is 248M rows and
`f_order_line` is 673M rows. They need a larger warehouse and are built
separately by `task dbt-project-run-facts`.

That leaves 17 models and 12 tests, which dbt reports as
`PASS=29 WARN=0 ERROR=0 SKIP=0 TOTAL=29`:

| Layer | Models | Nodes |
| --- | --- | --- |
| `models/marts` | 8 dimensions | `d_country`, `d_franchise`, `d_location`, `d_loyalty_member`, `d_menu_item`, `d_menu_item_ingredients`, `d_menu_type`, `d_truck` |
| `models/intermediate` | 1 table | `int_franchise_deduped` |
| `models/staging` | 8 views | `stg_loyalty__customer_loyalty`, `stg_pos__country`, `stg_pos__franchise`, `stg_pos__location`, `stg_pos__menu`, `stg_pos__order_detail`, `stg_pos__order_header`, `stg_pos__truck` |

`stg_safegraph__core_poi_geometry` is absent because no mart references it, so
it is not an ancestor of anything selected.

To see the model list yourself without building anything:

```shell
dbt ls --target dev-tastyb --profiles-dir ~/.dbt \
  --select +path:models/marts --exclude f_order f_order_line --resource-type model
```

### Where the models land

Each layer is routed to a fixed schema by `dbt_project.yml`, all inside the
`dev_dbt_demo` database:

| Layer | `dbt_project.yml` config | Resolved schema | Materialization |
| --- | --- | --- | --- |
| `staging` | `+schema: raw` | `dev_dbt_demo.raw` | view |
| `intermediate` | `+schema: curated` | `dev_dbt_demo.curated` | table |
| `marts` | *(none)* | `dev_dbt_demo.modeled` | table |

`marts` sets no `+schema`, so it falls through to the target's own schema,
`modeled`. One mart overrides its materialization in the model file itself:
`d_loyalty_member` is `incremental` on `unique_key='customer_id'`, so a rebuild
merges rather than replaces.

That override also has a second job, which is what makes stage 2 work; see
[the limitation of this stage](#the-limitation-of-this-stage).

### The tighter inner loop

Building 17 models to check one change is wasteful. When you are iterating on a
single dimension, select just it and its ancestors:

```shell
task dbt:build-country-dimension
```

which is:

```shell
dbt build --target dev-tastyb --project-dir . --profiles-dir ~/.dbt --select +d_country
```

Use the same `+model_name` shape for any other model, for example
`--select +d_franchise` to pick up `int_franchise_deduped` and
`stg_pos__franchise` along the way.

### Verify the build

dbt reports pass/fail per node, but it is worth confirming the objects landed
in the schemas the table above predicts:

```sql
SELECT table_schema, table_type, count(*) AS objects
FROM dev_dbt_demo.information_schema.tables
WHERE table_schema IN ('RAW', 'CURATED', 'MODELED')
GROUP BY 1, 2
ORDER BY 1, 2;
```

Expect views in `RAW` (the staging layer), a table in `CURATED`
(`int_franchise_deduped`), and the dimension tables in `MODELED`.

Ownership is worth checking too, for the reason in the next subsection:

```sql
SELECT table_schema, table_type, table_owner, count(*) AS objects
FROM dev_dbt_demo.information_schema.tables
WHERE table_schema IN ('RAW', 'CURATED', 'MODELED')
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
```

Every dbt-built object should be owned by `DEV_DBT_DEMO_DATA_ENGINEER`. The nine
base tables in `RAW` are the exception: those are the source tables declared in
DCM, so they are owned by the DCM project owner (`ACCOUNTADMIN`) and dbt only
reads them.

### Troubleshooting: insufficient privileges to operate on view

```text
003001 (42501): SQL access control error:
Insufficient privileges to operate on view 'STG_POS__FRANCHISE'.
Your primary role DEV_DBT_DEMO_DATA_ENGINEER must have OWNERSHIP
granted on TABLE DEV_DBT_DEMO.RAW.STG_POS__FRANCHISE.
```

dbt materializes tables and views with `CREATE OR REPLACE`, and that requires
**OWNERSHIP** of the existing object, not merely write privileges. Ownership in
Snowflake follows the creating role, and nothing in
`tasks/snow-cli/dcm/sources/definitions/grants.sql` grants OWNERSHIP - the model
is deliberately creator-owns. So this error means the object was created by a
*different* role than the one you are building with.

The usual cause is a run whose role was not pinned. `DBT_CURRENT_ROLE` in
`env.yml` is set to a literal role for exactly this reason; when it was
previously `{{ select CURRENT_ROLE() }}` it inherited whoever triggered the run,
and a run triggered as `ACCOUNTADMIN` produced `ACCOUNTADMIN`-owned objects that
no later `data_engineer` run could replace.

Pinning the role fixes future runs but not objects already created. Repair those
by transferring ownership of the dbt-built objects, leaving the DCM-managed
source tables alone:

```sql
GRANT OWNERSHIP ON ALL VIEWS  IN SCHEMA dev_dbt_demo.raw
  TO ROLE dev_dbt_demo_data_engineer COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL TABLES IN SCHEMA dev_dbt_demo.curated
  TO ROLE dev_dbt_demo_data_engineer COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL TABLES IN SCHEMA dev_dbt_demo.modeled
  TO ROLE dev_dbt_demo_data_engineer COPY CURRENT GRANTS;
```

`COPY CURRENT GRANTS` preserves the existing grants on those objects instead of
revoking them. Note the first statement targets `ALL VIEWS`, not `ALL TABLES`:
the staging views in `raw` are dbt's, while the base tables beside them belong
to DCM and must keep their current owner.

### The limitation of this stage

**Every developer running stage 1 writes to the same three schemas.** The
`dev-tastyb` target has `schema: modeled`, which is shared. Two people building
`d_franchise` at the same time are issuing `CREATE OR REPLACE TABLE` against
the same object, and the last one to finish wins. Neither gets an error, which
makes it worse.

That is not a flaw in the target so much as an unavoidable property of a shared
schema. Fixing it means giving each developer their own schema, and doing that
by hand for every engineer does not scale.

Stage 2 solves it: the `dev_user` environment in `env.yml` derives the schema
name from `CURRENT_USER()` at run time, so isolation is automatic and requires
no per-developer configuration.

## Stage 2 - Run dbt inside Snowflake

In this stage the project is deployed into Snowflake as a `DBT PROJECT` object
and dbt runs *there*. Snowflake owns the runtime, the dbt version, and the
orchestration, so there is no Python environment to maintain and no dbt CLI
version drift between developers.

Snowflake's [best practices for dbt Projects on
Snowflake](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake-best-practices)
sanctions deploying and testing this way for **dev and staging** targets.
Production is deliberately different and belongs in stage 3: deploying straight
to a production project object, whether from the Git stage or by pulling in
Workspaces and clicking deploy, is called out there as an anti-pattern because
nothing gates the change behind tests and review.

### Why bother, when stage 1 already works

| | Stage 1 (local) | Stage 2 (in Snowflake) |
| --- | --- | --- |
| dbt install | yours, and yours alone | Snowflake-managed, identical for everyone |
| dbt version | whatever you `pip install`ed (1.9.4 here) | pinned on the object (1.11.11 here) |
| Credentials | a PAT or key pair on your disk | none stored; runs as the calling session |
| Reproducible by a teammate | no, it is your working tree | yes, it is a numbered version |
| Schema collisions | shared `modeled` | isolated per developer |

The last two rows are the point. Stage 1 cannot be reproduced by anyone else and
cannot be isolated; stage 2 gives you both.

### Deploy the project object

```shell
task dbt-project-deploy
```

Two things happen. First `cmd/stage-dbt-project.sh` copies a clean payload into
`.build/dbt` using an explicit whitelist - `dbt_project.yml`, `profiles.yml`,
`env.yml`, `packages.yml`, `package-lock.yml`, and the `models`, `macros`,
`seeds`, `data-tests`, `dbt_packages` directories. That matters because the dbt
project lives at the repo root next to `.venv` (~9,700 files), `.git`, `target/`
and `logs/`, and a project object is capped at 20,000 files. The script fails
loudly if a `.venv` or `.git` slips in.

Then `snow dbt deploy` uploads it. Note what is *not* passed:

- **No `--force`.** Without it an existing object gains a new version; with it
  Snowflake runs `CREATE OR REPLACE` and destroys every prior version and all
  run history.
- **No `--profiles-dir`.** The staged payload already contains a credential-free
  `profiles.yml`. Pointing at `~/.dbt` would supply one containing a password,
  which `snow dbt deploy` rejects outright.
- **No `--database` / `--schema`.** On Snowflake CLI 3.24.1 those are *connection*
  overrides, and `--database` is not applied when the deploy creates its
  temporary stage - it lands in `<connection default database>.<--schema>` and
  fails. The object name is fully qualified instead.

Confirm the result:

```shell
task dbt-project-list
```

```text
name          database_name  schema_name           dbt_version  default_version_name  default_target
TASTY_BYTES   UTIL           DBT_PROJECT_ARCHIVE   1.11.11      VERSION$4             dev
```

The object lives in `util.dbt_project_archive`, not in `dev_dbt_demo`. Keeping it
in the shared `util` database means its version history survives a full teardown
and rebuild of the databases it builds into.

1.11.11 is deliberate: Snowflake recommends the latest supported dbt Core 1.11.x
for the broadest materialization and package support. dbt Fusion (2.x) is worth
considering past roughly 5,000 models, which this project is nowhere near.

### Validate before you build

```shell
task dbt-project-compile
```

Compiling is the cheap way to prove `profiles.yml`, `env.yml`, and every `ref()`
resolve. It runs no DDL, so it costs a few seconds of warehouse time and cannot
damage anything. Run it after editing `env.yml` in particular, since a broken
environment variable will otherwise surface partway through a build.

### Run the shared dev environment

```shell
task dbt-project-run-marts
```

Same selection as stage 1, executed inside Snowflake. It issues:

```sql
EXECUTE DBT PROJECT util.dbt_project_archive.tasty_bytes
  ARGS = 'build --select +path:models/marts --exclude f_order f_order_line --target dev'
  ENVIRONMENT = 'dev';
```

`EXECUTE DBT PROJECT` in SQL is used rather than `snow dbt execute` because
Snowflake CLI 3.24.1 has no `--env` or `--env-vars` flags - `--environment` is
merely an alias for `--connection` - and selecting an `env.yml` environment is
the entire point here.

### The two-role model

This is the part that surprises people. Every `EXECUTE DBT PROJECT` involves
**two** roles:

1. **The calling role** - the active role of the session issuing the statement.
   It needs `EXECUTE DBT PROJECT` on the project object.
2. **The `profiles.yml` role** - what dbt actually builds as. It determines which
   databases, schemas, and tables the run can touch.

Both roles need `USAGE` on the warehouse, the calling role must be able to
`USE` the `profiles.yml` role, and **effective privileges are the intersection of
the two**. A permission missing from either role is missing from the run.

In this project:

| | Resolved from | Value here |
| --- | --- | --- |
| Calling role | the `snow sql` connection in `.env/demo.env` | `ACCOUNTADMIN` (connection default) |
| `profiles.yml` role | `env_var('DBT_CURRENT_ROLE')`, set in `env.yml` | `dev_dbt_demo_data_engineer` |

`DBT_CURRENT_ROLE` is pinned to a **literal role**, and that is a deliberate
departure from Snowflake's example, which suggests
`DBT_CURRENT_ROLE: "{{ select CURRENT_ROLE() }}"` so the profile follows the
caller. Inheriting the caller is what broke this project once: dbt materializes
tables with `CREATE OR REPLACE`, which requires OWNERSHIP, and ownership follows
the creating role. A run triggered as `ACCOUNTADMIN` produced `ACCOUNTADMIN`-owned
marts that no later `data_engineer` run could replace. See
[the stage 1 troubleshooting section](#troubleshooting-insufficient-privileges-to-operate-on-view)
for the error and the repair. A fixed role keeps ownership consistent no matter
who triggers the run, which matters more here than following the caller.

The warehouse is aligned on purpose too. `execute-dbt-project` passes
`--warehouse` matching `DBT_CURRENT_WH`, so the outer session and the dbt run use
the same warehouse. Mismatch them and a single run wakes two warehouses and bills
for both.

### Per-developer isolation

```shell
task dbt-project-run-marts-dev-user
```

Identical to `dbt-project-run-marts` apart from `ENVIRONMENT = 'dev_user'`. That
environment in `env.yml` computes the schema at run time:

```yaml
- name: dev_user
  env:
    DBT_CURRENT_DB: dev_dbt_demo
    DBT_CURRENT_SCHEMA: "{{ select REPLACE(SPLIT_PART(CURRENT_USER(), '@', 1), '.', '_') }}"
    DBT_CURRENT_WH: dev_dbt_demo_s_wh
    DBT_CURRENT_ROLE: dev_dbt_demo_data_engineer
```

Snowflake resolves that SQL *before* dbt starts and injects the result as an
environment variable. Nothing in the task names a developer, so the same command
gives every engineer a different schema:

- `dgillis` -> `dev_dbt_demo.dgillis`
- `first.last@example.com` -> `dev_dbt_demo.first_last`

The `SPLIT_PART` and `REPLACE` matter because a raw `CURRENT_USER()` is often an
email address, and `@` and `.` are not valid in an unquoted identifier.

#### Everything collapses into that one schema

In the shared environments each layer routes to its own schema. Under `dev_user`
they all land together:

| Layer | `dev` environment | `dev_user` environment |
| --- | --- | --- |
| `staging` | `dev_dbt_demo.raw` | `dev_dbt_demo.<user>` |
| `intermediate` | `dev_dbt_demo.curated` | `dev_dbt_demo.<user>` |
| `marts` | `dev_dbt_demo.modeled` | `dev_dbt_demo.<user>` |

That collapse is the second job of `macros/generate_schema_name.sql`. Honoring
`+schema: raw` during a per-developer run would send every developer's staging
views back into the shared `raw` schema and defeat the isolation entirely. The
macro therefore returns `target.schema` verbatim whenever the resolved schema is
not a known shared name:

```jinja
{%- set shared_schemas = ['modeled'] -%}
...
{%- elif target.schema | lower not in shared_schemas -%}
    {{ target.schema }}
```

It keys off the *resolved schema*, not `target.name`. That is not a stylistic
choice: `dev_user` is an `env.yml` **environment**, while `dev` and `prod` are dbt
**targets** in `profiles.yml`. They are independent axes, and this task passes
`--target dev` with `ENVIRONMENT = 'dev_user'`, so `target.name` is never
`dev_user` and any test against it would silently never fire.

#### Sources stay shared, so nothing is copied

Only *outputs* are isolated. The staging views in your schema still read the
shared raw tables, so a per-developer run duplicates no source data:

```sql
SELECT GET_DDL('VIEW', 'dev_dbt_demo.dgillis.stg_pos__franchise');
```

```sql
create or replace view STG_POS__FRANCHISE(...) as (
    with source as ( select * from dev_dbt_demo.raw.franchise )
    ...
```

#### The one grant this requires

dbt runs `create schema if not exists` for your schema on the first run, which
needs `CREATE SCHEMA` on the database. `grants.sql` grants it to the RW access
role:

```sql
GRANT CREATE SCHEMA ON DATABASE {{ env }}_dbt_demo TO ROLE {{ env }}_dbt_demo_rw;
```

Without it the run fails on the very first statement. Declaring a
`DEFINE SCHEMA` per developer would work too, but it would mean editing
`manifest.yml` and redeploying DCM for every new engineer; one grant lets the set
of developer schemas grow on its own. The creating role owns what it creates, so
your schema needs no further grants for you to build in it.

### Verify the isolation

```sql
SELECT table_schema, table_type, table_owner, count(*) AS objects
FROM dev_dbt_demo.information_schema.tables
WHERE table_schema NOT IN ('INFORMATION_SCHEMA', 'PUBLIC')
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
```

A successful `dev_user` run on this account produced
`PASS=29 WARN=0 ERROR=0 SKIP=0 TOTAL=29` in about 14 seconds and this layout:

```text
CURATED    BASE TABLE  DEV_DBT_DEMO_DATA_ENGINEER   1
DGILLIS    BASE TABLE  DEV_DBT_DEMO_DATA_ENGINEER   9
DGILLIS    VIEW        DEV_DBT_DEMO_DATA_ENGINEER   8
MODELED    BASE TABLE  DEV_DBT_DEMO_DATA_ENGINEER  10
RAW        BASE TABLE  ACCOUNTADMIN                 9
RAW        VIEW        DEV_DBT_DEMO_DATA_ENGINEER   9
```

All 17 models are in `DGILLIS` (9 tables = 8 dimensions plus
`int_franchise_deduped`, 8 staging views), owned by the creating role. The shared
`CURATED`, `MODELED`, and `RAW` contents are untouched by the run - which is the
whole point.

Confirm the schema and its owner directly:

```sql
SHOW SCHEMAS LIKE 'DGILLIS' IN DATABASE dev_dbt_demo;
```

### What isolation does not cover

Per-developer schemas isolate **output**. They do not isolate **execution**.

Snowflake documents that a single dbt project object supports **one concurrent
execution**, and that a second `EXECUTE DBT PROJECT` issued while one is running
fails. Every developer here shares one object,
`util.dbt_project_archive.tasty_bytes`, so that limit applies to the whole team
regardless of which schema each person writes to.

> **Measured on this account (dbt 1.11.11), the documented failure did not
> reproduce.** Two concurrent `compile` runs overlapped and both succeeded. Two
> `build` runs issued three seconds apart did not overlap at all: the second
> waited for the first to finish - `06:20:58`-`06:21:28` then
> `06:21:33`-`06:22:01` in query history, with zero warehouse queue time - and
> both succeeded. So the behavior here looks like serialization rather than
> rejection. Treat that as an observation to retest, not a guarantee to build on;
> the documented contract is that the second execution fails.

If concurrent execution becomes a real constraint, the options are to deploy a
separate project object per developer from the same source, split the DAG with
`--select` and chain the slices with task `AFTER` clauses, or lean on dbt threads
for parallelism *within* one execution. `profiles.yml` already sets
`threads: 8`, which is Snowflake's recommendation for compatibility with most
warehouse sizes.

### A note on who can see what

`MONITOR` on the project object grants access to the manifest, run history, and
artifacts (`manifest.json`, `run_results.json`, `dbt.log`) - useful for debugging
a failed run. It grants **no** access to the data the project produces. Likewise,
building a table does not grant anyone `SELECT` on it: analysts need explicit
grants, which is why `grants.sql` maintains a separate read-only access role.
The ability to build a pipeline and the ability to read its output are kept
separate on purpose.

### Clean up your schema

A developer schema is disposable. Drop it when a branch is done:

```sql
DROP SCHEMA IF EXISTS dev_dbt_demo.dgillis;
```

Nothing in DCM declares it, so dropping it produces no drift - `task dcm-plan`
will still report no changes.

### Observability

Stage 1 prints dbt's output to your terminal, so watching a run is free. Stage 2
does not: `EXECUTE DBT PROJECT` runs inside Snowflake and returns a single result
row, so by default a failed run leaves you nothing to read.

Snowflake fixes this by emitting OpenTelemetry logs and trace spans from every
run into the account's event table - but only if three telemetry levels are set
on the schema holding the project object:

```sql
ALTER SCHEMA util.dbt_project_archive SET LOG_LEVEL = 'INFO';
ALTER SCHEMA util.dbt_project_archive SET TRACE_LEVEL = 'ALWAYS';
ALTER SCHEMA util.dbt_project_archive SET METRIC_LEVEL = 'ALL';
```

Those live in `tasks/snow-cli/sql/bootstrap/001-create_util_database.sql` and are
applied by `task demo-up`. If the reader tasks below return nothing, an
unconfigured schema is the first thing to check:

```shell
snow sql -q "SHOW PARAMETERS LIKE '%LEVEL%' IN SCHEMA util.dbt_project_archive;"
```

`LOG_LEVEL`, `TRACE_LEVEL`, and `METRIC_LEVEL` should each report `SCHEMA` in the
`level` column. A blank `level` means the value is inherited and nothing has been
set here.

#### Why only the schema

The docs describe setting these on "the database and schema", which reads like two
operations. It is one. Object parameters resolve through a hierarchy of
**account -> database -> schema -> object**, and each level *overrides* the one
above rather than adding to it, so a schema-level setting is already complete.

Setting them on `util` as well would be actively worse here: `util` is shared and
predates this demo, so a database-level setting would switch on telemetry for
unrelated schemas that other teams own.

#### Reading a run

Four tasks, none of which need a query id - each resolves the most recent run of
the project object itself, via `DBT_PROJECT_EXECUTION_HISTORY`:

| Task | Shows |
| --- | --- |
| `task dbt-project-logs` | Every log line from the last run, chronologically |
| `task dbt-project-logs-errors` | Only `ERROR` and `WARN` from the last run |
| `task dbt-project-spans` | Per-step timings from the last run, slowest first |
| `task dbt-project-run-marts-tailed` | Runs the marts build and streams logs live |

The usual loop is run, then read:

```shell
task dbt-project-run-marts
task dbt-project-logs-errors
```

A full marts build emits around 74 log rows, which is why the errors-only variant
exists. Cap any of them with `ROW_LIMIT`:

```shell
ROW_LIMIT=20 task dbt-project-logs
```

One caveat on "most recent": `DBT_PROJECT_EXECUTION_HISTORY` reports runs of the
object by *any* user, not just yours. On a shared account, a colleague running the
same project object after you means these tasks show their run. Attribution is
still exact - query ids are globally unique, so events from two runs can never be
mixed - it is only the choice of *which* run that is account-wide. Add
`AND user_name = CURRENT_USER()` to the CTE in the SQL files if that matters.

#### Spans are the reason TRACE_LEVEL is on

Logs tell you what happened; spans tell you how long each step took. Span names
are dbt node ids, so the output points straight at a model or test:

```
model.tasty_bytes.stg_pos__order_header                    2222 ms
test.tasty_bytes.unique_d_country_country_key.4a3418be58    1843 ms
```

#### Watching a run live

`task dbt-project-run-marts-tailed` submits the build asynchronously and polls the
event table, printing new lines as they arrive. Two constraints come with it:

- **No environment selection.** `snow dbt execute` on Snowflake CLI 3.24.1 has no
  flag for `ENVIRONMENT` or `ENV_VARS`; those exist only on the `EXECUTE DBT
  PROJECT` SQL command. The tailed run therefore uses whatever
  `default_environment` in `env.yml` names, currently `dev`. To watch a
  `dev_user` or `prod` run, use the normal task and read the logs after.
- **The tail trails the run.** Event table writes lag by up to 10 seconds, so the
  final lines land after the run already reports finished. The script does one
  drain pass to collect them.

Ctrl-C stops the tail, not the run. The run continues inside Snowflake, and
`task dbt-project-logs` will still show it afterwards.

#### The 10-second delay

It applies to the reader tasks too. Running `task dbt-project-logs` the instant a
build returns can come back short - the last few lines simply have not been
written yet. Re-run it.

## Stage 3 - Deploy to production with GitHub Actions

*Not yet written.* Covers promoting the `DBT PROJECT` object to the
`prod_dbt_demo` database from CI, following the recommended pattern: a PR
deploys a tester object and runs `dbt build` against staging, and only a merge to
main deploys to the production object.

