"""
加载原始数据到 ODS (原始数据层)

说明：
1. 本脚本将 CSV 文件从本地复制到 HDFS 的 ODS 目录
2. 然后在 Hive 中创建 EXTERNAL 表指向这些文件
3. 不进行任何数据清洗和转换

使用方式：
1. 方式一 (推荐)：在 Hive 中直接执行 SQL：
   $ beeline -u jdbc:hive2://localhost:10000 -f sql/ods_olist.sql
   
   然后在 Hive 中执行 MSCK REPAIR TABLE 来加载数据（可选）：
   $ beeline -u jdbc:hive2://localhost:10000
   > MSCK REPAIR TABLE ods_orders;
   > MSCK REPAIR TABLE ods_order_items;
   > ...

2. 方式二：Python + Spark 方式加载
   $ python src/load_to_ods.py
"""

import os
import sys
import logging
from pathlib import Path
import subprocess
import pandas as pd

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 定义常量
PROJECT_ROOT = Path(__file__).parent.parent
DATA_RAW_DIR = PROJECT_ROOT / 'data' / 'raw' / 'public' / 'olist'
HDFS_ODS_BASE = '/dw/ods/olist'

# ODS 表配置
ODS_TABLES = {
    'ods_orders': {
        'file': 'olist_orders_dataset.csv',
        'hdfs_path': f'{HDFS_ODS_BASE}/orders'
    },
    'ods_order_items': {
        'file': 'olist_order_items_dataset.csv',
        'hdfs_path': f'{HDFS_ODS_BASE}/order_items'
    },
    'ods_order_payments': {
        'file': 'olist_order_payments_dataset.csv',
        'hdfs_path': f'{HDFS_ODS_BASE}/order_payments'
    },
    'ods_customers': {
        'file': 'olist_customers_dataset.csv',
        'hdfs_path': f'{HDFS_ODS_BASE}/customers'
    },
    'ods_products': {
        'file': 'olist_products_dataset.csv',
        'hdfs_path': f'{HDFS_ODS_BASE}/products'
    }
}

# Hadoop/HDFS 相关配置
NAMENODE_HOST = os.environ.get('NAMENODE_HOST', 'namenode')
NAMENODE_PORT = os.environ.get('NAMENODE_PORT', '9000')
HDFS_URL = f'hdfs://{NAMENODE_HOST}:{NAMENODE_PORT}'


def run_hdfs_command(command):
    """执行 HDFS 命令"""
    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            check=True
        )
        logger.info(f"✅ {command}")
        if result.stdout:
            logger.debug(result.stdout)
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"❌ 命令执行失败: {command}")
        logger.error(f"错误信息: {e.stderr}")
        return False


def hdfs_mkdir(path):
    """在 HDFS 中创建目录"""
    cmd = f'hdfs dfs -mkdir -p {path}'
    return run_hdfs_command(cmd)


def hdfs_put(local_file, hdfs_path):
    """上传文件到 HDFS"""
    cmd = f'hdfs dfs -put -f {local_file} {hdfs_path}'
    return run_hdfs_command(cmd)


def hdfs_ls(path):
    """列出 HDFS 目录内容"""
    cmd = f'hdfs dfs -ls {path}'
    return run_hdfs_command(cmd)


def load_ods_data_via_hdfs():
    """
    方法 1: 通过 HDFS 命令加载数据
    要求在 Hadoop namenode 容器内执行，或配置好跨网络的 HDFS 客户端
    """
    logger.info("=" * 80)
    logger.info("方法 1: 通过 HDFS 命令加载数据到 ODS")
    logger.info("=" * 80)

    # 创建 HDFS ODS 基础目录
    logger.info(f"\n1️⃣ 创建 HDFS ODS 基础目录: {HDFS_ODS_BASE}")
    hdfs_mkdir(HDFS_ODS_BASE)

    # 加载每个表的数据
    for table_name, config in ODS_TABLES.items():
        logger.info(f"\n📂 处理表: {table_name}")
        local_file = DATA_RAW_DIR / config['file']

        # 检查本地文件是否存在
        if not local_file.exists():
            logger.error(f"❌ 本地文件不存在: {local_file}")
            continue

        logger.info(f"  源文件: {local_file}")
        logger.info(f"  行数: {len(pd.read_csv(local_file))} 行")

        # 创建表的 HDFS 目录
        hdfs_path = config['hdfs_path']
        logger.info(f"  HDFS 目标: {hdfs_path}")
        hdfs_mkdir(hdfs_path)

        # 上传文件到 HDFS
        logger.info(f"  正在上传文件到 HDFS...")
        if hdfs_put(str(local_file), hdfs_path):
            logger.info(f"  ✅ 上传成功")
            # 验证文件
            hdfs_ls(hdfs_path)
        else:
            logger.error(f"  ❌ 上传失败")


