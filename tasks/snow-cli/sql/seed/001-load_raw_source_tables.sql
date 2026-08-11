USE ROLE sysadmin;

-- Start small. The common paths (nothing to do, or a zero-copy clone) need almost
-- no compute; the block below scales up to XL only if it has to fall back to S3.
USE WAREHOUSE dev_dbt_demo_xs_wh;

-- -----------------------------------------------------------------------
-- Populate the RAW schema with source data.
--
-- Replaces the old unconditional clone script. Runs after the DCM deploy, which
-- has already created the 9 tables empty from
-- dcm/sources/definitions/raw_tables.sql. This step only ever adds rows; it
-- never changes structure.
--
-- Per table, if the table is empty:
--
--   1. FAST PATH - if XX_DBT_DEMO_BACKUP exists, zero-copy clone from it.
--      Instant, no compute, no extra storage. XX_ rather than an environment
--      prefix because one backup serves both dev and prod.
--
--   2. FALLBACK - otherwise COPY INTO from the public Tasty Bytes S3 bucket,
--      following the quickstart's file-format-plus-external-stage pattern:
--      https://github.com/Snowflake-Labs/sfguide-getting-started-from-zero-to-snowflake
--
-- A non-empty table is left alone, so re-running demo-up is safe and will not
-- silently refresh data. Drop or truncate a table to force a reload.
--
-- Why the fallback is not a straight COPY INTO
--
-- The public CSVs are shaped for the quickstart's schema, which is NOT this
-- project's schema. Verified against the bucket:
--
--   truck             CSV has 14 columns, table has 15 - no truck_type
--   customer_loyalty  CSV has 15 columns, table has 16 - no last_update_ts
--   core_poi_geometry the quickstart never loads it; the file has a header row
--                     and quoted fields containing commas, so it needs its own
--                     file format
--
-- Both missing columns are load bearing. truck_type feeds stg_pos__truck and
-- d_truck. last_update_ts is the incremental watermark in d_loyalty_member:
--
--   WHERE last_update_ts >= (SELECT COALESCE(MAX(last_update_ts), '1900-01-01') FROM {{ this }})
--
-- Loading with ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE would leave it NULL, that
-- predicate would match no rows, and d_loyalty_member would build 0 rows without
-- raising anything. So the fallback synthesizes both columns explicitly through
-- COPY INTO ... FROM (SELECT ...):
--
--   last_update_ts -> CURRENT_TIMESTAMP() at load time, which is what the
--                     incremental watermark actually wants
--   truck_type     -> NULL, since the public data cannot supply it
--
-- The fallback is equivalent demo data, not a byte-identical restore. Public S3
-- has 335 franchise rows against the backup's 325, and 222,540 customer_loyalty
-- rows against 222,541.
--
-- DEV only. The block runs on the XS warehouse and switches to XL only when it
-- actually falls back to S3, because order_header is 248M rows and order_detail
-- is 673M. A clone, or a run with nothing to do, never wakes the big warehouse.
-- -----------------------------------------------------------------------

-- File formats and external stage, per the quickstart pattern.
CREATE OR REPLACE FILE FORMAT dev_dbt_demo.raw.csv_ff
    TYPE = 'csv'
    COMMENT = 'Tasty Bytes quickstart CSVs: no header, unquoted.';

-- core_poi_geometry needs different options: its file has a header row, and
-- polygon_wkt contains commas inside quotes.
CREATE OR REPLACE FILE FORMAT dev_dbt_demo.raw.csv_header_quoted_ff
    TYPE = 'csv'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    COMMENT = 'Safegraph POI CSV: header row and quoted fields containing commas.';

CREATE OR REPLACE STAGE dev_dbt_demo.raw.tb_s3load
    URL = 's3://sfquickstarts/frostbyte_tastybytes/'
    FILE_FORMAT = dev_dbt_demo.raw.csv_ff
    COMMENT = 'Public Tasty Bytes quickstart data, used when XX_DBT_DEMO_BACKUP is absent.';

