GRANT EXECUTE TASK ON ACCOUNT TO ROLE {{ base }}_rw;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE {{ base }}_rw;

{% for wh in warehouses %}
GRANT USAGE ON WAREHOUSE {{ base }}_{{ wh.suffix }}_wh TO ROLE {{ base }}_rw;
{% endfor %}

GRANT USAGE ON DATABASE {{ base }} TO ROLE {{ base }}_ro;
GRANT USAGE ON DATABASE {{ base }} TO ROLE {{ base }}_rw;

GRANT CREATE SCHEMA ON DATABASE {{ base }} TO ROLE {{ base }}_rw;

{% for schema in schemas %}
GRANT USAGE ON SCHEMA {{ base }}.{{ schema.name }} TO ROLE {{ base }}_ro;
GRANT USAGE ON SCHEMA {{ base }}.{{ schema.name }} TO ROLE {{ base }}_rw;
{% endfor %}

{% for schema in schemas %}
GRANT INHERITED SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA {{ base }}.{{ schema.name }} TO ROLE {{ base }}_rw;
GRANT INHERITED SELECT ON ALL VIEWS IN SCHEMA {{ base }}.{{ schema.name }} TO ROLE {{ base }}_rw;
{% endfor %}

GRANT INHERITED USAGE ON ALL STAGES IN SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
GRANT INHERITED USAGE ON ALL FUNCTIONS IN SCHEMA {{ base }}.utilities TO ROLE {{ base }}_rw;

GRANT INHERITED OPERATE ON ALL TASKS IN DATABASE {{ base }} TO ROLE {{ base }}_rw;

{% for schema in schemas %}
GRANT INHERITED SELECT ON ALL TABLES IN SCHEMA {{ base }}.{{ schema.name }} TO ROLE {{ base }}_ro;
{% endfor %}

GRANT INHERITED SELECT ON ALL VIEWS IN SCHEMA {{ base }}.modeled TO ROLE {{ base }}_ro;
GRANT INHERITED SELECT ON ALL VIEWS IN SCHEMA {{ base }}.utilities TO ROLE {{ base }}_ro;
GRANT INHERITED USAGE ON ALL FUNCTIONS IN SCHEMA {{ base }}.utilities TO ROLE {{ base }}_ro;

GRANT CREATE FILE FORMAT ON SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
GRANT CREATE TABLE ON SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
GRANT CREATE VIEW ON SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
GRANT CREATE STAGE ON SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
GRANT CREATE PIPE ON SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
GRANT CREATE STREAM ON SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
GRANT CREATE EXTERNAL TABLE ON SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;

-- CURATED: tables, views, and the scheduled work that maintains them.
GRANT CREATE TABLE ON SCHEMA {{ base }}.curated TO ROLE {{ base }}_rw;
GRANT CREATE VIEW ON SCHEMA {{ base }}.curated TO ROLE {{ base }}_rw;
GRANT CREATE TASK ON SCHEMA {{ base }}.curated TO ROLE {{ base }}_rw;

-- MODELED: where the dbt marts land.
GRANT CREATE TABLE ON SCHEMA {{ base }}.modeled TO ROLE {{ base }}_rw;
GRANT CREATE VIEW ON SCHEMA {{ base }}.modeled TO ROLE {{ base }}_rw;
GRANT CREATE DYNAMIC TABLE ON SCHEMA {{ base }}.modeled TO ROLE {{ base }}_rw;

-- UTILITIES: shared UDFs, so it is the only schema granted CREATE FUNCTION.
GRANT CREATE TABLE ON SCHEMA {{ base }}.utilities TO ROLE {{ base }}_rw;
GRANT CREATE VIEW ON SCHEMA {{ base }}.utilities TO ROLE {{ base }}_rw;
GRANT CREATE DYNAMIC TABLE ON SCHEMA {{ base }}.utilities TO ROLE {{ base }}_rw;
GRANT CREATE FUNCTION ON SCHEMA {{ base }}.utilities TO ROLE {{ base }}_rw;

{% for schema in schemas %}
GRANT OWNERSHIP ON SCHEMA {{ base }}.{{ schema.name }} TO ROLE {{ base }}_rw;
{% endfor %}

GRANT OWNERSHIP ON ALL TABLES IN SCHEMA {{ base }}.raw TO ROLE {{ base }}_rw;
