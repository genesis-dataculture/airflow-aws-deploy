#!/bin/bash

set -e

# Function to handle errors
error_exit() {
    echo "ERRO: $1" >&2
    exit 1
}

# Sincronizar as DAGs do S3 para o diretório local do Airflow
echo "Sincronizando DAGs do S3..."
mkdir -p /opt/airflow/dags

# Check if required environment variables are set
if [ -z "$AIRFLOW_S3_BUCKET" ] || [ -z "$AIRFLOW_S3_DAGS_PATH" ]; then
    echo "AVISO: AIRFLOW_S3_BUCKET ou AIRFLOW_S3_DAGS_PATH não definidos. Pulando sincronização S3."
else
    echo "[LOG] Testando acesso ao S3: aws s3 ls s3://${AIRFLOW_S3_BUCKET}/${AIRFLOW_S3_DAGS_PATH}/"
    if ! aws s3 ls s3://${AIRFLOW_S3_BUCKET}/${AIRFLOW_S3_DAGS_PATH}/; then
        echo "AVISO: Não foi possível acessar S3. Continuando sem sincronização."
    else
        echo "[LOG] Sincronizando DAGs do S3 (inicial): aws s3 sync s3://${AIRFLOW_S3_BUCKET}/${AIRFLOW_S3_DAGS_PATH}/ /opt/airflow/dags/"
        aws s3 sync s3://${AIRFLOW_S3_BUCKET}/${AIRFLOW_S3_DAGS_PATH}/ /opt/airflow/dags/ || echo "AVISO: Falha na sincronização inicial do S3"
        
        echo "[LOG] Configurando sincronização automática de DAGs..."
        (
          while true; do
            echo "[LOG] Sincronizando DAGs do S3 (loop): aws s3 sync s3://${AIRFLOW_S3_BUCKET}/${AIRFLOW_S3_DAGS_PATH}/ /opt/airflow/dags/ --delete"
            if aws s3 sync s3://${AIRFLOW_S3_BUCKET}/${AIRFLOW_S3_DAGS_PATH}/ /opt/airflow/dags/ --delete; then
                echo "DAGs sincronizadas em $(date)"
            else
                echo "AVISO: Falha na sincronização do S3 em $(date)"
            fi
            sleep 30
          done
        ) &
    fi
fi

# Initialize Airflow database if this is the webserver
if [ "$1" = "webserver" ]; then
    echo "Inicializando banco de dados do Airflow..."
    airflow db init || error_exit "Falha ao inicializar o banco de dados"
    
    # Create admin user if it doesn't exist
    echo "Verificando usuário admin..."
    if ! airflow users list | grep -q "admin"; then
        echo "Criando usuário admin..."
        airflow users create \
            --username admin \
            --firstname Admin \
            --lastname User \
            --role Admin \
            --email admin@airflow.local \
            --password admin || echo "AVISO: Falha ao criar usuário admin"
    fi
fi

# Iniciar o Airflow com o comando passado
echo "Iniciando o Airflow..."
exec /usr/bin/dumb-init -- /home/airflow/.local/bin/airflow "$@"