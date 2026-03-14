-- ============================================================================
-- Olist 数据仓库 - ODS (原始数据层) DDL
-- ============================================================================
-- 说明：
-- 1. ODS 层采用 EXTERNAL 表结构，数据直接存储在 HDFS 中
-- 2. 不进行数据清洗，保留原始数据格式和内容
-- 3. 使用 CSV 格式存储，支持 HDFS 管理
-- 4. 所有时间字段保持字符串格式，便于后续的统一处理
-- ============================================================================

-- 创建数据库
CREATE DATABASE IF NOT EXISTS olist_dw
LOCATION 'hdfs://namenode:9000/user/hive/warehouse/olist_dw.db';
USE olist_dw;

-- ============================================================================
-- 1. ODS_ORDERS - 订单主表
-- ============================================================================
DROP TABLE IF EXISTS ods_orders;
CREATE EXTERNAL TABLE IF NOT EXISTS ods_orders (
    order_id STRING COMMENT '订单 ID - 主键',
    customer_id STRING COMMENT '客户 ID - 外键关联 ods_customers',
    order_status STRING COMMENT '订单状态 (delivered, shipped, canceled)',
    order_purchase_timestamp STRING COMMENT '下单时间 - 核心时间字段',
    order_approved_at STRING COMMENT '支付批准时间',
    order_delivered_carrier_date STRING COMMENT '交付承运商时间',
    order_delivered_customer_date STRING COMMENT '用户签收时间',
    order_estimated_delivery_date STRING COMMENT '预计送达时间'
)
COMMENT '订单主表 - 保存所有订单的基本信息'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' 
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ods/olist/orders'
TBLPROPERTIES (
    "skip.header.line.count"="1",
    "field.delim"=","
);

-- ============================================================================
-- 2. ODS_ORDER_ITEMS - 订单明细表
-- ============================================================================
DROP TABLE IF EXISTS ods_order_items;
CREATE EXTERNAL TABLE IF NOT EXISTS ods_order_items (
    order_id STRING COMMENT '订单 ID - 外键',
    order_item_id INT COMMENT '订单内商品序号 - 与 order_id 组成候选主键',
    product_id STRING COMMENT '商品 ID - 外键关联 ods_products',
    seller_id STRING COMMENT '卖家 ID - 外键关联卖家维度表',
    shipping_limit_date STRING COMMENT '发货截止时间',
    price DECIMAL(10, 2) COMMENT '商品价格',
    freight_value DECIMAL(10, 2) COMMENT '运费金额'
)
COMMENT '订单明细表 - 保存每个订单中的商品信息（一个订单可能有多个商品）'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ods/olist/order_items'
TBLPROPERTIES (
    "skip.header.line.count"="1",
    "field.delim"=","
);

-- ============================================================================
-- 3. ODS_ORDER_PAYMENTS - 订单支付表
-- ============================================================================
DROP TABLE IF EXISTS ods_order_payments;
CREATE EXTERNAL TABLE IF NOT EXISTS ods_order_payments (
    order_id STRING COMMENT '订单 ID - 外键',
    payment_sequential INT COMMENT '支付序号 - 与 order_id 组成候选主键',
    payment_type STRING COMMENT '支付类型 (credit_card, boleto, voucher 等)',
    payment_installments INT COMMENT '分期次数',
    payment_value DECIMAL(12, 2) COMMENT '支付金额 - GMV 计算关键字段'
)
COMMENT '订单支付表 - 保存每个订单的支付信息（可能有多笔支付）'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ods/olist/order_payments'
TBLPROPERTIES (
    "skip.header.line.count"="1",
    "field.delim"=","
);

-- ============================================================================
-- 4. ODS_CUSTOMERS - 客户维度表
-- ============================================================================
DROP TABLE IF EXISTS ods_customers;
CREATE EXTERNAL TABLE IF NOT EXISTS ods_customers (
    customer_id STRING COMMENT '客户 ID - 主键，关联订单表',
    customer_unique_id STRING COMMENT '统一用户 ID - 候选主键但存在重复',
    customer_zip_code_prefix INT COMMENT '邮编前缀 - 可关联地理位置表',
    customer_city STRING COMMENT '客户城市 - 地区分析字段',
    customer_state STRING COMMENT '客户州/省 - 地区分析字段'
)
COMMENT '客户维度表 - 保存所有客户的基本属性'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ods/olist/customers'
TBLPROPERTIES (
    "skip.header.line.count"="1",
    "field.delim"=","
);

