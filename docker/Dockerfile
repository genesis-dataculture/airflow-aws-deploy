FROM apache/airflow:2.8.1-python3.10

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential default-libmysqlclient-dev awscli curl \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh /entrypoint.sh
# remove CRLF e garante permissão de execução
RUN sed -i 's/\r$//' /entrypoint.sh && chmod 0755 /entrypoint.sh

USER airflow
COPY docker/requirements.txt /requirements.txt
RUN pip install --no-cache-dir --user -r /requirements.txt

# Copiar projeto dbt para a imagem
COPY dbt /opt/airflow/dbt

# Instalar packages dbt durante o build (uma vez só)
WORKDIR /opt/airflow/dbt
RUN if [ -f "packages.yml" ]; then \
        echo "===========================================" && \
        echo "Instalando packages dbt durante o build..." && \
        echo "===========================================" && \
        dbt deps --profiles-dir . && \
        echo "" && \
        echo "Packages instalados com sucesso:" && \
        ls -la dbt_packages/ 2>/dev/null || echo "AVISO: Diretório dbt_packages não encontrado"; \
    else \
        echo "AVISO: Nenhum packages.yml encontrado, pulando instalação"; \
    fi

# Voltar para diretório padrão
WORKDIR /opt/airflow

ENTRYPOINT ["/entrypoint.sh"]