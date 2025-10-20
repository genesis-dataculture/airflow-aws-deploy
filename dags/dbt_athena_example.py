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


def check_dbt_installation():
    """Verifica se o dbt está instalado corretamente"""
    import subprocess
    
    result = subprocess.run(
        ['dbt', '--version'],
        capture_output=True,
        text=True
    )
    
    print(result.stdout)
    
    if result.returncode != 0:
        raise Exception(f"dbt não está instalado corretamente: {result.stderr}")


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

    # Task 1: Verificar instalação do dbt
    check_dbt = PythonOperator(
        task_id='check_dbt_installation',
        python_callable=check_dbt_installation,
        doc_md="""
        ### Check dbt Installation
        Verifica se o dbt-core e dbt-athena-community estão instalados corretamente
        no container.
        
        **NOTA:** A sincronização do projeto dbt do S3 é feita automaticamente pelo
        entrypoint.sh a cada 30 segundos em background, não sendo necessária uma task
        dedicada para isso.
        
        O comando `dbt run` já valida a conexão e compila os modelos antes de executá-los,
        tornando desnecessárias tasks separadas de setup, debug ou compile.
        """
    )

    # Task Group: Execução dos modelos dbt
    with TaskGroup('dbt_run_models', tooltip='Execução das transformações dbt') as run_group:
        
        dbt_run_staging = BashOperator(
            task_id='run_staging_models',
            # Adicionar 2>&1 para capturar stderr e --debug para mais detalhes
            bash_command='cd /opt/airflow/dbt && dbt run --profiles-dir . --target dev --select staging.* --debug 2>&1',
            doc_md="""
            ### Run Staging Models
            Executa os modelos da camada staging (limpeza e padronização).
            """
        )

        dbt_run_intermediate = BashOperator(
            task_id='run_intermediate_models',
            bash_command='cd /opt/airflow/dbt && dbt run --profiles-dir . --target dev --select intermediate.*',
            doc_md="""
            ### Run Intermediate Models
            Executa os modelos intermediários (transformações business logic).
            """
        )

        dbt_run_marts = BashOperator(
            task_id='run_marts_models',
            bash_command='cd /opt/airflow/dbt && dbt run --profiles-dir . --target dev --select marts.*',
            doc_md="""
            ### Run Marts Models
            Executa os modelos finais (marts) prontos para consumo analytics.
            """
        )

        # Sequência de execução dos modelos
        dbt_run_staging >> dbt_run_intermediate >> dbt_run_marts

    # Task Group: Testes de qualidade
    with TaskGroup('dbt_quality_checks', tooltip='Testes de qualidade dos dados') as quality_group:
        
        dbt_test = BashOperator(
            task_id='run_data_tests',
            bash_command='cd /opt/airflow/dbt && dbt test --profiles-dir . --target dev',
            doc_md="""
            ### Run dbt Tests
            Executa todos os testes de qualidade definidos nos modelos:
            - unique
            - not_null
            - accepted_values
            - relationships
            - custom tests
            """
        )

        dbt_source_freshness = BashOperator(
            task_id='check_source_freshness',
            bash_command='cd /opt/airflow/dbt && dbt source freshness --profiles-dir . --target dev',
            doc_md="""
            ### Check Source Freshness
            Verifica a atualização das tabelas fontes (sources).
            """
        )

        [dbt_test, dbt_source_freshness]

    # Task: Gerar documentação
    dbt_docs = BashOperator(
        task_id='generate_documentation',
        bash_command='''
            cd /opt/airflow/dbt && \
            dbt docs generate --profiles-dir . --target dev && \
            aws s3 sync target/ s3://ons-dev-dg-00-stage/dbt-docs/ --exclude "*" --include "*.json" --include "*.html"
        ''',
        doc_md="""
        ### Generate dbt Documentation
        Gera documentação interativa do projeto dbt e faz upload para S3.
        A documentação pode ser acessada via S3 ou servida localmente com `dbt docs serve`.
        """
    )

    # Definir dependências entre as tasks
    # NOTA: sync_dbt e dbt_setup removidos - sincronização automática pelo entrypoint.sh
    # e validação/compilação feitas automaticamente pelo dbt run
    check_dbt >> run_group >> quality_group >> dbt_docs


# Documentação adicional do DAG
dag.doc_md = """
# DAG: dbt + Athena Integration Example

## 📋 Descrição
Este DAG demonstra a integração completa entre dbt e Athena orquestrado pelo Airflow.

## 🔄 Fluxo de Execução
1. **Check Installation**: Verifica se dbt está instalado
2. **Run Models**: Executa transformações (staging → intermediate → marts)
3. **Quality Checks**: Executa testes de qualidade
4. **Documentation**: Gera e publica documentação

**NOTAS IMPORTANTES:**
- A sincronização do projeto dbt do S3 é feita automaticamente pelo `entrypoint.sh` 
  a cada 30 segundos em background. Isso garante que o código dbt está sempre 
  atualizado sem necessidade de uma task dedicada na DAG.
- O comando `dbt run` já valida conexões e compila modelos antes de executar, 
  eliminando a necessidade de tasks separadas de setup, debug ou compile.

## 🎯 Pré-requisitos
- dbt-core e dbt-athena-community instalados
- Projeto dbt no S3: `s3://ons-dev-dg-00-stage/dbt/`
- AWS Glue Catalog configurado com databases e tables
- IAM Role com permissões: Athena, Glue, S3
- Sincronização automática configurada no entrypoint.sh (a cada 30s)

## 🚀 Como Executar
1. Acesse a UI do Airflow
2. Encontre o DAG `dbt_athena_example`
3. Clique em "Trigger DAG" para execução manual
4. Monitore a execução na Graph View

## 📊 Materializações
- **Staging**: Views (leitura rápida, sem duplicação)
- **Intermediate**: Ephemeral (CTEs, não persistidos)
- **Marts**: Tables (Parquet no S3, otimizado para análise)

## 🔗 Links Úteis
- [dbt Documentation](https://docs.getdbt.com)
- [dbt-athena Adapter](https://github.com/dbt-athena/dbt-athena-adapter)
- [Airflow dbt Provider](https://airflow.apache.org/docs/apache-airflow-providers-dbt-cloud/)
"""