-- ============================================================================
-- 5. ODS_PRODUCTS - 商品维度表
-- ============================================================================
DROP TABLE IF EXISTS ods_products;
CREATE EXTERNAL TABLE IF NOT EXISTS ods_products (
    product_id STRING COMMENT '商品 ID - 主键',
    product_category_name STRING COMMENT '商品类目名称 (葡语)',
    product_name_lenght DOUBLE COMMENT '商品名称长度',
    product_description_lenght DOUBLE COMMENT '商品描述长度',
    product_photos_qty DOUBLE COMMENT '商品图片数量',
    product_weight_g DOUBLE COMMENT '商品重量(克)',
    product_length_cm DOUBLE COMMENT '商品长度(厘米)',
    product_height_cm DOUBLE COMMENT '商品高度(厘米)',
    product_width_cm DOUBLE COMMENT '商品宽度(厘米)'
)
COMMENT '商品维度表 - 保存所有商品的属性信息'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ods/olist/products'
TBLPROPERTIES (
    "skip.header.line.count"="1",
    "field.delim"=","
);

-- ============================================================================
-- 6. ODS_SELLERS - 卖家维度表
-- ============================================================================
DROP TABLE IF EXISTS ods_sellers;
CREATE EXTERNAL TABLE IF NOT EXISTS ods_sellers (
    seller_id STRING COMMENT '卖家 ID - 主键，关联订单明细表',
    seller_zip_code_prefix INT COMMENT '邮编前缀 - 可关联地理位置表',
    seller_city STRING COMMENT '卖家城市 - 地区分析字段',
    seller_state STRING COMMENT '卖家州/省 - 地区分析字段'
)
COMMENT '卖家维度表 - 保存所有卖家的基本属性'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ods/olist/sellers'
TBLPROPERTIES (
    "skip.header.line.count"="1",
    "field.delim"=","
);
-- ============================================================================
-- 7. ODS_ORDER_REVIEWS - 订单评价表
-- ============================================================================
DROP TABLE IF EXISTS ods_order_reviews;
CREATE EXTERNAL TABLE IF NOT EXISTS ods_order_reviews (
    review_id STRING COMMENT '评价 ID - 主键',
    order_id STRING COMMENT '订单 ID - 外键，关联订单表',
    review_score INT COMMENT '评分 (1-5 分)',
    review_comment_title STRING COMMENT '评论标题 - 可为空',
    review_comment_message STRING COMMENT '评论内容 - 可为空',
    review_creation_date STRING COMMENT '评论创建时间',
    review_answer_timestamp STRING COMMENT '评论答复时间'
)
COMMENT '订单评价表 - 保存订单评价信息'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ods/olist/order_reviews'
TBLPROPERTIES (
    "skip.header.line.count"="1",
    "field.delim"=","
);
-- ============================================================================
-- 8. ODS_GEOLOCATION - 地理位置表
-- ============================================================================
DROP TABLE IF EXISTS ods_geolocation;
CREATE EXTERNAL TABLE IF NOT EXISTS ods_geolocation (
    geolocation_zip_code_prefix INT COMMENT '邮编前缀 - 与客户/卖家邮编关联',
    geolocation_lat DOUBLE COMMENT '纬度 - 地图分析字段',
    geolocation_lng DOUBLE COMMENT '经度 - 地图分析字段',
    geolocation_city STRING COMMENT '城市 - 可能有大小写/拼写差异',
    geolocation_state STRING COMMENT '州/省 - 地区字段'
)
COMMENT '地理位置表 - 邮编与经纬度映射，用于地区扩展分析'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ods/olist/geolocation'
TBLPROPERTIES (
    "skip.header.line.count"="1",
    "field.delim"=","
);
-- ============================================================================
-- 9. ODS_CATEGORY_TRANSLATION - 商品类目翻译表
-- ============================================================================
DROP TABLE IF EXISTS ods_category_translation;
CREATE EXTERNAL TABLE IF NOT EXISTS ods_category_translation (
    product_category_name STRING COMMENT '葡语商品类目名 - 主键，关联商品表',
    product_category_name_english STRING COMMENT '英文类目名 - 翻译映射'
)
COMMENT '商品类目翻译表 - 葡语类目与英文类目映射'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/dw/ods/olist/category_translation'
TBLPROPERTIES (
    "skip.header.line.count"="1",
    "field.delim"=","
);

-- ============================================================================
-- ODS 层创建完成
-- ============================================================================
-- 查看已创建的表
SHOW TABLES;

-- 查看表结构（示例）
-- DESC ods_orders;
-- DESC ods_order_items;
-- DESC ods_order_payments;
-- DESC ods_customers;
-- DESC ods_products;
