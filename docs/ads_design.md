# Day5 ADS 应用层与 Spark 作业 - 执行总结

> 依据《一周数据开发求职项目》Day5 计划完成，涵盖 ADS 选表、建表、Spark 导出、性能对比全流程。

---

## 1. ADS 表选取思路

### 1.1 选表原则

- **业务驱动**：围绕 Olist 电商经营分析需求，覆盖 GMV、商品、地区、支付、城市等核心维度
- **数据可用**：基于现有 DWS 与 DWD 字段，避免不可用维度（如 RFM 因无复购而放弃）
- **时间粒度**：日表支撑趋势与明细，月表支撑同比环比与汇报

### 1.2 选表决策与调整

| 原计划表 | 最终决策 | 原因 |
|----------|----------|------|
| ads_funnel_day | **ads_order_status_day** | 数据探索发现 order_status 中 delivered 占比约 98%，漏斗转化意义弱；改为按日监控 unavailable/canceled 等异常状态 |
| ads_rfm_simple | **取消** | Olist 中 order_id 与 customer_id 一一对应，无复购，F 恒为 1，无法做 RFM 分层 |
| — | **ads_gmv_month** 等月表 | 数据覆盖约 2 年，月表更适合同比环比与汇报 |
| — | **ads_payment_dist** / **ads_category_topn** / **ads_city_sales** | 基于数据字典扩展，充分利用 DWS 已有支付、类目、城市维度 |

### 1.3 最终 ADS 表清单（10 张）

| 表名 | 来源 | 粒度/用途 |
|------|------|-----------|
| ads_gmv_trend | dws_gmv_day | 日 GMV 趋势 |
| ads_product_topn | dws_product_sales | Top100 商品销售额 |
| ads_region_sales_rank | dws_region_day | 地区销售排行 |
| ads_order_status_day | dwd_trade_detail | 每日订单状态分布（监控 unavailable/canceled） |
| ads_gmv_month | dws_gmv_day | 月 GMV 趋势 |
| ads_region_sales_month | dws_region_day | 地区月度销售 |
| ads_payment_type_month | dws_payment_type_day | 支付方式月度 |
| ads_payment_dist | dws_payment_type_day | 支付方式占比 |
| ads_category_topn | dws_product_sales | Top50 类目销售 |
| ads_city_sales | dws_city_day | Top100 城市销售 |

### 1.4 DWS 城市扩展

- 新增 **dws_city_day**：粒度 `customer_city + customer_state + order_purchase_date`
- 用于支撑 ads_city_sales（城市级销售排行）

---

## 2. 关键知识点

### 2.1 ADS 分层

- **职责**：面向应用/报表的汇总结果，可直接支撑 BI、看板、导出
- **来源**：以 DWS 为主，少数直接来自 DWD（如 ads_order_status_day）
- **粒度选择**：日表（dt）、月表（substr(dt,1,7)）、排行表（ROW_NUMBER）

### 2.2 Hive 窗口函数

- `ROW_NUMBER() OVER (ORDER BY col DESC)`：用于 TopN 排行
- 嵌套子查询：先按维度聚合，再窗口函数排名，最后 `WHERE rank_num <= N`

### 2.3 Spark 与 Hive 集成

- **spark-submit** 提交 PySpark 脚本，需 `--conf spark.hadoop.hive.metastore.uris=thrift://hivemetastore:9083`
- **enableHiveSupport()**：SparkSession 启用 Hive 支持，可 `spark.table("db.table")` 读取 Hive 表
- **执行环境**：脚本在 `dw_spark` 容器内执行，依赖镜像自带的 PySpark，无需额外 pip 安装

### 2.4 Spark 写 CSV

- `df.write.csv(path)` 默认生成目录及 `part-00000-*.csv` 等分片文件
- `coalesce(1)` 合并为单文件，适用于小表导出
- `option("header", "true")` 输出表头

### 2.5 性能对比结论

- **小表、简单全表扫描**：Hive（beeline）往往更快，因 Spark 有 JVM 冷启动开销
- **大表、复杂聚合**：Spark 通常更有优势
- **优化方向**：列式存储（Parquet/ORC）、分区过滤、Spark 参数调优

---

## 3. 关键执行步骤

### 3.1 前置条件

- Docker 容器已启动：`dw_namenode`、`dw_datanode`、`dw_hive_server`、`hivemetastore`、`dw_spark`
- ODS、DWD 已加载；DWS 需重新执行以包含 `dws_city_day`

### 3.2 一键全流程（推荐）

```powershell
cd data_dev_internship_project\scripts
.\run_ads_full.ps1
```

依次完成：HDFS 目录 → DWS（含 city_day）→ ADS 建表与插入 → Spark 导出 CSV → 性能对比

### 3.3 分步执行

| 步骤 | 命令/操作 |
|------|-----------|
| 1. HDFS 目录 | `docker exec dw_namenode hdfs dfs -mkdir -p /dw/dws/olist/city_day` 及 `/dw/ads/olist/*`，`chown -R hive:hive` |
| 2. DWS | `docker cp sql/dws_olist.sql dw_hive_server:/tmp/`，`beeline -f /tmp/dws_olist.sql` |
| 3. ADS | `docker cp sql/ads_olist.sql dw_hive_server:/tmp/`，`beeline -f /tmp/ads_olist.sql` |
| 4. Spark 导出 | `docker cp jobs/spark_ads_job.py dw_spark:/tmp/`，`spark-submit ... /tmp/spark_ads_job.py --warehouse-db olist_dw --output-dir /tmp/ads_metrics` |
| 5. 复制 CSV | `docker cp dw_spark:/tmp/ads_metrics/. output/ads_metrics/` |
| 6. 性能对比 | `.\scripts\run_ads_performance_compare.ps1` |

---

## 4. 输出与验证

- **CSV 路径**：`output/ads_metrics/`，每张表对应子目录，内含 `part-00000-*.csv`
- **性能报告**：`docs/performance_report_template.md`，记录 Hive vs Spark 对 ads_gmv_trend、ads_product_topn 的查询耗时
- **验证**：`docker exec -it dw_hive_server beeline -u jdbc:hive2://localhost:10000` → `USE olist_dw; SHOW TABLES; SELECT * FROM ads_gmv_trend LIMIT 5;`

---

## 5. 问题与解决

### 5.1 ADS 选表问题

- **漏斗表**：delivered 占比 98%，传统漏斗价值低，改为订单状态日监控表
- **RFM**：数据无复购，无法做频次分层，取消 ads_rfm_simple

### 5.2 城市维度缺失

- **现象**：DWS 仅有 customer_state，无 city 粒度
- **处理**：在 `dws_olist.sql` 中新增 `dws_city_day`，从 DWD 按 customer_city + customer_state + dt 聚合

---

## 6. 执行顺序速查

```
前置：ODS、DWD 已就绪
  ↓
1. dws_olist.sql（含 dws_city_day）
  ↓
2. ads_olist.sql（10 张 ADS 表）
  ↓
3. spark-submit spark_ads_job.py → /tmp/ads_metrics
  ↓
4. docker cp 到宿主机 output/ads_metrics
  ↓
5. run_ads_performance_compare.ps1 → performance_report_template.md
```
