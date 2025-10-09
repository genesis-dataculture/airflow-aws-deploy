FROM apache/airflow:2.8.1-python3.10

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential default-libmysqlclient-dev awscli curl \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
# remove CRLF e garante permissão de execução
RUN sed -i 's/\r$//' /entrypoint.sh && chmod 0755 /entrypoint.sh

USER airflow
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir --user -r /requirements.txt

ENTRYPOINT ["/entrypoint.sh"]