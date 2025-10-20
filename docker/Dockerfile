FROM apache/airflow:2.8.1-python3.10

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential default-libmysqlclient-dev awscli curl git gosu \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh /entrypoint.sh
# remove CRLF e garante permissão de execução
RUN sed -i 's/\r$//' /entrypoint.sh && chmod 0755 /entrypoint.sh

USER airflow
COPY docker/requirements.txt /requirements.txt
RUN pip install --no-cache-dir --user -r /requirements.txt

# Copiar projeto dbt para a imagem (como usuário airflow para ter permissões corretas)
USER root
COPY dbt /opt/airflow/dbt
RUN chown -R airflow:root /opt/airflow/dbt && chmod -R 775 /opt/airflow/dbt

# Voltar para diretório padrão
WORKDIR /opt/airflow

# CRÍTICO: Entrypoint deve rodar como root para corrigir permissões
# O entrypoint.sh irá trocar para usuário airflow antes de executar o Airflow
ENTRYPOINT ["/entrypoint.sh"]