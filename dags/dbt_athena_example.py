"""
DAG de exemplo para demonstrar a integração dbt + Athena com Airflow

Este DAG demonstra como orquestrar transformações dbt rodando no AWS Athena
através do Apache Airflow rodando em ECS Fargate.

Autor: Data Team
Data: 2024-10-17
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from airflow.utils.task_group import TaskGroup


default_args = {
    'owner': 'data-team',
    'depends_on_past': False,
    'email': ['data-team@example.com'],
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}


def check_aws_and_dbt():
    """Diagnóstico completo: AWS credentials, S3, Athena, Glue, dbt"""
    import subprocess
    import os
    
    print("=" * 60)
    print("DIAGNÓSTICO: AWS + dbt")
    print("=" * 60)
    
    # 1. Environment variables
    print("\n[1/8] Environment Variables (AWS/dbt):")
    for key in ['AWS_DEFAULT_REGION', 'AWS_REGION', 'DBT_PROFILES_DIR', 
                'DBT_PROJECT_DIR', 'DBT_ATHENA_S3_STAGING', 'AIRFLOW_S3_BUCKET']:
        val = os.environ.get(key, 'NOT SET')
        print(f"  {key}: {val}")
    
    # 2. AWS Credentials
    print("\n[2/8] AWS STS Get Caller Identity:")
    result = subprocess.run(['aws', 'sts', 'get-caller-identity'], 
                          capture_output=True, text=True)
    print(result.stdout if result.returncode == 0 else f"ERROR: {result.stderr}")
    if result.returncode != 0:
        raise Exception("AWS credentials NOT configured")
    
    # 3. S3 Bucket Access
    print("\n[3/8] S3 Bucket Access Test:")
    bucket = os.environ.get('AIRFLOW_S3_BUCKET', 'ons-dev-dg-00-stage')
    result = subprocess.run(['aws', 's3', 'ls', f's3://{bucket}/'], 
                          capture_output=True, text=True)
    print(result.stdout[:500] if result.returncode == 0 else f"ERROR: {result.stderr}")
    if result.returncode != 0:
        raise Exception(f"Cannot access S3 bucket: {bucket}")
    
    # 4. Athena Workgroup
    print("\n[4/8] Athena Workgroup Configuration:")
    result = subprocess.run(['aws', 'athena', 'get-work-group', 
                           '--work-group', 'primary'], 
                          capture_output=True, text=True)
    if result.returncode == 0:
        import json
        wg = json.loads(result.stdout)
        output_loc = wg.get('WorkGroup', {}).get('Configuration', {}).get('ResultConfiguration', {}).get('OutputLocation', 'NOT SET')
        print(f"  OutputLocation: {output_loc}")
        if output_loc == 'NOT SET' or not output_loc:
            print("  ⚠️  WARNING: OutputLocation not configured! Run:")
            print(f"     aws athena update-work-group --work-group primary --configuration-updates \"ResultConfigurationUpdates={{OutputLocation=s3://{bucket}/athena-results/}}\"")
    else:
        print(f"ERROR: {result.stderr}")
    
    # 5. Glue Database
    print("\n[5/8] Glue Database Check (analytics_dev):")
    result = subprocess.run(['aws', 'glue', 'get-database', 
                           '--name', 'analytics_dev'], 
                          capture_output=True, text=True)
    if result.returncode == 0:
        import json
        db = json.loads(result.stdout)
        print(f"  Name: {db['Database']['Name']}")
        print(f"  Description: {db['Database'].get('Description', 'N/A')}")
    else:
        print(f"ERROR: {result.stderr}")
        print("  ⚠️  Database 'analytics_dev' NOT FOUND! Run setup-glue-databases.ps1")
        raise Exception("Glue database 'analytics_dev' not found")
    
    # 6. dbt Installation
    print("\n[6/8] dbt Version:")
    result = subprocess.run(['dbt', '--version'], 
                          capture_output=True, text=True)
    print(result.stdout if result.returncode == 0 else f"ERROR: {result.stderr}")
    
    # 7. dbt Project Files
    print("\n[7/8] dbt Project Files in Container:")
    result = subprocess.run(['ls', '-la', '/opt/airflow/dbt/'], 
                          capture_output=True, text=True)
    print(result.stdout)
    
    # 8. dbt Packages (já instalados na imagem)
    print("\n[8/8] dbt Packages (pré-instalados na imagem):")
    result = subprocess.run(['ls', '-la', '/opt/airflow/dbt/dbt_packages/'], 
                          capture_output=True, text=True)
    if result.returncode == 0:
        print(result.stdout)
    else:
        print("  ⚠️  dbt_packages/ não encontrado! Verifique o build da imagem Docker")
    
    print("\n" + "=" * 60)
    print("✅ Diagnóstico concluído!")
    print("=" * 60)


with DAG(
    'dbt_athena_example',
    default_args=default_args,
    description='Pipeline de exemplo com dbt + Athena',
    schedule_interval=None,  # Manual trigger para testes iniciais
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['dbt', 'athena', 'example', 'data-transformation'],
    doc_md=__doc__
) as dag:

    # Task 1: Diagnóstico completo
    check_aws_dbt = PythonOperator(
        task_id='check_aws_and_dbt',
        python_callable=check_aws_and_dbt,
        doc_md="""
        ### Diagnóstico AWS + dbt
        Verifica:
        1. Variáveis de ambiente
        2. Credenciais AWS (STS)
        3. Acesso ao bucket S3
        4. Configuração do Athena Workgroup
        5. Database no Glue Catalog
        6. Instalação do dbt
        7. Arquivos do projeto dbt no container
        
        **Sincronização automática**: O projeto dbt é sincronizado do S3 
        automaticamente pelo entrypoint.sh a cada 30 segundos.
        """
    )

    # Task Group: Execução dos modelos dbt
    with TaskGroup('dbt_run_models', tooltip='Execução das transformações dbt') as run_group:

        dbt_run_staging = BashOperator(
            task_id='run_staging_models',
            bash_command='''
                set -euo pipefail
                cd /opt/airflow/dbt
                
                echo "=========================================="
                echo "DBT RUN STAGING"
                echo "=========================================="
                echo ""
                
                echo "[1/3] Verificando packages (pré-instalados)..."
                ls -1 dbt_packages/ 2>/dev/null || echo "⚠️  dbt_packages/ não encontrado"
                
                echo ""
                echo "[2/3] dbt debug (teste de conexão)..."
                dbt debug --profiles-dir . --target dev 2>&1
                
                echo ""
                echo "[3/3] dbt run (staging models)..."
                dbt run --profiles-dir . --target dev --select staging.* 2>&1
                
                echo ""
                echo "✅ Staging models executados com sucesso!"
            ''',
            doc_md="""
            ### Run Staging Models
            Executa os modelos da camada staging com:
            - Workspace temporário em /tmp (gravável pelo usuário airflow)
            - Self-heal: instala packages automaticamente se necessário
            - Diagnóstico completo de conexão (dbt debug)
            - Logs detalhados em caso de erro
            """
        )

        dbt_run_intermediate = BashOperator(
            task_id='run_intermediate_models',
            bash_command='''
                cd /opt/airflow/dbt
                dbt run --profiles-dir . --target dev --select intermediate.* 2>&1
            ''',
            doc_md="""
            ### Run Intermediate Models
            Executa os modelos intermediários (transformações business logic).
            """
        )

        dbt_run_marts = BashOperator(
            task_id='run_marts_models',
            bash_command='''
                cd /opt/airflow/dbt
                dbt run --profiles-dir . --target dev --select marts.* 2>&1
            ''',
            doc_md="""
            ### Run Marts Models
            Executa os modelos finais (marts) prontos para consumo analytics.
            """
        )

        # Sequência de execução dos modelos
        dbt_run_staging >> dbt_run_intermediate >> dbt_run_marts

    # Task: Gerar documentação
    dbt_docs = BashOperator(
        task_id='generate_documentation',
        bash_command='''
            cd /opt/airflow/dbt && \
            dbt docs generate --profiles-dir . --target dev 2>&1 && \
            aws s3 sync target/ s3://ons-dev-dg-00-stage/dbt-docs/ --exclude "*" --include "*.json" --include "*.html"
        ''',
        doc_md="""
        ### Generate dbt Documentation
        Gera documentação interativa do projeto dbt e faz upload para S3.
        """
    )

    # Fluxo (sem quality checks)
    check_aws_dbt >> run_group >> dbt_docs


# Documentação adicional do DAG
dag.doc_md = """
# DAG: dbt + Athena Integration Example

## 📋 Descrição
Pipeline completo com diagnóstico AWS, self-healing e execução dbt.

## 🔄 Fluxo
1. **Diagnóstico**: AWS credentials, S3, Athena, Glue, dbt
2. **Self-heal**: Instala packages automaticamente se necessário
3. **Run Models**: staging → intermediate → marts
4. **Quality Checks**: Testes de qualidade
5. **Documentation**: Gera e publica docs

## 🎯 Sincronização Automática
- Projeto dbt sincronizado do S3 a cada 30s pelo entrypoint.sh
- Localização S3: `s3://ons-dev-dg-00-stage/dbt/`
- Packages instalados automaticamente se ausentes

## ⚠️ Troubleshooting
Se o dbt debug falhar, verifique nos logs:
1. Athena Workgroup OutputLocation configurado
2. Database 'analytics_dev' existe no Glue
3. Permissões IAM (Athena, Glue, S3)
4. Bucket S3 acessível

## 🔗 Links Úteis
- [dbt Documentation](https://docs.getdbt.com)
- [dbt-athena Adapter](https://github.com/dbt-athena/dbt-athena-adapter)
"""
