#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Olist ADS 报表导出任务

从 Hive 读取 ADS 表，导出为 CSV 格式到指定目录。
支持可配置的数据库、表列表、输出路径。

用法示例：
    spark-submit --master local[2] \\
        --conf spark.hadoop.hive.metastore.uris=thrift://hivemetastore:9083 \\
        spark_ads_job.py --warehouse-db olist_dw --output-dir /tmp/ads_metrics

    spark-submit ... spark_ads_job.py --tables ads_gmv_trend,ads_product_topn
"""

import argparse
import sys
from pathlib import Path

# 默认导出的 ADS 表列表
DEFAULT_ADS_TABLES = [
    "ads_gmv_trend",
    "ads_product_topn",
    "ads_region_sales_rank",
    "ads_order_status_day",
    "ads_gmv_month",
    "ads_region_sales_month",
    "ads_payment_type_month",
    "ads_payment_dist",
    "ads_category_topn",
    "ads_city_sales",
]


def run_export(spark, db: str, tables: list, output_dir: str) -> None:
    """导出指定表到 CSV"""
    output_path = Path(output_dir)
    for table in tables:
        full_table = f"{db}.{table}" if db else table
        try:
            df = spark.table(full_table)
            out = str(output_path / table)
            # coalesce(1) 生成单文件，ADS 表数据量较小
            df.coalesce(1).write.mode("overwrite").option(
                "header", "true"
            ).option("sep", ",").csv(out)
            print(f"[OK] {full_table} -> {out}")
        except Exception as e:
            print(f"[SKIP] {full_table}: {e}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="Olist ADS 报表导出")
    parser.add_argument(
        "--warehouse-db",
        default="olist_dw",
        help="Hive 数据库名 (default: olist_dw)",
    )
    parser.add_argument(
        "--output-dir",
        default="/tmp/ads_metrics",
        help="CSV 输出目录 (default: /tmp/ads_metrics)",
    )
    parser.add_argument(
        "--tables",
        default=",".join(DEFAULT_ADS_TABLES),
        help="要导出的表，逗号分隔 (default: 全部 ADS 表)",
    )
    args = parser.parse_args()

    tables = [t.strip() for t in args.tables.split(",") if t.strip()]
    if not tables:
        tables = DEFAULT_ADS_TABLES

    try:
        from pyspark.sql import SparkSession
    except ImportError:
        print("请使用 spark-submit 运行此脚本", file=sys.stderr)
        sys.exit(1)

    spark = (
        SparkSession.builder.appName("Olist ADS Export")
        .enableHiveSupport()
        .getOrCreate()
    )

    run_export(spark, args.warehouse_db, tables, args.output_dir)
    spark.stop()
    print("Export completed.")


if __name__ == "__main__":
    main()
