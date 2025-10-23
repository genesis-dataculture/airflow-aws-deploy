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

# Corrigir permissões do diretório dags
echo "[FIX] Corrigindo permissões de /opt/airflow/dags..."
chown -R airflow:root /opt/airflow/dags 2>/dev/null || echo "[WARNING] Não foi possível corrigir permissões"
chmod -R 775 /opt/airflow/dags 2>/dev/null || echo "[WARNING] Não foi possível ajustar chmod"

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

# Sincronizar projeto dbt do S3 (APENAS CÓDIGO, packages já na imagem)
echo "[LOG] Sincronizando projeto dbt do S3..."
mkdir -p /opt/airflow/dbt

# CORREÇÃO CRÍTICA: Ajustar permissões do diretório dbt
# O diretório foi criado durante o Docker build como root
# Precisa ser acessível pelo usuário airflow (UID 50000)
echo "[FIX] Corrigindo permissões de /opt/airflow/dbt..."
chown -R airflow:root /opt/airflow/dbt 2>/dev/null || echo "[WARNING] Falha ao corrigir permissões (ok se não for root)"
chmod -R 775 /opt/airflow/dbt 2>/dev/null || echo "[WARNING] Falha ao ajustar chmod"

if [ ! -z "$AIRFLOW_S3_BUCKET" ]; then
    echo "[LOG] Testando acesso ao dbt no S3: aws s3 ls s3://${AIRFLOW_S3_BUCKET}/dbt/"
    if aws s3 ls s3://${AIRFLOW_S3_BUCKET}/dbt/ 2>/dev/null; then
        echo "[LOG] Sincronizando projeto dbt (apenas código, excluindo packages)..."
        # IMPORTANTE: --exclude "dbt_packages/*" - não sobrescrever packages da imagem
        # SEM --delete para preservar dbt_packages instalados durante o build
        if aws s3 sync s3://${AIRFLOW_S3_BUCKET}/dbt/ /opt/airflow/dbt/ --exclude "dbt_packages/*"; then
            echo "[SUCCESS] Projeto dbt sincronizado!"
            echo "[INFO] Packages dbt já instalados na imagem - nenhuma instalação necessária"
            
            # Listar packages instalados
            if [ -d "/opt/airflow/dbt/dbt_packages" ]; then
                echo "[INFO] Packages disponíveis na imagem:"
                ls -1 /opt/airflow/dbt/dbt_packages/ 2>/dev/null || echo "Diretório vazio"
            fi
            
            # Configurar sincronização automática de projeto dbt (a cada 30 segundos)
            # SEMPRE excluindo dbt_packages - REMOVIDO --delete para não apagar packages da imagem
            echo "[LOG] Configurando sincronização automática de projeto dbt (a cada 30 segundos)..."
            
            # INSTALAÇÃO INICIAL DE PACKAGES (uma vez, na primeira sincronização)
            if [ ! -d "/opt/airflow/dbt/dbt_packages" ] || [ ! "$(ls -A /opt/airflow/dbt/dbt_packages 2>/dev/null)" ]; then
                echo "[INFO] Instalando dbt packages (primeira execução)..."
                if [ -f "/opt/airflow/dbt/packages.yml" ]; then
                    # Run dbt deps as the airflow user so it uses the user's local python packages
                    cd /opt/airflow/dbt && gosu airflow bash -lc "dbt deps --profiles-dir ." 2>&1 && \
                    echo "[SUCCESS] dbt packages instalados:" && \
                    ls -1 dbt_packages/ 2>/dev/null || echo "[WARNING] Falha ao instalar packages"
                fi
            else
                echo "[INFO] dbt packages já instalados, pulando."
            fi
            
            (
              while true; do
                if aws s3 sync s3://${AIRFLOW_S3_BUCKET}/dbt/ /opt/airflow/dbt/ --exclude "dbt_packages/*" 2>/dev/null; then
                    echo "[SYNC-DBT] Projeto dbt sincronizado em $(date)"
                else
                    echo "[SYNC-DBT] AVISO: Falha na sincronização do projeto dbt em $(date)"
                fi
                sleep 30
              done
            ) &
        else
            echo "AVISO: Falha ao sincronizar projeto dbt do S3"
        fi
    else
        echo "INFO: Diretório dbt/ não encontrado no S3. Pulando sincronização dbt."
    fi
else
    echo "AVISO: AIRFLOW_S3_BUCKET não definido. Pulando sincronização dbt."
fi

# Initialize Airflow database if this is the webserver
if [ "$1" = "webserver" ]; then
    echo "Inicializando banco de dados do Airflow (como usuário airflow)..."
    gosu airflow bash -lc "/home/airflow/.local/bin/airflow db init" || error_exit "Falha ao inicializar o banco de dados"

    # Create admin user if it doesn't exist
    echo "Verificando usuário admin..."
    if ! gosu airflow bash -lc "/home/airflow/.local/bin/airflow users list | grep -qw admin"; then
        echo "Criando usuário admin..."
        gosu airflow bash -lc "/home/airflow/.local/bin/airflow users create \
            --username admin \
            --firstname Admin \
            --lastname User \
            --role Admin \
            --email admin@airflow.local \
            --password admin" || echo "AVISO: Falha ao criar usuário admin"
    fi
fi

# Iniciar o Airflow com o comando passado
echo "Iniciando o Airflow..."

# Trocar para usuário airflow antes de executar o Airflow
# (o entrypoint roda como root para corrigir permissões, mas Airflow deve rodar como airflow)
exec gosu airflow /usr/bin/dumb-init -- /home/airflow/.local/bin/airflow "$@"