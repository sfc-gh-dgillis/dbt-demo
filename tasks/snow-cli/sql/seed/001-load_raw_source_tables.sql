USE ROLE sysadmin;

-- Start small. Probing row counts needs almost no compute; the block below scales
-- up to XL only if it finds something to load.
USE WAREHOUSE <% base %>_xs_wh;

-- -----------------------------------------------------------------------
-- Populate the RAW schema with source data.
--
-- Runs after the DCM deploy, which has already created the 9 tables empty from
-- dcm/sources/definitions/raw_tables.sql. This step only ever adds rows; it
-- never changes structure.
-- -----------------------------------------------------------------------

-- File formats and external stage, per the quickstart pattern.
CREATE OR REPLACE FILE FORMAT <% base %>.raw.csv_ff
    TYPE = 'csv'
    COMMENT = 'Tasty Bytes quickstart CSVs: no header, unquoted.';

-- core_poi_geometry needs different options: its file has a header row, and
-- polygon_wkt contains commas inside quotes.
CREATE OR REPLACE FILE FORMAT <% base %>.raw.csv_header_quoted_ff
    TYPE = 'csv'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    COMMENT = 'Safegraph POI CSV: header row and quoted fields containing commas.';

CREATE OR REPLACE STAGE <% base %>.raw.tb_s3load
    URL = 's3://sfquickstarts/frostbyte_tastybytes/'
    FILE_FORMAT = <% base %>.raw.csv_ff
    COMMENT = 'Public Tasty Bytes quickstart data.';

EXECUTE IMMEDIATE $$
DECLARE
    row_count INTEGER;
    tbl STRING;
    scaled_up BOOLEAN DEFAULT FALSE;
    loaded INTEGER DEFAULT 0;
    tables ARRAY DEFAULT ARRAY_CONSTRUCT(
        'country', 'franchise', 'location', 'menu', 'truck',
        'order_header', 'order_detail', 'customer_loyalty', 'core_poi_geometry'
    );
    -- Per-table COPY. Kept as a map so the loop below stays uniform while each
    -- table keeps whatever transformation it needs.
    copy_sql OBJECT DEFAULT OBJECT_CONSTRUCT(
        'country',
            'COPY INTO <% base %>.raw.country
             FROM @<% base %>.raw.tb_s3load/raw_pos/country/',
        'franchise',
            'COPY INTO <% base %>.raw.franchise
             FROM @<% base %>.raw.tb_s3load/raw_pos/franchise/',
        'location',
            'COPY INTO <% base %>.raw.location
             FROM @<% base %>.raw.tb_s3load/raw_pos/location/',
        'menu',
            'COPY INTO <% base %>.raw.menu
             FROM @<% base %>.raw.tb_s3load/raw_pos/menu/',
        'order_header',
            'COPY INTO <% base %>.raw.order_header
             FROM @<% base %>.raw.tb_s3load/raw_pos/order_header/',
        'order_detail',
            'COPY INTO <% base %>.raw.order_detail
             FROM @<% base %>.raw.tb_s3load/raw_pos/order_detail/',
        -- 14 CSV columns then a synthesized truck_type.
        'truck',
            'COPY INTO <% base %>.raw.truck FROM (
                 SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14,
                        NULL
                 FROM @<% base %>.raw.tb_s3load/raw_pos/truck/
             )',
        -- 15 CSV columns then a synthesized last_update_ts.
        'customer_loyalty',
            'COPY INTO <% base %>.raw.customer_loyalty FROM (
                 SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15,
                        CURRENT_TIMESTAMP()
                 FROM @<% base %>.raw.tb_s3load/raw_customer/customer_loyalty/
             )',
        'core_poi_geometry',
            'COPY INTO <% base %>.raw.core_poi_geometry
             FROM @<% base %>.raw.tb_s3load/raw_safegraph/core_poi_geometry.csv
             FILE_FORMAT = (FORMAT_NAME = ''<% base %>.raw.csv_header_quoted_ff'')'
    );
BEGIN
    FOR i IN 0 TO ARRAY_SIZE(:tables) - 1 DO
        tbl := GET(:tables, i)::STRING;

        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM <% base %>.raw.' || :tbl;
        SELECT $1 INTO :row_count FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

        IF (:row_count > 0) THEN
            CONTINUE;
        END IF;

        -- Only a real load needs real compute, so pay for it only once, and only
        -- when there is something to load.
        IF (NOT :scaled_up) THEN
            EXECUTE IMMEDIATE 'USE WAREHOUSE <% base %>_xl_wh';
            scaled_up := TRUE;
        END IF;

        EXECUTE IMMEDIATE GET(:copy_sql, :tbl)::STRING;
        loaded := :loaded + 1;
    END FOR;

    RETURN 'Raw tables checked. ' || :loaded ||
           ' of ' || ARRAY_SIZE(:tables) ||
           ' were empty and loaded from the public Tasty Bytes S3 bucket.';
END
$$;

-- Report what the RAW schema holds now.
SELECT 'country' AS table_name, COUNT(*) AS row_count FROM <% base %>.raw.country
UNION ALL SELECT 'franchise', COUNT(*) FROM <% base %>.raw.franchise
UNION ALL SELECT 'location', COUNT(*) FROM <% base %>.raw.location
UNION ALL SELECT 'menu', COUNT(*) FROM <% base %>.raw.menu
UNION ALL SELECT 'truck', COUNT(*) FROM <% base %>.raw.truck
UNION ALL SELECT 'order_header', COUNT(*) FROM <% base %>.raw.order_header
UNION ALL SELECT 'order_detail', COUNT(*) FROM <% base %>.raw.order_detail
UNION ALL SELECT 'customer_loyalty', COUNT(*) FROM <% base %>.raw.customer_loyalty
UNION ALL SELECT 'core_poi_geometry', COUNT(*) FROM <% base %>.raw.core_poi_geometry
ORDER BY table_name;
