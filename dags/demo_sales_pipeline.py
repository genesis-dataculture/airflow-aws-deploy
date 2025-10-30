"""
Demo DAG: dbt seed + run (staging/marts) + docs for a small sales dataset

This orchestrates a complete demo using dbt seeds (customers/orders),
transformations in staging and marts, and publishes docs to S3.

Author: Data Team
Date: 2025-10-22
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator


default_args = {
    'owner': 'data-team',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}


def brief_check():
    """Quick sanity check for dbt and seeds presence in the container."""
    import subprocess
    import os
    print("[Env] DBT_PROJECT_DIR:", os.environ.get('DBT_PROJECT_DIR'))
    print("[Env] DBT_PROFILES_DIR:", os.environ.get('DBT_PROFILES_DIR'))
    subprocess.run(['dbt', '--version'], check=False)
    print("Listing /opt/airflow/dbt/seeds:")
    subprocess.run(['ls', '-la', '/opt/airflow/dbt/seeds'], check=False)


with DAG(
    'demo_sales_pipeline',
    default_args=default_args,
    description='Demo: dbt seed + run + docs (Athena)',
    schedule_interval=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['dbt', 'athena', 'demo'],
    doc_md=__doc__,
) as dag:

    check = PythonOperator(
        task_id='check_dbt_and_seeds',
        python_callable=brief_check,
    )

    dbt_seed = BashOperator(
        task_id='dbt_seed',
        bash_command='''
            set -euo pipefail
            cd /opt/airflow/dbt
            echo "=== dbt seed ==="
            dbt seed --profiles-dir . --target dev 2>&1
        ''',
    )

    dbt_run_staging = BashOperator(
        task_id='dbt_run_staging',
        bash_command='''
            set -euo pipefail
            cd /opt/airflow/dbt
            echo "=== dbt run (staging) ==="
            dbt run --profiles-dir . --target dev --select staging.* 2>&1
        ''',
    )

    dbt_run_marts = BashOperator(
        task_id='dbt_run_marts',
        bash_command='''
            set -euo pipefail
            cd /opt/airflow/dbt
            echo "=== dbt run (marts) ==="
            dbt run --profiles-dir . --target dev --select marts.fct_orders_summary 2>&1
        ''',
    )

    dbt_docs = BashOperator(
        task_id='dbt_docs',
        bash_command='''
            set -euo pipefail
            cd /opt/airflow/dbt
            echo "=== dbt docs generate ==="
            dbt docs generate --profiles-dir . --target dev 2>&1
            echo "=== sync docs to S3 ==="
            aws s3 sync target/ s3://ons-dev-dg-00-stage/dbt-docs/ --exclude "*" --include "*.json" --include "*.html"
        ''',
    )

    check >> dbt_seed >> dbt_run_staging >> dbt_run_marts >> dbt_docs
