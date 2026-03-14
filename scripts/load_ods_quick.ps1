#!/usr/bin/env powershell

<#
.SYNOPSIS
    快速加载 Olist 数据到 ODS 的 PowerShell 脚本

.DESCRIPTION
    自动化执行以下步骤：
    1. 将 CSV 文件复制到 Hadoop namenode 容器
    2. 在容器内上传文件到 HDFS
    3. 在 Hive 中创建 ODS 表
    4. 验证数据加载结果

.PARAMETER NamenodeContainer
    Namenode 容器名称，默认为 'dw_namenode'

.PARAMETER HiveContainer
    Hive 容器名称，默认为 'dw_hive_server'

.PARAMETER HivePort
    Hive 服务端口，默认为 10000

.EXAMPLE
    .\load_ods_quick.ps1
    .\load_ods_quick.ps1 -NamenodeContainer dw_namenode -HiveContainer dw_hive_server -HivePort 10000

.NOTES
    要求：
    - Docker 已安装并运行
    - Hadoop (namenode) 和 Hive (hiveserver2) 容器已启动
    - 需在项目根目录或 scripts 目录下执行
#>

param(
    [string]$NamenodeContainer = "dw_namenode",
    [string]$HiveContainer = "dw_hive_server",
    [int]$HivePort = 10000
)

# 颜色输出
function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️ $Message" -ForegroundColor Cyan
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️ $Message" -ForegroundColor Yellow
}

# 获取项目根目录
$ProjectRoot = (Get-Location).Path
if (-not (Test-Path "data_dev_internship_project\sql\ods_olist.sql")) {
    # 尝试上级目录
    if (Test-Path "..\data_dev_internship_project\sql\ods_olist.sql") {
        $ProjectRoot = (Get-Item "..").FullName
    } else {
        Write-Error "无法找到项目根目录，请确保在正确的位置执行脚本"
        exit 1
    }
}

$DataDir = "$ProjectRoot\data_dev_internship_project\data\raw\public\olist"
$SqlDir = "$ProjectRoot\data_dev_internship_project\sql"

Write-Info "========================================="
Write-Info "Olist ODS 快速加载脚本"
Write-Info "========================================="
Write-Info "项目根目录: $ProjectRoot"
Write-Info "数据目录: $DataDir"
Write-Info "Namenode 容器: $NamenodeContainer | Hive 容器: $HiveContainer"
Write-Info ""

# 检查环境
Write-Info "1️⃣ 检查环境..."
if (-not (Test-Path $DataDir)) {
    Write-Error "数据目录不存在: $DataDir"
    exit 1
}
Write-Success "数据目录存在"

# 检查 docker 命令
try {
    $null = docker --version 2>&1
    Write-Success "Docker 可用"
} catch {
    Write-Error "Docker 命令未找到"
    exit 1
}

# 检查 namenode 和 hive-server 容器是否运行
foreach ($c in @($NamenodeContainer, $HiveContainer)) {
    try {
        $containerStatus = docker inspect -f '{{.State.Running}}' $c 2>&1
        if ($containerStatus -eq "true") {
            Write-Success "容器 $c 正在运行"
        } else {
            Write-Error "容器 $c 未运行"
            exit 1
        }
    } catch {
        Write-Error "容器 $c 不存在"
        exit 1
    }
}

# 定义要上传的文件（共 9 张 Olist 表）
$Files = @(
    "olist_orders_dataset.csv",
    "olist_order_items_dataset.csv",
    "olist_order_payments_dataset.csv",
    "olist_customers_dataset.csv",
    "olist_products_dataset.csv",
    "olist_sellers_dataset.csv",
    "olist_order_reviews_dataset.csv",
    "olist_geolocation_dataset.csv",
    "product_category_name_translation.csv"
)

# 映射关系：CSV文件 -> HDFS目标目录
$FileMapping = @{
    "olist_orders_dataset.csv" = "orders"
    "olist_order_items_dataset.csv" = "order_items"
    "olist_order_payments_dataset.csv" = "order_payments"
    "olist_customers_dataset.csv" = "customers"
    "olist_products_dataset.csv" = "products"
    "olist_sellers_dataset.csv" = "sellers"
    "olist_order_reviews_dataset.csv" = "order_reviews"
    "olist_geolocation_dataset.csv" = "geolocation"
    "product_category_name_translation.csv" = "category_translation"
}

Write-Info ""
Write-Info "2️⃣ 将 CSV 文件复制到容器..."

foreach ($file in $Files) {
    $srcPath = "$DataDir\$file"
    if (-not (Test-Path $srcPath)) {
        Write-Warning "文件不存在，跳过: $srcPath"
        continue
    }
    
    Write-Info "  复制: $file"
    try {
        docker cp $srcPath "${NamenodeContainer}:/tmp/" 2>&1 | Out-Null
        Write-Success "  已复制: $file"
    } catch {
        Write-Error "  复制失败: $file"
    }
}

Write-Info ""
Write-Info "3️⃣ 在容器内创建 HDFS 目录..."

# 创建目录
$CreateDirsCmd = @"
hdfs dfs -mkdir -p /dw/ods/olist/orders && `
hdfs dfs -mkdir -p /dw/ods/olist/order_items && `
hdfs dfs -mkdir -p /dw/ods/olist/order_payments && `
hdfs dfs -mkdir -p /dw/ods/olist/customers && `
hdfs dfs -mkdir -p /dw/ods/olist/products && `
hdfs dfs -mkdir -p /dw/ods/olist/sellers && `
hdfs dfs -mkdir -p /dw/ods/olist/order_reviews && `
hdfs dfs -mkdir -p /dw/ods/olist/geolocation && `
hdfs dfs -mkdir -p /dw/ods/olist/category_translation
"@

