# DWS 层设计说明与指标口径

本文档说明 DWS 汇总层各主题表的粒度、字段定义及指标口径，作为 Day5 ADS 与指标看板的口径基准。

---

## 1. DWS 层概览

| 表名 | 粒度 | 用途 |
|------|------|------|
| dws_gmv_day | order_purchase_date | 日 GMV 趋势 |
| dws_product_sales | product_id + order_purchase_date | Top 商品、类目销售 |
| dws_region_day | customer_state + order_purchase_date | 地区销售排行 |
| dws_payment_type_day | payment_type + order_purchase_date | 支付方式分布 |
| dws_user_order_summary | customer_id | RFM 用户分层 |

**统一过滤规则**：所有销售/GMV 类指标仅统计 `order_status = 'delivered'`（已交付订单），不含已取消、配送中等状态。

---

## 2. 指标口径定义

### 2.1 GMV（Gross Merchandise Volume）

| 项目 | 说明 |
|------|------|
| 含义 | 已交付订单的支付总额 |
| 计算 | 按 order_id 去重后 sum(payment_value_sum) |
| 数据源 | dwd_trade_detail.payment_value_sum（订单级，需去重） |
| 注意 | DWD 中一单多明细，payment_value_sum 重复；DWS 聚合时先按 order_id 取 MAX 再 sum |

### 2.2 订单数（order_cnt）

| 项目 | 说明 |
|------|------|
| 含义 | 已交付订单的数量 |
| 计算 | COUNT(DISTINCT order_id) |
| 注意 | 不以 DWD 明细行数计，避免一单多商品被重复计数 |

### 2.3 客单价（avg_order_amt）

| 项目 | 说明 |
|------|------|
| 含义 | 平均每笔已交付订单的支付金额 |
| 计算 | GMV / 订单数 |
| 公式 | sum(payment_value_sum) / count(distinct order_id) |

### 2.4 销售额（sales_amt，商品维度）

| 项目 | 说明 |
|------|------|
| 含义 | 商品+运费小计之和（item_total_amount） |
| 计算 | sum(item_total_amount)，按 product_id + dt 聚合 |
| 与 GMV 区别 | GMV 为支付金额、订单级去重；商品销售额为商品+运费汇总，按明细累加 |

### 2.5 购买人数（buyer_cnt / customer_cnt）

| 项目 | 说明 |
|------|------|
| 含义 | 去重后的客户数量 |
| 计算 | COUNT(DISTINCT customer_id) |

### 2.6 销售件数（item_qty）

| 项目 | 说明 |
|------|------|
| 含义 | 已销售商品件数（订单明细行数） |
| 计算 | COUNT(*)，按 product_id + dt 聚合时 |

---

## 3. 各表字段与口径

### 3.1 dws_gmv_day

| 字段 | 类型 | 口径 |
|------|------|------|
| dt | STRING | 下单日期，yyyy-MM-dd |
| gmv | DECIMAL(14,2) | 当日已交付订单支付总额 |
| order_cnt | BIGINT | 当日已交付订单数 |
| customer_cnt | BIGINT | 当日下单客户数（去重） |
| avg_order_amt | DECIMAL(12,2) | 客单价 = gmv / order_cnt |

**下游 ADS**：ads_gmv_trend（日 GMV 趋势图）

---

### 3.2 dws_product_sales

| 字段 | 类型 | 口径 |
|------|------|------|
| product_id | STRING | 商品ID |
| product_category_name_english | STRING | 商品类目（英文），空则填 'unknown' |
| dt | STRING | 下单日期 |
| sales_amt | DECIMAL(14,2) | 当日该商品销售额（item_total_amount 之和） |
| order_cnt | BIGINT | 涉及该商品的订单数 |
| item_qty | BIGINT | 销售件数 |
| buyer_cnt | BIGINT | 购买人数（去重 customer_id） |

**下游 ADS**：ads_product_topn（Top 商品销售额排行）

---

### 3.3 dws_region_day

| 字段 | 类型 | 口径 |
|------|------|------|
| customer_state | STRING | 客户所在州/省，空则填 'unknown' |
| dt | STRING | 下单日期 |
| gmv | DECIMAL(14,2) | 当日该地区 GMV |
| order_cnt | BIGINT | 当日该地区订单数 |
| customer_cnt | BIGINT | 当日该地区下单客户数 |

**下游 ADS**：ads_region_sales_rank（地区销售排行）

---

### 3.4 dws_payment_type_day

