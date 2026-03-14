#!/usr/bin/env powershell
<#
.SYNOPSIS
    执行 ADS 全流程：DWS 城市扩展 -> ADS 建表 -> Spark 导出 CSV -> 性能对比

.DESCRIPTION
    1. 创建 HDFS 目录 (dws_city_day + ads)
    2. 执行 dws_olist.sql（含 city_day）
    3. 执行 ads_olist.sql
    4. 运行 Spark 作业导出 CSV
    5. 运行 Hive vs Spark 性能对比

.EXAMPLE
    .\run_ads_full.ps1
#>

param(
    [string]$HiveContainer = "dw_hive_server",
    [string]$NamenodeContainer = "dw_namenode",
    [string]$SparkContainer = "dw_spark",
    [string]$ProjectRoot = $PSScriptRoot + "\.."
)

$SqlDir = Join-Path $ProjectRoot "sql"
$JobsDir = Join-Path $ProjectRoot "jobs"
$OutputDir = Join-Path $ProjectRoot "output\ads_metrics"

function Write-Step { param([string]$M) Write-Host "`n==> $M" -ForegroundColor Cyan }
function Write-Ok { param([string]$M) Write-Host "  OK: $M" -ForegroundColor Green }
function Write-Err { param([string]$M) Write-Host "  ERR: $M" -ForegroundColor Red }

Write-Host "`n========== Olist ADS 全流程 ==========" -ForegroundColor Yellow

# 1. 创建 HDFS 目录
Write-Step "1. 创建 HDFS 目录 (dws_city_day + ads)"
$hdfsDirs = @(
    "/dw/dws/olist/city_day",
    "/dw/ads/olist/gmv_trend",
    "/dw/ads/olist/product_topn",
    "/dw/ads/olist/region_sales_rank",
    "/dw/ads/olist/order_status_day",
    "/dw/ads/olist/gmv_month",
    "/dw/ads/olist/region_sales_month",
    "/dw/ads/olist/payment_type_month",
    "/dw/ads/olist/payment_dist",
    "/dw/ads/olist/category_topn",
    "/dw/ads/olist/city_sales"
)
foreach ($d in $hdfsDirs) {
    docker exec $NamenodeContainer hdfs dfs -mkdir -p $d 2>$null
}
docker exec $NamenodeContainer hdfs dfs -chown -R hive:hive /dw/dws/olist 2>$null
docker exec $NamenodeContainer hdfs dfs -chown -R hive:hive /dw/ads/olist 2>$null
Write-Ok "HDFS 目录就绪"

# 2. 执行 DWS（含 city_day）
Write-Step "2. 执行 dws_olist.sql"
docker cp (Join-Path $SqlDir "dws_olist.sql") "${HiveContainer}:/tmp/"
docker exec $HiveContainer /opt/hive/bin/beeline -u "jdbc:hive2://localhost:10000" -f /tmp/dws_olist.sql -n hive 2>&1 | Out-Null
Write-Ok "DWS 执行完成"

# 3. 执行 ADS
Write-Step "3. 执行 ads_olist.sql"
docker cp (Join-Path $SqlDir "ads_olist.sql") "${HiveContainer}:/tmp/"
docker exec $HiveContainer /opt/hive/bin/beeline -u "jdbc:hive2://localhost:10000" -f /tmp/ads_olist.sql -n hive 2>&1 | Out-Null
Write-Ok "ADS 执行完成"

# 4. Spark 导出 CSV
Write-Step "4. Spark 导出 ADS 到 CSV"
docker cp (Join-Path $JobsDir "spark_ads_job.py") "${SparkContainer}:/tmp/"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
docker exec $SparkContainer /opt/spark/bin/spark-submit `
    --master local[2] `
    --conf spark.hadoop.hive.metastore.uris=thrift://hivemetastore:9083 `
    /tmp/spark_ads_job.py --warehouse-db olist_dw --output-dir /tmp/ads_metrics 2>&1
Write-Ok "Spark 导出完成"

# 5. 复制 CSV 到宿主机
Write-Step "5. 复制 CSV 到宿主机"
docker cp "${SparkContainer}:/tmp/ads_metrics/." $OutputDir 2>$null
Write-Ok "CSV 已保存到 $OutputDir"

# 6. 运行性能对比
Write-Step "6. 运行 Hive vs Spark 性能对比"
$perfScript = Join-Path $ProjectRoot "scripts\run_ads_performance_compare.ps1"
if (Test-Path $perfScript) {
    & $perfScript -HiveContainer $HiveContainer -SparkContainer $SparkContainer
} else {
    Write-Err "性能对比脚本不存在: $perfScript"
}

Write-Host "`n========== 完成 ==========" -ForegroundColor Green
