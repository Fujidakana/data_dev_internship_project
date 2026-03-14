- # 性能对比报告（Hive SQL vs Spark SQL）

  ## 1. 测试背景

  - **数据集**：Olist，大约 11 万行订单明细记录，时间跨度约 2 年
  - **指标**：
    - `ads_gmv_trend`：日 GMV 趋势
    - `ads_product_topn`：按销售额排序的 Top 100 商品
  - **环境**：Docker 容器（`dw_hive_server`、`dw_spark`）
  - **执行次数**：每条查询执行 2 次，取中位数作为结果

  ## 2. 测试方法

  1. 在 Hive（beeline）和 Spark（spark-sql）上分别运行**相同的** SQL 逻辑。
  2. SQL 形式：`SELECT * FROM olist_dw.ads_xxx`。
  3. Spark 配置：`--master local[2]`，通过 `thrift://hivemetastore:9083` 连接 Hive Metastore。

  ## 3. 测试结果

  | 指标                          | Hive SQL（秒） | Spark SQL（秒） | 结论      |
  | ----------------------------- | -------------- | --------------- | --------- |
  | 日 GMV（ads_gmv_trend）       | 1.53           | 5               | Hive 更优 |
  | 商品 TopN（ads_product_topn） | 1.15           | 3.96            | Hive 更优 |

  ## 4. 结果分析

  - **存储格式**：DWD/DWS/ADS 表目前均为 TEXTFILE（行式存储），不是列式存储。
  - **ADS 数据量**：属于聚合结果表，行数较少（几百到几千行）。
  - **Spark 启动开销**：Spark 有 JVM 启动与初始化开销，在小数据量、简单查询场景下，Hive 可能更快。
  - **复杂/大数据场景**：对于更大的表或更复杂的聚合逻辑，Spark 通常更有优势。

  ## 5. 优化建议

  - 在可能的情况下，将 DWD/DWS 表改为列式存储格式（如 Parquet/ORC）。
  - 为常用查询增加分区过滤（例如按 `dt` 分区），减少扫描数据量。
  - 调优 Spark 参数，例如 `spark.sql.shuffle.partitions`、executor 内存等设置，以适应不同数据规模。
