# DWD 层设计说明

本文档说明 DWD 交易明细宽表 `dwd_trade_detail` 的字段口径、粒度与数据来源。

---

## 1. 表概览

| 属性 | 说明 |
|------|------|
| 表名 | dwd_trade_detail |
| 粒度 | 一行 = 一个订单商品明细（order_id + order_item_id） |
| 数据库 | olist_dw |
| 存储路径 | hdfs://namenode:9000/dw/dwd/olist/trade_detail |
| 分隔符 | TAB (\t) |

---

## 2. 字段清单与口径

| 字段名 | 类型 | 来源 | 口径说明 |
|--------|------|------|----------|
| order_id | STRING | ods_orders | 订单ID，主键之一 |
| customer_id | STRING | ods_orders | 客户ID，关联客户维度 |
| order_status | STRING | ods_orders | 订单状态（delivered/shipped/canceled 等） |
| order_purchase_timestamp | STRING | ods_orders | 下单时间，原始格式 |
| order_purchase_date | STRING | 衍生 | 下单日期，substr(timestamp, 1, 10) |
| order_item_id | INT | ods_order_items | 订单内商品序号，主键之一 |
| product_id | STRING | ods_order_items | 商品ID |
| seller_id | STRING | ods_order_items | 卖家ID |
| price | DECIMAL(10,2) | ods_order_items | 商品价格，空值兜底为 0 |
| freight_value | DECIMAL(10,2) | ods_order_items | 运费，空值兜底为 0 |
| item_total_amount | DECIMAL(10,2) | 衍生 | 商品+运费小计，price + freight_value |
| payment_type | STRING | ods_order_payments | 支付类型，一单多支付时取第一笔 |
| payment_value_sum | DECIMAL(12,2) | ods_order_payments | 订单支付总额，按 order_id 聚合 sum |
| customer_city | STRING | ods_customers | 客户城市 |
| customer_state | STRING | ods_customers | 客户州/省 |
| product_category_name | STRING | ods_products | 商品类目（葡语） |
| product_category_name_english | STRING | ods_category_translation | 商品类目（英文），LEFT JOIN 可空 |
| product_weight_g | DOUBLE | ods_products | 商品重量（克） |
| etl_date | STRING | 衍生 | 跑批日期，current_date |

---

## 3. 数据流

```
ods_order_items (事实基表)
    INNER JOIN ods_orders ON order_id
    LEFT JOIN (ods_order_payments 按 order_id 聚合) ON order_id
    LEFT JOIN ods_customers ON customer_id
    LEFT JOIN ods_products ON product_id
    LEFT JOIN ods_category_translation ON product_category_name
    --> dwd_trade_detail
```

---

![ODS到DWD数据流图](D:\HeJiaqian\job_analysis\作品集\Day3\ODS到DWD数据流图.png)

## 4. 清洗规则

| 规则 | 实现 |
|------|------|
| 关键主键非空 | WHERE order_id/product_id/customer_id IS NOT NULL |
| 金额兜底 | COALESCE(price, 0), COALESCE(freight_value, 0) |
| 支付聚合 | 先 GROUP BY order_id，取 sum(payment_value)、第一笔 payment_type |

---

## 5. 依赖 ODS 表

- ods_orders
- ods_order_items
- ods_order_payments
- ods_customers
- ods_products
- ods_category_translation

---

## 6. 数据加载步骤

### 前置条件

- ODS 层 6 张表（含 category_translation）已创建并加载完成
- Docker 容器 `dw_namenode`、`dw_hive_server` 已启动

---

### 步骤 1：确认 ODS 表可查

```bash
docker exec dw_hive_server /opt/hive/bin/beeline -u jdbc:hive2://localhost:10000 -e "
USE olist_dw;
SELECT COUNT(*) FROM ods_orders;
SELECT COUNT(*) FROM ods_order_items;
SELECT COUNT(*) FROM ods_category_translation;
"
```

确认各表有数据后再继续。

---

### 步骤 2：创建 HDFS 目录并授权

DWD 数据由 Hive 写入，需保证目录对 `hive` 用户可写。

```bash
# 创建 DWD 目录
docker exec dw_namenode hdfs dfs -mkdir -p /dw/dwd/olist/trade_detail

# 将目录授予 hive 用户（HiveServer2 以 hive 身份写入）
docker exec dw_namenode hdfs dfs -chown -R hive:hive /dw/dwd/olist

# 验证目录
docker exec dw_namenode hdfs dfs -ls -R /dw/dwd/olist
```

---

### 步骤 3：执行 DWD 建表与清洗入仓

在项目目录 `data_dev_internship_project` 下执行：

```powershell
# 复制 SQL 脚本到 Hive 容器
docker cp sql/dwd_olist.sql dw_hive_server:/tmp/dwd_olist.sql

# 执行 DDL + INSERT（INSERT 可能需 1–2 分钟）
docker exec dw_hive_server /opt/hive/bin/beeline -u jdbc:hive2://localhost:10000 -f /tmp/dwd_olist.sql -n hive
```

---

### 步骤 4：验证 DWD 表

```bash
# 连接 Hive
docker exec -it dw_hive_server /opt/hive/bin/beeline -u jdbc:hive2://localhost:10000

# 切换数据库并查看表
> USE olist_dw;
> SHOW TABLES;

# 查看表结构
> DESC dwd_trade_detail;

# 查看行数（预期约 10 万+）
> SELECT COUNT(*) FROM dwd_trade_detail;

# 抽样数据
> SELECT * FROM dwd_trade_detail LIMIT 10;
```

---

### 步骤 5：执行质量检查（可选）

```bash
docker cp sql/dwd_quality_checks.sql dw_hive_server:/tmp/
docker exec dw_hive_server /opt/hive/bin/beeline -u jdbc:hive2://localhost:10000 -f /tmp/dwd_quality_checks.sql -n hive
```

---

### 常见问题

| 现象 | 原因 | 处理 |
|------|------|------|
| `Permission denied: user=hive, access=WRITE` | HDFS 目录归属 root，hive 无写权限 | 执行 `hdfs dfs -chown -R hive:hive /dw/dwd/olist` |
| INSERT 报错表不存在 | 未切到 olist_dw | 在 SQL 中确认有 `USE olist_dw;` 或 beeline 中先执行 `USE olist_dw;` |
| 行数为 0 | ODS 表无数据或 JOIN 条件过滤掉全部 | 检查 ODS 各表 `COUNT(*)` 及主键/外键是否一致 |
