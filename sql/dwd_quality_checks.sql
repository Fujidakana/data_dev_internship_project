-- ============================================================================
-- DWD 层数据质量检查 SQL
-- ============================================================================
-- 执行前请先完成 dwd_trade_detail 的建表与入仓
-- 使用方法：在 beeline 中依次执行各段，记录结果并对比预期
-- ============================================================================

USE olist_dw;

-- ============================================================================
-- 1. 行数对比：ODS 明细 vs DWD 明细
-- ============================================================================
-- ODS order_items 行数（去除 order_id/product_id 为空后的理论最大行数）
SELECT 'ods_order_items' AS source, COUNT(*) AS row_count FROM ods_order_items
WHERE order_id IS NOT NULL AND product_id IS NOT NULL;

-- DWD 实际行数（去除 customer_id 为空等过滤后的行数）
SELECT 'dwd_trade_detail' AS source, COUNT(*) AS row_count FROM dwd_trade_detail;

-- 预期：dwd 行数 <= ods_order_items 行数（因 INNER JOIN orders 会过滤掉无订单的明细，且 customer_id 非空过滤）


-- ============================================================================
-- 2. 主键重复：order_id + order_item_id 重复率
-- ============================================================================
-- 重复记录数
SELECT COUNT(*) AS duplicate_count
FROM (
    SELECT order_id, order_item_id, COUNT(*) AS cnt
    FROM dwd_trade_detail
    GROUP BY order_id, order_item_id
    HAVING COUNT(*) > 1
) t;

-- 预期：duplicate_count = 0


-- ============================================================================
-- 3. 关键字段空值率
-- ============================================================================
SELECT
    SUM(CASE WHEN order_id IS NULL OR order_id = '' THEN 1 ELSE 0 END) AS order_id_null_cnt,
    SUM(CASE WHEN customer_id IS NULL OR customer_id = '' THEN 1 ELSE 0 END) AS customer_id_null_cnt,
    SUM(CASE WHEN product_id IS NULL OR product_id = '' THEN 1 ELSE 0 END) AS product_id_null_cnt,
    COUNT(*) AS total_cnt
FROM dwd_trade_detail;

-- 预期：order_id/customer_id/product_id 空值数均为 0


-- ============================================================================
-- 4. 金额异常：price < 0、freight_value < 0
-- ============================================================================
SELECT
    SUM(CASE WHEN price < 0 THEN 1 ELSE 0 END) AS price_negative_cnt,
    SUM(CASE WHEN freight_value < 0 THEN 1 ELSE 0 END) AS freight_negative_cnt
FROM dwd_trade_detail;

-- 预期：均为 0


-- ============================================================================
-- 5. 关联缺失：ODS 明细中有多少无法关联到 DWD
-- ============================================================================
-- 无法关联到订单的 order_items 数量
SELECT COUNT(*) AS items_without_order
FROM ods_order_items oi
LEFT JOIN ods_orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL AND oi.order_id IS NOT NULL;

-- 因 customer_id 为空被过滤的订单明细数（通过 orders 关联）
-- 此检查较复杂，可作为补充


-- ============================================================================
-- 6. 支付覆盖率：有订单明细但无支付信息的比例
-- ============================================================================
SELECT
    SUM(CASE WHEN payment_type IS NULL AND payment_value_sum IS NULL THEN 1 ELSE 0 END) AS no_payment_cnt,
    COUNT(*) AS total_cnt,
    ROUND(100.0 * SUM(CASE WHEN payment_type IS NULL AND payment_value_sum IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS no_payment_pct
FROM dwd_trade_detail;

-- 记录 no_payment_pct，部分订单可能无支付记录（如未完成支付）


-- ============================================================================
-- 7. order_status 分布（业务合理性检查）
-- ============================================================================
SELECT order_status, COUNT(*) AS cnt
FROM dwd_trade_detail
GROUP BY order_status
ORDER BY cnt DESC;
