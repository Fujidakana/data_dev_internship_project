-- ============================================================================
-- Olist 数据仓库 - DWD (明细数据层)
-- ============================================================================
-- 说明：
-- 1. dwd_trade_detail：交易明细宽表，粒度 = order_id + order_item_id
-- 2. 从 ODS 6 表 JOIN 并轻度清洗入仓
-- 3. 支付表需先按 order_id 聚合，避免明细倍增
-- ============================================================================

USE olist_dw;

-- ============================================================================
-- 1. 创建 HDFS 目录（需在 namenode 容器内执行，或通过脚本执行）
-- hdfs dfs -mkdir -p /dw/dwd/olist/trade_detail
-- ============================================================================

-- ============================================================================
-- 2. DWD_TRADE_DETAIL - 交易明细宽表 DDL
-- ============================================================================
DROP TABLE IF EXISTS dwd_trade_detail;
CREATE EXTERNAL TABLE IF NOT EXISTS dwd_trade_detail (
    -- 订单主线
    order_id STRING COMMENT '订单ID',
    customer_id STRING COMMENT '客户ID',
    order_status STRING COMMENT '订单状态',
    order_purchase_timestamp STRING COMMENT '下单时间',
    order_purchase_date STRING COMMENT '下单日期(衍生)',
    -- 订单明细
    order_item_id INT COMMENT '订单内商品序号',
    product_id STRING COMMENT '商品ID',
    seller_id STRING COMMENT '卖家ID',
    price DECIMAL(10,2) COMMENT '商品价格',
    freight_value DECIMAL(10,2) COMMENT '运费',
    item_total_amount DECIMAL(10,2) COMMENT '商品+运费小计(衍生)',
    -- 支付
    payment_type STRING COMMENT '支付类型',
    payment_value_sum DECIMAL(12,2) COMMENT '订单支付总额',
    -- 客户
    customer_city STRING COMMENT '客户城市',
    customer_state STRING COMMENT '客户州/省',
    -- 商品
    product_category_name STRING COMMENT '商品类目(葡语)',
    product_category_name_english STRING COMMENT '商品类目(英文)',
    product_weight_g DOUBLE COMMENT '商品重量(g)',
    -- 跑批
    etl_date STRING COMMENT '跑批日期(衍生)'
)
COMMENT 'DWD交易明细宽表-粒度:order_id+order_item_id'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/dwd/olist/trade_detail';

-- ============================================================================
-- 3. 清洗入仓 - INSERT OVERWRITE
-- ============================================================================
INSERT OVERWRITE TABLE dwd_trade_detail
SELECT
    o.order_id,
    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp,
    substr(o.order_purchase_timestamp, 1, 10) AS order_purchase_date,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    coalesce(oi.price, 0) AS price,
    coalesce(oi.freight_value, 0) AS freight_value,
    coalesce(oi.price, 0) + coalesce(oi.freight_value, 0) AS item_total_amount,
    pay.payment_type,
    pay.payment_value_sum,
    c.customer_city,
    c.customer_state,
    p.product_category_name,
    ct.product_category_name_english,
    p.product_weight_g,
    cast(current_date AS string) AS etl_date
FROM ods_order_items oi
INNER JOIN ods_orders o ON oi.order_id = o.order_id
LEFT JOIN (
    SELECT order_id,
           min(struct(payment_sequential, payment_type)).col2 AS payment_type,
           sum(payment_value) AS payment_value_sum
    FROM ods_order_payments
    GROUP BY order_id
) pay ON oi.order_id = pay.order_id
LEFT JOIN ods_customers c ON o.customer_id = c.customer_id
LEFT JOIN ods_products p ON oi.product_id = p.product_id
LEFT JOIN ods_category_translation ct ON p.product_category_name = ct.product_category_name
WHERE oi.order_id IS NOT NULL
  AND oi.product_id IS NOT NULL
  AND o.customer_id IS NOT NULL;

-- ============================================================================
-- 4. 验证
-- ============================================================================
-- SELECT COUNT(*) FROM dwd_trade_detail;
-- SELECT * FROM dwd_trade_detail LIMIT 10;
