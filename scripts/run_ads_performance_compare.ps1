#!/usr/bin/env powershell
<#
.SYNOPSIS
    Hive vs Spark 性能对比（1-2 个 ADS 指标）

.DESCRIPTION
    对 ads_gmv_trend 和 ads_product_topn 分别用 Hive(beeline) 和 Spark(spark-sql) 执行
    全表扫描，记录耗时并写入 performance_report_template.md

.EXAMPLE
    .\run_ads_performance_compare.ps1
#>

param(
    [string]$HiveContainer = "dw_hive_server",
    [string]$SparkContainer = "dw_spark",
    [string]$ProjectRoot = $PSScriptRoot + "\..",
    [int]$Runs = 2
)

$ReportPath = Join-Path $ProjectRoot "docs\performance_report_template.md"

function Measure-HiveQuery {
    param([string]$Sql)
    $tmpFile = [System.IO.Path]::GetTempFileName()
    "USE olist_dw;`n$Sql" | Set-Content $tmpFile -Encoding UTF8
    docker cp $tmpFile "${HiveContainer}:/tmp/perf.sql" 2>$null
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    docker exec $HiveContainer /opt/hive/bin/beeline -u "jdbc:hive2://localhost:10000" -f /tmp/perf.sql -n hive 2>&1 | Out-Null
    $sw.Stop()
    return [math]::Round($sw.Elapsed.TotalSeconds, 2)
}

function Measure-SparkQuery {
    param([string]$Sql)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    docker exec $SparkContainer /opt/spark/bin/spark-sql `
        --master local[2] `
        --conf spark.hadoop.hive.metastore.uris=thrift://hivemetastore:9083 `
        -e $Sql 2>&1 | Out-Null
    $sw.Stop()
    return [math]::Round($sw.Elapsed.TotalSeconds, 2)
}

Write-Host "`n========== Hive vs Spark Performance Comparison ==========" -ForegroundColor Cyan
Write-Host "Metrics: ads_gmv_trend, ads_product_topn" -ForegroundColor Gray
Write-Host "Each metric runs $Runs times, using the median duration`n" -ForegroundColor Gray

$Results = @{}

# ads_gmv_trend
Write-Host "[1/2] ads_gmv_trend" -ForegroundColor Yellow
$hiveTimes = @()
$sparkTimes = @()
for ($i = 0; $i -lt $Runs; $i++) {
    $ht = Measure-HiveQuery "SELECT * FROM ads_gmv_trend;"
    $st = Measure-SparkQuery "SELECT * FROM olist_dw.ads_gmv_trend"
    $hiveTimes += $ht
    $sparkTimes += $st
    Write-Host "  Run $($i+1): Hive=$ht s, Spark=$st s"
}
$Results["gmv_trend"] = @{
    Hive = ($hiveTimes | Sort-Object)[[math]::Floor($Runs/2)]
    Spark = ($sparkTimes | Sort-Object)[[math]::Floor($Runs/2)]
}

# ads_product_topn
Write-Host "`n[2/2] ads_product_topn" -ForegroundColor Yellow
$hiveTimes = @()
$sparkTimes = @()
for ($i = 0; $i -lt $Runs; $i++) {
    $ht = Measure-HiveQuery "SELECT * FROM ads_product_topn;"
    $st = Measure-SparkQuery "SELECT * FROM olist_dw.ads_product_topn"
    $hiveTimes += $ht
    $sparkTimes += $st
    Write-Host "  Run $($i+1): Hive=$ht s, Spark=$st s"
}
$Results["product_topn"] = @{
    Hive = ($hiveTimes | Sort-Object)[[math]::Floor($Runs/2)]
    Spark = ($sparkTimes | Sort-Object)[[math]::Floor($Runs/2)]
}

# 写入报告
$gmvHive = $Results["gmv_trend"].Hive
$gmvSpark = $Results["gmv_trend"].Spark
$prodHive = $Results["product_topn"].Hive
$prodSpark = $Results["product_topn"].Spark

$conclusionGmv = if ($gmvSpark -lt $gmvHive) { "Spark 更优" } else { "Hive 更优" }
$conclusionProd = if ($prodSpark -lt $prodHive) { "Spark 更优" } else { "Hive 更优" }

$reportContent = @"
# Performance Comparison Report (Hive SQL vs Spark SQL)

## 1. Test Background

- Dataset: Olist, about 110k order detail records, ~2 years of data
- Metrics:
  - ads_gmv_trend: daily GMV trend
  - ads_product_topn: top 100 products by sales
- Environment: Docker containers (dw_hive_server, dw_spark)
- Each query is executed $Runs times, the median time is reported.

## 2. Methodology

1. Run the SAME SQL logic on both Hive (beeline) and Spark (spark-sql).
2. SQL form: `SELECT * FROM olist_dw.ads_xxx`.
3. Spark config: `--master local[2]`, connect to Hive Metastore via `thrift://hivemetastore:9083`.

## 3. Results

| Metric                         | Hive SQL (sec) | Spark SQL (sec) | Conclusion      |
| ------------------------------ | -------------- | ----------------| ----------------|
| Daily GMV (ads_gmv_trend)     | $gmvHive       | $gmvSpark       | $conclusionGmv  |
| Product TopN (ads_product_topn) | $prodHive    | $prodSpark      | $conclusionProd |

## 4. Analysis

- Storage format: DWD/DWS/ADS tables are TEXTFILE (row-oriented), not columnar.
- Data volume at ADS layer is relatively small (hundreds to a few thousand rows).
- Spark has JVM startup overhead; for small queries Hive may be faster.
- For larger tables or more complex aggregations, Spark usually has advantages.

## 5. Optimization Suggestions

- Use columnar formats (Parquet/ORC) for DWD/DWS where possible.
- Add partition filters (e.g. by dt) for common queries.
- Tune Spark parameters such as `spark.sql.shuffle.partitions` and executor memory.
"@

Set-Content -Path $ReportPath -Value $reportContent -Encoding UTF8
Write-Host "`n报告已写入: $ReportPath" -ForegroundColor Green
