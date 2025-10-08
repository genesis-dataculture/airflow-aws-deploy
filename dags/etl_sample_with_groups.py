from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.utils.task_group import TaskGroup
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
from airflow.operators.python import get_current_context
from datetime import datetime, timedelta
import pandas as pd
import mysql.connector
import io
import logging, traceback, inspect

# ===========================================================
# CONFIGURAÇÕES GERAIS
# ===========================================================
BUCKET_NAME = "ons-dev-dg-00-stage"
S3_PREFIX = "airflow-outputs/world_etl"
BRONZE_PATH = f"{S3_PREFIX}/bronze"
SILVER_PATH = f"{S3_PREFIX}/silver"
GOLD_PATH = f"{S3_PREFIX}/gold"

# ===========================================================
# DECORATOR DE LOG E ERRO
# ===========================================================
def log_and_reraise(fn):
    sig = inspect.signature(fn)

    def _wrap(*args, **kwargs):
        try:
            if any(p.kind == inspect.Parameter.VAR_KEYWORD for p in sig.parameters.values()):
                return fn(*args, **kwargs)
            allowed = set(sig.parameters.keys())
            fkwargs = {k: v for k, v in kwargs.items() if k in allowed}
            return fn(*args, **fkwargs)
        except Exception:
            logging.error("Task error:\n%s", traceback.format_exc())
            raise
    return _wrap

# ===========================================================
# ETL DE CIDADES
# ===========================================================
@log_and_reraise
def extract_city():
    """Extrai dados brutos de cidades e grava em Bronze"""
    ctx = get_current_context()
    run_date = ctx["ds"]

    conn = mysql.connector.connect(
        host="relational.fit.cvut.cz",
        user="guest",
        password="relational",
        database="world",
    )
    df = pd.read_sql("SELECT ID, Name, CountryCode, Population FROM city", conn)
    conn.close()

    hook = S3Hook(aws_conn_id="aws_default")
    key = f"{BRONZE_PATH}/city_raw_{run_date}.csv"
    hook.load_string(df.to_csv(index=False), BUCKET_NAME, key, replace=True)
    print(f"[City Extract] Saved to s3://{BUCKET_NAME}/{key} ({len(df)} rows)")

@log_and_reraise
def transform_city():
    """Lê Bronze e gera Silver"""
    ctx = get_current_context()
    run_date = ctx["ds"]

    hook = S3Hook(aws_conn_id="aws_default")
    raw_key = f"{BRONZE_PATH}/city_raw_{run_date}.csv"
    csv_data = hook.read_key(raw_key, BUCKET_NAME)
    df = pd.read_csv(io.StringIO(csv_data))
    df_filtered = df[df["Population"] > 1_000_000].copy()

    silver_key = f"{SILVER_PATH}/city_filtered_{run_date}.csv"
    hook.load_string(df_filtered.to_csv(index=False), BUCKET_NAME, silver_key, replace=True)
    print(f"[City Transform] Saved to s3://{BUCKET_NAME}/{silver_key} ({len(df_filtered)} rows)")

@log_and_reraise
def load_city():
    """Lê Silver e gera Gold (exemplo: adiciona ranking de população)"""
    ctx = get_current_context()
    run_date = ctx["ds"]

    hook = S3Hook(aws_conn_id="aws_default")
    silver_key = f"{SILVER_PATH}/city_filtered_{run_date}.csv"
    df = pd.read_csv(io.StringIO(hook.read_key(silver_key, BUCKET_NAME)))

    df["pop_rank"] = df["Population"].rank(ascending=False).astype(int)
    gold_key = f"{GOLD_PATH}/city_gold_{run_date}.csv"
    hook.load_string(df.to_csv(index=False), BUCKET_NAME, gold_key, replace=True)
    print(f"[City Load] Saved to s3://{BUCKET_NAME}/{gold_key}")

# ===========================================================
# ETL DE PAÍSES
# ===========================================================
@log_and_reraise
def extract_country():
    """Extrai países brutos e grava em Bronze"""
    ctx = get_current_context()
    run_date = ctx["ds"]

    conn = mysql.connector.connect(
        host="relational.fit.cvut.cz",
        user="guest",
        password="relational",
        database="world",
    )
    df = pd.read_sql("SELECT Code, Name, Continent, Population, LifeExpectancy FROM country", conn)
    conn.close()

    hook = S3Hook(aws_conn_id="aws_default")
    key = f"{BRONZE_PATH}/country_raw_{run_date}.csv"
    hook.load_string(df.to_csv(index=False), BUCKET_NAME, key, replace=True)
    print(f"[Country Extract] Saved to s3://{BUCKET_NAME}/{key} ({len(df)} rows)")

