FROM apache/airflow:2.8.1-python3.10

USER root
# deps do sistema
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential default-libmysqlclient-dev awscli curl \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# copie e ajuste as permissões como root
COPY /entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod 0755 /entrypoint.sh

# volte para airflow antes de instalar python (se preferir)
USER airflow
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir --user -r /requirements.txt

ENTRYPOINT ["/entrypoint.sh"]
