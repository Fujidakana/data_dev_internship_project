-- ============================================================================
-- Olist 数据仓库 - ADS (应用数据层)
-- ============================================================================
-- 说明：
-- 1. 从 DWS/DWD 构建应用层报表，支撑 BI 与 Spark 导出
-- 2. 日表 + 月表 + 排行表 + 监控表
-- ============================================================================

USE olist_dw;

-- ============================================================================
-- 前置：HDFS 目录（需在 namenode 容器内执行）
-- hdfs dfs -mkdir -p /dw/ads/olist/gmv_trend
-- hdfs dfs -mkdir -p /dw/ads/olist/product_topn
-- hdfs dfs -mkdir -p /dw/ads/olist/region_sales_rank
-- hdfs dfs -mkdir -p /dw/ads/olist/order_status_day
-- hdfs dfs -mkdir -p /dw/ads/olist/gmv_month
-- hdfs dfs -mkdir -p /dw/ads/olist/region_sales_month
-- hdfs dfs -mkdir -p /dw/ads/olist/payment_type_month
-- hdfs dfs -mkdir -p /dw/ads/olist/payment_dist
-- hdfs dfs -mkdir -p /dw/ads/olist/category_topn
-- hdfs dfs -mkdir -p /dw/ads/olist/city_sales
-- hdfs dfs -chown -R hive:hive /dw/ads/olist
-- ============================================================================

-- ============================================================================
-- 1. ADS_GMV_TREND - 日 GMV 趋势
-- ============================================================================
DROP TABLE IF EXISTS ads_gmv_trend;
CREATE EXTERNAL TABLE IF NOT EXISTS ads_gmv_trend (
    dt STRING COMMENT '日期 yyyy-MM-dd',
    gmv DECIMAL(14,2) COMMENT 'GMV',
    order_cnt BIGINT COMMENT '订单数',
    customer_cnt BIGINT COMMENT '客户数',
    avg_order_amt DECIMAL(12,2) COMMENT '客单价'
)
COMMENT 'ADS日GMV趋势'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ads/olist/gmv_trend';

INSERT OVERWRITE TABLE ads_gmv_trend
SELECT dt, gmv, order_cnt, customer_cnt, avg_order_amt
FROM dws_gmv_day
ORDER BY dt;

-- ============================================================================
-- 2. ADS_PRODUCT_TOPN - Top 商品销售额排行
-- ============================================================================
DROP TABLE IF EXISTS ads_product_topn;
CREATE EXTERNAL TABLE IF NOT EXISTS ads_product_topn (
    rank_num INT COMMENT '排名',
    product_id STRING COMMENT '商品ID',
    product_category_name_english STRING COMMENT '类目英文',
    sales_amt DECIMAL(14,2) COMMENT '累计销售额',
    order_cnt BIGINT COMMENT '累计订单数',
    item_qty BIGINT COMMENT '累计销售件数'
)
COMMENT 'ADS商品销售额TopN'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ads/olist/product_topn';

INSERT OVERWRITE TABLE ads_product_topn
SELECT
    rank_num,
    product_id,
    product_category_name_english,
    sales_amt,
    order_cnt,
    item_qty
FROM (
    SELECT
        ROW_NUMBER() OVER (ORDER BY sales_amt DESC) AS rank_num,
        product_id,
        product_category_name_english,
        sales_amt,
        order_cnt,
        item_qty
    FROM (
        SELECT
            product_id,
            product_category_name_english,
            SUM(sales_amt) AS sales_amt,
            SUM(order_cnt) AS order_cnt,
            SUM(item_qty) AS item_qty
        FROM dws_product_sales
        GROUP BY product_id, product_category_name_english
    ) t
) r
WHERE rank_num <= 100;

-- ============================================================================
-- 3. ADS_REGION_SALES_RANK - 地区销售排行
-- ============================================================================
DROP TABLE IF EXISTS ads_region_sales_rank;
CREATE EXTERNAL TABLE IF NOT EXISTS ads_region_sales_rank (
    rank_num INT COMMENT '排名',
    customer_state STRING COMMENT '州/省',
    gmv DECIMAL(14,2) COMMENT '累计GMV',
    order_cnt BIGINT COMMENT '累计订单数',
    customer_cnt BIGINT COMMENT '累计客户数'
)
COMMENT 'ADS地区销售排行'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ads/olist/region_sales_rank';

INSERT OVERWRITE TABLE ads_region_sales_rank
SELECT
    rank_num,
    customer_state,
    gmv,
    order_cnt,
    customer_cnt