@log_and_reraise
def transform_country():
    """Lê Bronze e gera Silver"""
    ctx = get_current_context()
    run_date = ctx["ds"]

    hook = S3Hook(aws_conn_id="aws_default")
    raw_key = f"{BRONZE_PATH}/country_raw_{run_date}.csv"
    csv_data = hook.read_key(raw_key, BUCKET_NAME)
    df = pd.read_csv(io.StringIO(csv_data))
    df_filtered = df[df["Population"] > 50_000_000].copy()

    silver_key = f"{SILVER_PATH}/country_filtered_{run_date}.csv"
    hook.load_string(df_filtered.to_csv(index=False), BUCKET_NAME, silver_key, replace=True)
    print(f"[Country Transform] Saved to s3://{BUCKET_NAME}/{silver_key} ({len(df_filtered)} rows)")

@log_and_reraise
def load_country():
    """Lê Silver e gera Gold"""
    ctx = get_current_context()
    run_date = ctx["ds"]

    hook = S3Hook(aws_conn_id="aws_default")
    silver_key = f"{SILVER_PATH}/country_filtered_{run_date}.csv"
    df = pd.read_csv(io.StringIO(hook.read_key(silver_key, BUCKET_NAME)))

    df["pop_density_est"] = df["Population"] / 1_000_000
    gold_key = f"{GOLD_PATH}/country_gold_{run_date}.csv"
    hook.load_string(df.to_csv(index=False), BUCKET_NAME, gold_key, replace=True)
    print(f"[Country Load] Saved to s3://{BUCKET_NAME}/{gold_key}")

# ===========================================================
#  CONSOLIDAÇÃO FINAL (GOLD)
# ===========================================================
@log_and_reraise
def consolidate():
    """Lê os arquivos Gold e gera resumo final"""
    ctx = get_current_context()
    run_date = ctx["ds"]
    hook = S3Hook(aws_conn_id="aws_default")

    city_key = f"{GOLD_PATH}/city_gold_{run_date}.csv"
    country_key = f"{GOLD_PATH}/country_gold_{run_date}.csv"

    df_city = pd.read_csv(io.StringIO(hook.read_key(city_key, BUCKET_NAME)))
    df_country = pd.read_csv(io.StringIO(hook.read_key(country_key, BUCKET_NAME)))

    summary = {
        "total_cities": len(df_city),
        "total_countries": len(df_country),
        "avg_city_population": round(df_city["Population"].mean(), 2),
        "avg_country_population": round(df_country["Population"].mean(), 2),
    }

    # grava JSON resumo no bucket
    summary_key = f"{GOLD_PATH}/summary_{run_date}.json"
    hook.load_string(str(summary), BUCKET_NAME, summary_key, replace=True)
    print(f"[Consolidation] Summary saved to s3://{BUCKET_NAME}/{summary_key}\n{summary}")

# ===========================================================
#  DAG
# ===========================================================
default_args = {
    "owner": "fabio.franco",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=3),
}

with DAG(
    dag_id="etl_public_mysql_medallion_s3",
    default_args=default_args,
    description="ETL público MySQL com arquitetura Medallion no S3",
    schedule_interval="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["mysql", "s3", "medallion", "bronze", "silver", "gold"],
) as dag:

    # Grupo Cidades
    with TaskGroup("etl_city", tooltip="Pipeline de Cidades") as etl_city:
        t1 = PythonOperator(task_id="extract_city", python_callable=extract_city)
        t2 = PythonOperator(task_id="transform_city", python_callable=transform_city)
        t3 = PythonOperator(task_id="load_city", python_callable=load_city)
        t1 >> t2 >> t3

    # Grupo Países
    with TaskGroup("etl_country", tooltip="Pipeline de Países") as etl_country:
        t4 = PythonOperator(task_id="extract_country", python_callable=extract_country)
        t5 = PythonOperator(task_id="transform_country", python_callable=transform_country)
        t6 = PythonOperator(task_id="load_country", python_callable=load_country)
        t4 >> t5 >> t6

    # Consolidação Final
    t7 = PythonOperator(task_id="consolidate", python_callable=consolidate)

    [etl_city, etl_country] >> t7