| 字段 | 类型 | 口径 |
|------|------|------|
| payment_type | STRING | 支付类型（credit_card/boleto/voucher 等），空则填 'unknown' |
| dt | STRING | 下单日期 |
| gmv | DECIMAL(14,2) | 当日该支付方式 GMV |
| order_cnt | BIGINT | 当日该支付方式订单数 |

**下游 ADS**：支付方式分布图

---

### 3.5 dws_user_order_summary

| 字段 | 类型 | 口径 |
|------|------|------|
| customer_id | STRING | 客户ID |
| last_order_date | STRING | 最近一次下单日期（Recency） |
| first_order_date | STRING | 首次下单日期 |
| order_cnt | BIGINT | 累计订单数 |
| total_amt | DECIMAL(14,2) | 累计支付金额（Frequency + Monetary） |

**下游 ADS**：ads_rfm_simple（RFM 简版分层）

---

## 4. DWD → DWS 数据流

```
dwd_trade_detail
    │
    ├─► 按 order_id 去重 payment_value_sum
    │   └─► dws_gmv_day（日聚合）
    │   └─► dws_region_day（地区+日）
    │   └─► dws_payment_type_day（支付方式+日）
    │
    ├─► 按 product_id + dt 聚合 item_total_amount
    │   └─► dws_product_sales
    │
    └─► 按 customer_id 聚合
        └─► dws_user_order_summary
```

---

## 5. 与 ADS 的对应关系

| DWS 表 | ADS 输出 | 说明 |
|--------|----------|------|
| dws_gmv_day | ads_gmv_trend | 按 dt 取 gmv、order_cnt 画趋势 |
| dws_product_sales | ads_product_topn | 按 sales_amt 排序取 TopN |
| dws_region_day | ads_region_sales_rank | 按 gmv 排序得地区排行 |
| dws_payment_type_day | 支付方式分布图 | 按 payment_type 汇总 gmv 占比 |
| dws_user_order_summary | ads_rfm_simple | 基于 last_order_date、order_cnt、total_amt 做 RFM 分层 |

## 6. 数据加载步骤

### 前置条件

- DWD 层 1 张表dwd_trade_detail已创建并加载完成
- Docker 容器 `dw_namenode`、`dw_hive_server` 已启动

---

### 步骤 1：确认 DWD 表可查

```bash
docker exec dw_hive_server /opt/hive/bin/beeline -u jdbc:hive2://localhost:10000 -e "
USE olist_dw;
SELECT COUNT(*) FROM dwd_trade_detail;
"
```

确认各表有数据后再继续。

---

### 步骤 2：创建 HDFS 目录并授权

DWS 数据由 Hive 写入，需保证目录对 `hive` 用户可写。

```bash
# 创建 DWS 目录
docker exec dw_namenode hdfs dfs -mkdir -p /dw/dws/olist/gmv_day
docker exec dw_namenode hdfs dfs -mkdir -p /dw/dws/olist/product_sales
docker exec dw_namenode hdfs dfs -mkdir -p /dw/dws/olist/region_day
docker exec dw_namenode hdfs dfs -mkdir -p /dw/dws/olist/payment_type_day
docker exec dw_namenode hdfs dfs -mkdir -p /dw/dws/olist/user_order_summary


# 将目录授予 hive 用户（HiveServer2 以 hive 身份写入）
docker exec dw_namenode hdfs dfs -chown -R hive:hive /dw/dws/olist
# 验证目录
docker exec dw_namenode hdfs dfs -ls -R /dw/dws/olist
```

---

### 步骤 3：执行 DWS 建表与清洗入仓

在项目目录 `data_dev_internship_project` 下执行：

```powershell
# 复制 SQL 脚本到 Hive 容器
docker cp sql/dws_olist.sql dw_hive_server:/tmp/dws_olist.sql

# 执行 DDL + INSERT（INSERT 可能需 1–2 分钟）
docker exec dw_hive_server /opt/hive/bin/beeline -u jdbc:hive2://localhost:10000 -f /tmp/dws_olist.sql -n hive
```

---

### 步骤 4：验证 DWS 表

```bash
# 连接 Hive
docker exec -it dw_hive_server /opt/hive/bin/beeline -u jdbc:hive2://localhost:10000

# 切换数据库并查看表
> USE olist_dw;
> SHOW TABLES;

# 查看表结构
> DESC dws_gmv_day;
> DESC dws_payment_type_day;
> DESC dws_product_sales;
> DESC dws_region_day;
> DESC dws_user_order_summary;

# 抽样数据
> SELECT * FROM dws_gmv_day LIMIT 10;
```