FROM (
    SELECT
        ROW_NUMBER() OVER (ORDER BY gmv DESC) AS rank_num,
        customer_state,
        gmv,
        order_cnt,
        customer_cnt
    FROM (
        SELECT
            customer_state,
            SUM(gmv) AS gmv,
            SUM(order_cnt) AS order_cnt,
            SUM(customer_cnt) AS customer_cnt
        FROM dws_region_day
        GROUP BY customer_state
    ) t
) r;

-- ============================================================================
-- 4. ADS_ORDER_STATUS_DAY - 每日订单状态分布（监控 unavailable/canceled）
-- ============================================================================
DROP TABLE IF EXISTS ads_order_status_day;
CREATE EXTERNAL TABLE IF NOT EXISTS ads_order_status_day (
    dt STRING COMMENT '下单日期',
    order_status STRING COMMENT '订单状态',
    order_cnt BIGINT COMMENT '订单数'
)
COMMENT 'ADS每日订单状态分布-用于监控异常状态'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ads/olist/order_status_day';

INSERT OVERWRITE TABLE ads_order_status_day
SELECT
    order_purchase_date AS dt,
    COALESCE(order_status, 'unknown') AS order_status,
    COUNT(DISTINCT order_id) AS order_cnt
FROM dwd_trade_detail
WHERE order_purchase_date IS NOT NULL AND order_purchase_date != ''
GROUP BY order_purchase_date, order_status
ORDER BY dt, order_status;

-- ============================================================================
-- 5. ADS_GMV_MONTH - 月 GMV 趋势
-- ============================================================================
DROP TABLE IF EXISTS ads_gmv_month;
CREATE EXTERNAL TABLE IF NOT EXISTS ads_gmv_month (
    month_dt STRING COMMENT '月份 yyyy-MM',
    gmv DECIMAL(14,2) COMMENT 'GMV',
    order_cnt BIGINT COMMENT '订单数',
    customer_cnt BIGINT COMMENT '客户数',
    avg_order_amt DECIMAL(12,2) COMMENT '客单价'
)
COMMENT 'ADS月GMV趋势'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ads/olist/gmv_month';

INSERT OVERWRITE TABLE ads_gmv_month
SELECT
    substr(dt, 1, 7) AS month_dt,
    SUM(gmv) AS gmv,
    SUM(order_cnt) AS order_cnt,
    SUM(customer_cnt) AS customer_cnt,
    ROUND(SUM(gmv) / SUM(order_cnt), 2) AS avg_order_amt
FROM dws_gmv_day
GROUP BY substr(dt, 1, 7)
ORDER BY month_dt;

-- ============================================================================
-- 6. ADS_REGION_SALES_MONTH - 地区月度销售
-- ============================================================================
DROP TABLE IF EXISTS ads_region_sales_month;
CREATE EXTERNAL TABLE IF NOT EXISTS ads_region_sales_month (
    month_dt STRING COMMENT '月份 yyyy-MM',
    customer_state STRING COMMENT '州/省',
    gmv DECIMAL(14,2) COMMENT 'GMV',
    order_cnt BIGINT COMMENT '订单数',
    customer_cnt BIGINT COMMENT '客户数'
)
COMMENT 'ADS地区月度销售'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ads/olist/region_sales_month';

INSERT OVERWRITE TABLE ads_region_sales_month
SELECT
    substr(dt, 1, 7) AS month_dt,
    customer_state,
    SUM(gmv) AS gmv,
    SUM(order_cnt) AS order_cnt,
    SUM(customer_cnt) AS customer_cnt
FROM dws_region_day
GROUP BY substr(dt, 1, 7), customer_state
ORDER BY month_dt, gmv DESC;

-- ============================================================================
-- 7. ADS_PAYMENT_TYPE_MONTH - 支付方式月度
-- ============================================================================
DROP TABLE IF EXISTS ads_payment_type_month;
CREATE EXTERNAL TABLE IF NOT EXISTS ads_payment_type_month (
    month_dt STRING COMMENT '月份 yyyy-MM',
    payment_type STRING COMMENT '支付类型',
    gmv DECIMAL(14,2) COMMENT 'GMV',
    order_cnt BIGINT COMMENT '订单数'
)
COMMENT 'ADS支付方式月度'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ads/olist/payment_type_month';

INSERT OVERWRITE TABLE ads_payment_type_month
SELECT
    substr(dt, 1, 7) AS month_dt,
    payment_type,
    SUM(gmv) AS gmv,
    SUM(order_cnt) AS order_cnt
FROM dws_payment_type_day
GROUP BY substr(dt, 1, 7), payment_type
ORDER BY month_dt, gmv DESC;

