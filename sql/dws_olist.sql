-- ============================================================================
-- Olist 数据仓库 - DWS (汇总数据层)
-- ============================================================================
-- 说明：
-- 1. 从 dwd_trade_detail 按主题聚合，支撑 Day5 ADS 指标
-- 2. GMV/订单数按 order_status='delivered' 过滤（已完成订单）
-- 3. payment_value_sum 在 DWD 中按订单重复，聚合时需先按 order_id 去重
-- ============================================================================

USE olist_dw;

-- ============================================================================
-- 前置：HDFS 目录（需在 namenode 容器内执行）
-- hdfs dfs -mkdir -p /dw/dws/olist/gmv_day
-- hdfs dfs -mkdir -p /dw/dws/olist/product_sales
-- hdfs dfs -mkdir -p /dw/dws/olist/region_day
-- hdfs dfs -mkdir -p /dw/dws/olist/city_day
-- hdfs dfs -mkdir -p /dw/dws/olist/payment_type_day
-- hdfs dfs -mkdir -p /dw/dws/olist/user_order_summary
-- hdfs dfs -chown -R hive:hive /dw/dws/olist
-- ============================================================================

-- ============================================================================
-- 1. DWS_GMV_DAY - 日 GMV 汇总
-- ============================================================================
DROP TABLE IF EXISTS dws_gmv_day;
CREATE EXTERNAL TABLE IF NOT EXISTS dws_gmv_day (
    dt STRING COMMENT '日期 yyyy-MM-dd',
    gmv DECIMAL(14,2) COMMENT 'GMV-当日已交付订单支付总额',
    order_cnt BIGINT COMMENT '订单数',
    customer_cnt BIGINT COMMENT '下单客户数',
    avg_order_amt DECIMAL(12,2) COMMENT '客单价'
)
COMMENT 'DWS日GMV汇总-粒度:order_purchase_date'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/dws/olist/gmv_day';

INSERT OVERWRITE TABLE dws_gmv_day
SELECT
    order_purchase_date AS dt,
    SUM(pay_amt) AS gmv,
    COUNT(*) AS order_cnt,
    COUNT(DISTINCT customer_id) AS customer_cnt,
    ROUND(SUM(pay_amt) / COUNT(*), 2) AS avg_order_amt
FROM (
    SELECT order_purchase_date, order_id, customer_id, MAX(payment_value_sum) AS pay_amt
    FROM dwd_trade_detail
    WHERE order_status = 'delivered'
      AND order_purchase_date IS NOT NULL
      AND order_purchase_date != ''
    GROUP BY order_purchase_date, order_id, customer_id
) t
GROUP BY order_purchase_date;

-- ============================================================================
-- 2. DWS_PRODUCT_SALES - 商品+日期销售汇总
-- ============================================================================
DROP TABLE IF EXISTS dws_product_sales;
CREATE EXTERNAL TABLE IF NOT EXISTS dws_product_sales (
    product_id STRING COMMENT '商品ID',
    product_category_name_english STRING COMMENT '商品类目(英文)',
    dt STRING COMMENT '日期',
    sales_amt DECIMAL(14,2) COMMENT '销售额-item_total_amount之和',
    order_cnt BIGINT COMMENT '订单数',
    item_qty BIGINT COMMENT '销售件数',
    buyer_cnt BIGINT COMMENT '购买人数'
)
COMMENT 'DWS商品日销售汇总-粒度:product_id+order_purchase_date'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/dws/olist/product_sales';

INSERT OVERWRITE TABLE dws_product_sales
SELECT
    product_id,
    COALESCE(product_category_name_english, 'unknown') AS product_category_name_english,
    order_purchase_date AS dt,
    SUM(item_total_amount) AS sales_amt,
    COUNT(DISTINCT order_id) AS order_cnt,
    COUNT(*) AS item_qty,
    COUNT(DISTINCT customer_id) AS buyer_cnt
FROM dwd_trade_detail
WHERE order_status = 'delivered'
  AND order_purchase_date IS NOT NULL
  AND order_purchase_date != ''
  AND product_id IS NOT NULL
GROUP BY product_id, product_category_name_english, order_purchase_date;

-- ============================================================================
-- 3. DWS_REGION_DAY - 地区+日期销售汇总
-- ============================================================================
DROP TABLE IF EXISTS dws_region_day;
CREATE EXTERNAL TABLE IF NOT EXISTS dws_region_day (
    customer_state STRING COMMENT '客户所在州/省',
    dt STRING COMMENT '日期',
    gmv DECIMAL(14,2) COMMENT 'GMV',
    order_cnt BIGINT COMMENT '订单数',
    customer_cnt BIGINT COMMENT '下单客户数'
)
COMMENT 'DWS地区日销售汇总-粒度:customer_state+order_purchase_date'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/dws/olist/region_day';

INSERT OVERWRITE TABLE dws_region_day
SELECT
    COALESCE(customer_state, 'unknown') AS customer_state,
    order_purchase_date AS dt,
    SUM(pay_amt) AS gmv,
    COUNT(*) AS order_cnt,
    COUNT(DISTINCT customer_id) AS customer_cnt