def print_manual_instructions():
    """打印手动执行指南"""
    logger.info("\n" + "=" * 80)
    logger.info("📋 ODS 加载步骤（手动执行指南）")
    logger.info("=" * 80)

    instructions = """
步骤 1: 进入 Hadoop namenode 容器
--------
$ docker exec -it dw_namenode bash

步骤 2: 创建 HDFS ODS 目录
--------
$ hdfs dfs -mkdir -p /dw/ods/olist/orders
$ hdfs dfs -mkdir -p /dw/ods/olist/order_items
$ hdfs dfs -mkdir -p /dw/ods/olist/order_payments
$ hdfs dfs -mkdir -p /dw/ods/olist/customers
$ hdfs dfs -mkdir -p /dw/ods/olist/products

步骤 3: 上传文件到 HDFS (在 namenode 容器内)
--------
# 如果需要从容器外部复制文件，先在本地执行：
$ docker cp data/raw/public/olist/olist_orders_dataset.csv dw_namenode:/tmp/
$ docker cp data/raw/public/olist/olist_order_items_dataset.csv dw_namenode:/tmp/
$ docker cp data/raw/public/olist/olist_order_payments_dataset.csv dw_namenode:/tmp/
$ docker cp data/raw/public/olist/olist_customers_dataset.csv dw_namenode:/tmp/
$ docker cp data/raw/public/olist/olist_products_dataset.csv dw_namenode:/tmp/

然后在 namenode 容器内执行：
$ hdfs dfs -put -f /tmp/olist_orders_dataset.csv /dw/ods/olist/orders/
$ hdfs dfs -put -f /tmp/olist_order_items_dataset.csv /dw/ods/olist/order_items/
$ hdfs dfs -put -f /tmp/olist_order_payments_dataset.csv /dw/ods/olist/order_payments/
$ hdfs dfs -put -f /tmp/olist_customers_dataset.csv /dw/ods/olist/customers/
$ hdfs dfs -put -f /tmp/olist_products_dataset.csv /dw/ods/olist/products/

步骤 4: 验证文件上传成功
--------
$ hdfs dfs -ls -R /dw/ods/olist

步骤 5: 创建 ODS Hive 表（在本地执行）
--------
$ beeline -u jdbc:hive2://localhost:10000 -f sql/ods_olist.sql

步骤 6: 使用 MSCK REPAIR TABLE 同步元数据（可选）
--------
$ beeline -u jdbc:hive2://localhost:10000

> MSCK REPAIR TABLE olist_dw.ods_orders;
> MSCK REPAIR TABLE olist_dw.ods_order_items;
> MSCK REPAIR TABLE olist_dw.ods_order_payments;
> MSCK REPAIR TABLE olist_dw.ods_customers;
> MSCK REPAIR TABLE olist_dw.ods_products;

步骤 7: 验证 ODS 表数据
--------
$ beeline -u jdbc:hive2://localhost:10000

> USE olist_dw;
> SELECT COUNT(*) FROM ods_orders;
> SELECT COUNT(*) FROM ods_order_items;
> SELECT COUNT(*) FROM ods_order_payments;
> SELECT COUNT(*) FROM ods_customers;
> SELECT COUNT(*) FROM ods_products;
> 
> SELECT * FROM ods_orders LIMIT 3;
"""
    logger.info(instructions)


def main():
    """主函数"""
    logger.info("\n" + "=" * 80)
    logger.info("🚀 Olist ODS 数据加载脚本")
    logger.info("=" * 80)

    # 检查环境
    logger.info("\n检查环境:")
    logger.info(f"  项目根目录: {PROJECT_ROOT}")
    logger.info(f"  数据源目录: {DATA_RAW_DIR}")
    logger.info(f"  HDFS 地址: {HDFS_URL}")

    if not DATA_RAW_DIR.exists():
        logger.error(f"❌ 数据源目录不存在: {DATA_RAW_DIR}")
        sys.exit(1)

    # 列出要加载的表
    logger.info(f"\n待加载的 ODS 表:")
    for table_name, config in ODS_TABLES.items():
        local_file = DATA_RAW_DIR / config['file']
        exists = "✅" if local_file.exists() else "❌"
        logger.info(f"  {exists} {table_name:20} <- {config['file']}")

    # 询问用户选择加载方式
    print("\n" + "=" * 80)
    print("请选择加载方式:")
    print("1. 查看手动执行指南（推荐新手）")
    print("2. 通过 HDFS 命令自动加载（需要 Hadoop 环境）")
    print("3. 退出")
    print("=" * 80)

    choice = input("请输入选择 (1-3): ").strip()

    if choice == '1':
        print_manual_instructions()
    elif choice == '2':
        load_ods_data_via_hdfs()
    else:
        logger.info("退出脚本")
        sys.exit(0)


if __name__ == '__main__':
    main()