-- ============================================================================
-- 8. ADS_PAYMENT_DIST - 支付方式分布（占比）
-- ============================================================================
DROP TABLE IF EXISTS ads_payment_dist;
CREATE EXTERNAL TABLE IF NOT EXISTS ads_payment_dist (
    payment_type STRING COMMENT '支付类型',
    gmv DECIMAL(14,2) COMMENT 'GMV',
    order_cnt BIGINT COMMENT '订单数',
    gmv_pct DECIMAL(5,2) COMMENT 'GMV占比%'
)
COMMENT 'ADS支付方式分布'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ads/olist/payment_dist';

INSERT OVERWRITE TABLE ads_payment_dist
SELECT
    payment_type,
    gmv,
    order_cnt,
    ROUND(gmv * 100.0 / total_gmv, 2) AS gmv_pct
FROM (
    SELECT
        payment_type,
        SUM(gmv) AS gmv,
        SUM(order_cnt) AS order_cnt
    FROM dws_payment_type_day
    GROUP BY payment_type
) t
CROSS JOIN (
    SELECT SUM(gmv) AS total_gmv FROM dws_gmv_day
) s
ORDER BY gmv DESC;

-- ============================================================================
-- 9. ADS_CATEGORY_TOPN - 类目销售 TopN
-- ============================================================================
DROP TABLE IF EXISTS ads_category_topn;
CREATE EXTERNAL TABLE IF NOT EXISTS ads_category_topn (
    rank_num INT COMMENT '排名',
    product_category_name_english STRING COMMENT '类目英文',
    sales_amt DECIMAL(14,2) COMMENT '累计销售额',
    order_cnt BIGINT COMMENT '累计订单数',
    item_qty BIGINT COMMENT '累计销售件数'
)
COMMENT 'ADS类目销售TopN'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ads/olist/category_topn';

INSERT OVERWRITE TABLE ads_category_topn
SELECT
    rank_num,
    product_category_name_english,
    sales_amt,
    order_cnt,
    item_qty
FROM (
    SELECT
        ROW_NUMBER() OVER (ORDER BY sales_amt DESC) AS rank_num,
        product_category_name_english,
        sales_amt,
        order_cnt,
        item_qty
    FROM (
        SELECT
            product_category_name_english,
            SUM(sales_amt) AS sales_amt,
            SUM(order_cnt) AS order_cnt,
            SUM(item_qty) AS item_qty
        FROM dws_product_sales
        GROUP BY product_category_name_english
    ) t
) r
WHERE rank_num <= 50;

-- ============================================================================
-- 10. ADS_CITY_SALES - 城市销售排行
-- ============================================================================
DROP TABLE IF EXISTS ads_city_sales;
CREATE EXTERNAL TABLE IF NOT EXISTS ads_city_sales (
    rank_num INT COMMENT '排名',
    customer_city STRING COMMENT '城市',
    customer_state STRING COMMENT '州/省',
    gmv DECIMAL(14,2) COMMENT '累计GMV',
    order_cnt BIGINT COMMENT '累计订单数',
    customer_cnt BIGINT COMMENT '累计客户数'
)
COMMENT 'ADS城市销售排行'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ads/olist/city_sales';

INSERT OVERWRITE TABLE ads_city_sales
SELECT
    rank_num,
    customer_city,
    customer_state,
    gmv,
    order_cnt,
    customer_cnt
FROM (
    SELECT
        ROW_NUMBER() OVER (ORDER BY gmv DESC) AS rank_num,
        customer_city,
        customer_state,
        gmv,
        order_cnt,
        customer_cnt
    FROM (
        SELECT
            customer_city,
            customer_state,
            SUM(gmv) AS gmv,
            SUM(order_cnt) AS order_cnt,
            SUM(customer_cnt) AS customer_cnt
        FROM dws_city_day
        GROUP BY customer_city, customer_state
    ) t
) r
WHERE rank_num <= 100;

-- ============================================================================
-- 验证
-- ============================================================================
-- SELECT * FROM ads_gmv_trend LIMIT 10;
-- SELECT * FROM ads_product_topn LIMIT 10;
-- SELECT * FROM ads_region_sales_rank LIMIT 10;
-- SELECT * FROM ads_order_status_day LIMIT 10;
-- SELECT * FROM ads_gmv_month LIMIT 10;
-- SELECT * FROM ads_region_sales_month LIMIT 10;
-- SELECT * FROM ads_payment_type_month LIMIT 10;
-- SELECT * FROM ads_payment_dist;
-- SELECT * FROM ads_category_topn LIMIT 10;
-- SELECT * FROM ads_city_sales LIMIT 10;