EXECUTE IMMEDIATE $$
DECLARE
    has_backup BOOLEAN DEFAULT FALSE;
    n INTEGER;
    row_count INTEGER;
    tbl STRING;
    loaded_from STRING;
    tables ARRAY DEFAULT ARRAY_CONSTRUCT(
        'country', 'franchise', 'location', 'menu', 'truck',
        'order_header', 'order_detail', 'customer_loyalty', 'core_poi_geometry'
    );
    -- Per-table fallback COPY. Kept as a map so the loop below stays uniform
    -- while each table keeps whatever transformation it needs.
    copy_sql OBJECT DEFAULT OBJECT_CONSTRUCT(
        'country',
            'COPY INTO dev_dbt_demo.raw.country
             FROM @dev_dbt_demo.raw.tb_s3load/raw_pos/country/',
        'franchise',
            'COPY INTO dev_dbt_demo.raw.franchise
             FROM @dev_dbt_demo.raw.tb_s3load/raw_pos/franchise/',
        'location',
            'COPY INTO dev_dbt_demo.raw.location
             FROM @dev_dbt_demo.raw.tb_s3load/raw_pos/location/',
        'menu',
            'COPY INTO dev_dbt_demo.raw.menu
             FROM @dev_dbt_demo.raw.tb_s3load/raw_pos/menu/',
        'order_header',
            'COPY INTO dev_dbt_demo.raw.order_header
             FROM @dev_dbt_demo.raw.tb_s3load/raw_pos/order_header/',
        'order_detail',
            'COPY INTO dev_dbt_demo.raw.order_detail
             FROM @dev_dbt_demo.raw.tb_s3load/raw_pos/order_detail/',
        -- 14 CSV columns then a synthesized truck_type.
        'truck',
            'COPY INTO dev_dbt_demo.raw.truck FROM (
                 SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14,
                        NULL
                 FROM @dev_dbt_demo.raw.tb_s3load/raw_pos/truck/
             )',
        -- 15 CSV columns then a synthesized last_update_ts.
        'customer_loyalty',
            'COPY INTO dev_dbt_demo.raw.customer_loyalty FROM (
                 SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15,
                        CURRENT_TIMESTAMP()
                 FROM @dev_dbt_demo.raw.tb_s3load/raw_customer/customer_loyalty/
             )',
        'core_poi_geometry',
            'COPY INTO dev_dbt_demo.raw.core_poi_geometry
             FROM @dev_dbt_demo.raw.tb_s3load/raw_safegraph/core_poi_geometry.csv
             FILE_FORMAT = (FORMAT_NAME = ''dev_dbt_demo.raw.csv_header_quoted_ff'')'
    );
BEGIN
    SHOW DATABASES LIKE 'XX_DBT_DEMO_BACKUP';
    SELECT COUNT(*) INTO :n FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    has_backup := (:n > 0);

    -- Only the S3 path needs real compute, so pay for it only then.
    IF (NOT :has_backup) THEN
        EXECUTE IMMEDIATE 'USE WAREHOUSE dev_dbt_demo_xl_wh';
    END IF;

    FOR i IN 0 TO ARRAY_SIZE(:tables) - 1 DO
        tbl := GET(:tables, i)::STRING;

        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM dev_dbt_demo.raw.' || :tbl;
        SELECT $1 INTO :row_count FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

        IF (:row_count > 0) THEN
            CONTINUE;
        END IF;

        IF (:has_backup) THEN
            EXECUTE IMMEDIATE
                'CREATE OR REPLACE TABLE dev_dbt_demo.raw.' || :tbl ||
                ' CLONE xx_dbt_demo_backup.raw.' || :tbl;
        ELSE
            EXECUTE IMMEDIATE GET(:copy_sql, :tbl)::STRING;
        END IF;
    END FOR;

    loaded_from := IFF(:has_backup,
                       'XX_DBT_DEMO_BACKUP (zero-copy clone)',
                       'public Tasty Bytes S3 bucket (COPY INTO)');
    RETURN 'Raw tables checked. Any empty table was loaded from ' || :loaded_from || '.';
END
$$;

-- Report what the RAW schema holds now.
SELECT 'country' AS table_name, COUNT(*) AS row_count FROM dev_dbt_demo.raw.country
UNION ALL SELECT 'franchise', COUNT(*) FROM dev_dbt_demo.raw.franchise
UNION ALL SELECT 'location', COUNT(*) FROM dev_dbt_demo.raw.location
UNION ALL SELECT 'menu', COUNT(*) FROM dev_dbt_demo.raw.menu
UNION ALL SELECT 'truck', COUNT(*) FROM dev_dbt_demo.raw.truck
UNION ALL SELECT 'order_header', COUNT(*) FROM dev_dbt_demo.raw.order_header
UNION ALL SELECT 'order_detail', COUNT(*) FROM dev_dbt_demo.raw.order_detail
UNION ALL SELECT 'customer_loyalty', COUNT(*) FROM dev_dbt_demo.raw.customer_loyalty
UNION ALL SELECT 'core_poi_geometry', COUNT(*) FROM dev_dbt_demo.raw.core_poi_geometry
ORDER BY table_name;
