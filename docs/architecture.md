# 项目架构与口径说明

## 1. 业务场景

基于 Olist 电商公开数据集，完成离线数仓与经营分析看板全链路：

- 数据分层建模（ODS/DWD/DWS/ADS）
- 可复用 ETL SQL 与 Hive 外部表
- Spark SQL 批处理导出 ADS 报表
- 10 张可视化图表及分析结论，支撑业务解读

## 2. 数仓分层

| 分层 | 职责 | 落地 |
|------|------|------|
| ODS | 原始落地层，保留源数据 | HDFS `/dw/ods/olist/*` + Hive 外部表 |
| DWD | 明细规范层，主键关联、轻度清洗 | `dwd_trade_detail`（粒度 order_id + order_item_id） |
| DWS | 主题汇总层，按维度预聚合 | 6 张：gmv_day、region_day、city_day、payment_type_day、product_sales、user_order_summary |
| ADS | 应用指标层，面向看板与导出 | 10 张表，经 Spark 导出 CSV → 可视化 |

## 3. 主题表与指标

### 3.1 DWS 主题表

| 表名 | 粒度 | 主要指标 |
|------|------|----------|
| dws_gmv_day | dt | gmv、order_cnt |
| dws_region_day | customer_state + dt | gmv、order_cnt |
| dws_city_day | customer_city + state + dt | gmv、order_cnt |
| dws_payment_type_day | payment_type + dt | gmv、order_cnt |
| dws_product_sales | product_id + dt | sales_amount、qty |
| dws_user_order_summary | customer_id | total_amt、order_cnt、first/last_date |

### 3.2 ADS 输出（10 张）

| 表名 | 用途 |
|------|------|
| ads_gmv_trend | 日 GMV 趋势 |
| ads_gmv_month | 月 GMV + 环比 |
| ads_region_sales_rank | 区域 GMV 排行 |
| ads_region_sales_month | 区域月度 GMV 堆叠 |
| ads_city_sales | 城市 GMV 排行 |
| ads_category_topn | 类目 GMV 排行 |
| ads_product_topn | 类目 Top3 商品 |
| ads_payment_dist | 支付方式 GMV 占比 |
| ads_payment_type_month | 支付方式月度占比 |
| ads_order_status_day | 异常订单（canceled/unavailable）监控 |

### 3.3 可视化产出（10 张图）

01 日 GMV 趋势 | 02 月 GMV+环比 | 03 区域排行 | 04 类目排行 | 05 城市排行  
06 支付占比 | 07 类目 Top3 商品 | 08 异常订单监控 | 09 区域月度堆叠 | 10 支付月度占比

## 4. 数据质量检查

- DWD：主键唯一、空值率、金额异常、关联缺失、支付覆盖率
- 见 `sql/dwd_quality_checks.sql`、`sql/dws_olist.sql` 中校验逻辑

## 5. 技术栈与部署

- 环境：Windows + WSL2 + Docker
- 组件：Hadoop（HDFS）、Hive（Metastore + HiveServer2）、Spark
- 语言：SQL（Hive）、Python（PySpark、pandas、matplotlib）
- 脚本：`jobs/spark_ads_job.py`、`src/ads_visualization.ipynb`

## 6. 面试讲解建议

1. **分层价值**：降低耦合、复用中间层、便于治理与口径统一  
2. **Spark 使用**：批量导出 ADS 表为 CSV，支撑可视化；小表场景 Hive 查询更快，大表/复杂聚合 Spark 吞吐更优  
3. **质量保障**：DWD 质量校验 SQL、DWS 指标口径文档、ADS 导出前验证行数