try {
    docker exec $NamenodeContainer bash -c $CreateDirsCmd 2>&1 | Out-Null
    Write-Success "HDFS 目录创建成功"
} catch {
    Write-Warning "HDFS 目录可能已存在"
}

Write-Info ""
Write-Info "4️⃣ 上传文件到 HDFS..."

foreach ($file in $Files) {
    $targetDir = $FileMapping[$file]
    if ([string]::IsNullOrEmpty($targetDir)) {
        continue
    }
    
    Write-Info "  上传: $file -> /dw/ods/olist/$targetDir/"
    
    $uploadCmd = "hdfs dfs -put -f /tmp/$file /dw/ods/olist/$targetDir/"
    try {
        docker exec $NamenodeContainer bash -c $uploadCmd 2>&1 | Out-Null
        Write-Success "  上传成功: $file"
    } catch {
        Write-Error "  上传失败: $file"
    }
}

Write-Info ""
Write-Info "5️⃣ 验证上传结果..."

$verifyCmd = "hdfs dfs -ls -R /dw/ods/olist"
Write-Info "执行命令: $verifyCmd"
Write-Info ""
docker exec $NamenodeContainer bash -c $verifyCmd

Write-Info ""
Write-Info "6️⃣ 创建 Hive ODS 表..."

$odsSqlFile = "$SqlDir\ods_olist.sql"
if (-not (Test-Path $odsSqlFile)) {
    Write-Error "ODS DDL 文件不存在: $odsSqlFile"
    exit 1
}

Write-Info "执行 SQL 文件: $odsSqlFile"
try {
    # 复制 SQL 到 Hive 容器并在容器内执行 beeline（适配 Windows 无本地 beeline）
    docker cp $odsSqlFile "${HiveContainer}:/tmp/ods_olist.sql" 2>&1 | Out-Null
    docker exec $HiveContainer /opt/hive/bin/beeline -u "jdbc:hive2://localhost:$HivePort" -f /tmp/ods_olist.sql -n hive 2>&1 | ForEach-Object { Write-Host $_ }
    
    Write-Success "ODS 表创建完成"
} catch {
    Write-Error "ODS 表创建失败: $_"
    Write-Warning "请手动执行: docker cp $odsSqlFile ${HiveContainer}:/tmp/ && docker exec $HiveContainer /opt/hive/bin/beeline -u jdbc:hive2://localhost:$HivePort -f /tmp/ods_olist.sql"
}

Write-Info ""
Write-Info "7️⃣ 验证 ODS 数据..."

Write-Info "执行数据验证查询..."
$verifySql = @"
USE olist_dw;
SELECT 'ods_orders' as tbl, COUNT(*) as cnt FROM ods_orders;
SELECT 'ods_order_items' as tbl, COUNT(*) as cnt FROM ods_order_items;
SELECT 'ods_order_payments' as tbl, COUNT(*) as cnt FROM ods_order_payments;
SELECT 'ods_customers' as tbl, COUNT(*) as cnt FROM ods_customers;
SELECT 'ods_products' as tbl, COUNT(*) as cnt FROM ods_products;
SELECT 'ods_sellers' as tbl, COUNT(*) as cnt FROM ods_sellers;
SELECT 'ods_order_reviews' as tbl, COUNT(*) as cnt FROM ods_order_reviews;
SELECT 'ods_geolocation' as tbl, COUNT(*) as cnt FROM ods_geolocation;
SELECT 'ods_category_translation' as tbl, COUNT(*) as cnt FROM ods_category_translation;
"@

try {
    # 保存 SQL 到临时文件并复制到容器内执行
    $tmpSqlFile = Join-Path $env:TEMP "ods_verify_$(Get-Random).sql"
    Set-Content -Path $tmpSqlFile -Value $verifySql -Encoding UTF8
    
    docker cp $tmpSqlFile "${HiveContainer}:/tmp/ods_verify.sql" 2>&1 | Out-Null
    docker exec $HiveContainer /opt/hive/bin/beeline -u "jdbc:hive2://localhost:$HivePort" -f /tmp/ods_verify.sql -n hive
    
    Remove-Item $tmpSqlFile -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warning "无法自动验证，请手动执行: docker exec $HiveContainer /opt/hive/bin/beeline -u jdbc:hive2://localhost:$HivePort -e 'USE olist_dw; SHOW TABLES;'"
}

Write-Info ""
Write-Success "========================================="
Write-Success "🎉 ODS 加载完成！"
Write-Success "========================================="
Write-Info ""
Write-Info "下一步操作："
Write-Info "1. 验证 Hive 表数据:"
Write-Info "   docker exec -it $HiveContainer /opt/hive/bin/beeline -u jdbc:hive2://localhost:$HivePort"
Write-Info "   > USE olist_dw;"
Write-Info "   > SHOW TABLES;"
Write-Info "   > SELECT COUNT(*) FROM ods_orders;"
Write-Info ""
Write-Info "2. 继续 DWD 层设计:"
Write-Info "   查看 docs/数仓项目plan.md"
Write-Info ""