FROM (
    SELECT order_purchase_date, customer_id, customer_state, order_id, MAX(payment_value_sum) AS pay_amt
    FROM dwd_trade_detail
    WHERE order_status = 'delivered'
      AND order_purchase_date IS NOT NULL
      AND order_purchase_date != ''
    GROUP BY order_purchase_date, customer_id, customer_state, order_id
) t
GROUP BY customer_state, order_purchase_date;

-- ============================================================================
-- 4. DWS_CITY_DAY - 城市+日期销售汇总（支撑 ads_city_sales）
-- ============================================================================
DROP TABLE IF EXISTS dws_city_day;
CREATE EXTERNAL TABLE IF NOT EXISTS dws_city_day (
    customer_city STRING COMMENT '客户所在城市',
    customer_state STRING COMMENT '客户所在州/省',
    dt STRING COMMENT '日期',
    gmv DECIMAL(14,2) COMMENT 'GMV',
    order_cnt BIGINT COMMENT '订单数',
    customer_cnt BIGINT COMMENT '下单客户数'
)
COMMENT 'DWS城市日销售汇总-粒度:customer_city+customer_state+order_purchase_date'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/dws/olist/city_day';

INSERT OVERWRITE TABLE dws_city_day
SELECT
    COALESCE(customer_city, 'unknown') AS customer_city,
    COALESCE(customer_state, 'unknown') AS customer_state,
    order_purchase_date AS dt,
    SUM(pay_amt) AS gmv,
    COUNT(*) AS order_cnt,
    COUNT(DISTINCT customer_id) AS customer_cnt
FROM (
    SELECT order_purchase_date, customer_id, customer_city, customer_state, order_id, MAX(payment_value_sum) AS pay_amt
    FROM dwd_trade_detail
    WHERE order_status = 'delivered'
      AND order_purchase_date IS NOT NULL
      AND order_purchase_date != ''
    GROUP BY order_purchase_date, customer_id, customer_city, customer_state, order_id
) t
GROUP BY customer_city, customer_state, order_purchase_date;

-- ============================================================================
-- 5. DWS_PAYMENT_TYPE_DAY - 支付方式+日期汇总
-- ============================================================================
DROP TABLE IF EXISTS dws_payment_type_day;
CREATE EXTERNAL TABLE IF NOT EXISTS dws_payment_type_day (
    payment_type STRING COMMENT '支付类型',
    dt STRING COMMENT '日期',
    gmv DECIMAL(14,2) COMMENT 'GMV',
    order_cnt BIGINT COMMENT '订单数'
)
COMMENT 'DWS支付方式日汇总-粒度:payment_type+order_purchase_date'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/dws/olist/payment_type_day';

INSERT OVERWRITE TABLE dws_payment_type_day
SELECT
    COALESCE(payment_type, 'unknown') AS payment_type,
    order_purchase_date AS dt,
    SUM(pay_amt) AS gmv,
    COUNT(*) AS order_cnt
FROM (
    SELECT order_purchase_date, payment_type, order_id, MAX(payment_value_sum) AS pay_amt
    FROM dwd_trade_detail
    WHERE order_status = 'delivered'
      AND order_purchase_date IS NOT NULL
      AND order_purchase_date != ''
    GROUP BY order_purchase_date, payment_type, order_id
) t
GROUP BY payment_type, order_purchase_date;

-- ============================================================================
-- 6. DWS_USER_ORDER_SUMMARY - 用户订单汇总
-- ============================================================================
DROP TABLE IF EXISTS dws_user_order_summary;
CREATE EXTERNAL TABLE IF NOT EXISTS dws_user_order_summary (
    customer_id STRING COMMENT '客户ID',
    last_order_date STRING COMMENT '最近一次下单日期',
    first_order_date STRING COMMENT '首次下单日期',
    order_cnt BIGINT COMMENT '订单数',
    total_amt DECIMAL(14,2) COMMENT '累计支付金额'
)
COMMENT 'DWS用户订单汇总-粒度:customer_id'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/dws/olist/user_order_summary';

INSERT OVERWRITE TABLE dws_user_order_summary
SELECT
    customer_id,
    MAX(order_purchase_date) AS last_order_date,
    MIN(order_purchase_date) AS first_order_date,
    COUNT(DISTINCT order_id) AS order_cnt,
    SUM(pay_amt) AS total_amt
FROM (
    SELECT customer_id, order_id, order_purchase_date, MAX(payment_value_sum) AS pay_amt
    FROM dwd_trade_detail
    WHERE order_status = 'delivered'
      AND customer_id IS NOT NULL
      AND order_purchase_date IS NOT NULL
    GROUP BY customer_id, order_id, order_purchase_date
) t
GROUP BY customer_id;

-- ============================================================================
-- 验证
-- ============================================================================
-- SELECT * FROM dws_gmv_day LIMIT 10;
-- SELECT * FROM dws_product_sales LIMIT 10;
-- SELECT * FROM dws_region_day LIMIT 10;
-- SELECT * FROM dws_city_day LIMIT 10;
-- SELECT * FROM dws_payment_type_day LIMIT 10;
-- SELECT * FROM dws_user_order_summary LIMIT 10;
