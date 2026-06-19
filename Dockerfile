ARG NODE_VERSION=22-bookworm-slim
ARG PYTHON_VERSION=3.13-slim-bookworm
ARG N8N_VERSION=2.4.5

FROM node:${NODE_VERSION} AS node-runtime
FROM python:${PYTHON_VERSION}

ARG N8N_VERSION=2.4.5
ARG UV_VERSION=0.8.14

USER root
ENV NODE_ENV=production
ENV N8N_PORT=5678
ENV N8N_RUNNERS_ENABLED=true
ENV N8N_RUNNERS_MODE=external
ENV N8N_NATIVE_PYTHON_RUNNER=true
ENV N8N_RUNNERS_BROKER_LISTEN_ADDRESS=127.0.0.1
ENV N8N_RUNNERS_BROKER_PORT=5679
ENV HOME=/home/node
ENV PATH=/usr/local/bin:${PATH}

COPY --from=node-runtime /usr/local /usr/local

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl netcat-openbsd tini && rm -rf /var/lib/apt/lists/*
RUN python3 --version && python --version && node --version && npm --version
RUN python -m pip install --no-cache-dir uv==${UV_VERSION}
RUN npm install -g n8n@${N8N_VERSION} && npm cache clean --force

WORKDIR /usr/local/lib/node_modules
RUN curl -fsSL -o /tmp/n8n.tar.gz https://github.com/n8n-io/n8n/archive/refs/tags/n8n@${N8N_VERSION}.tar.gz
RUN mkdir -p /tmp/n8n-src && tar -xzf /tmp/n8n.tar.gz -C /tmp/n8n-src
RUN mkdir -p /usr/local/lib/node_modules/@n8n && cp -a /tmp/n8n-src/n8n-n8n-${N8N_VERSION}/packages/@n8n/task-runner-python /usr/local/lib/node_modules/@n8n/task-runner-python
RUN cd /usr/local/lib/node_modules/@n8n/task-runner-python && uv venv && uv sync --frozen --no-dev --all-extras --no-editable
RUN test -x /usr/local/lib/node_modules/@n8n/task-runner-python/.venv/bin/python && /usr/local/lib/node_modules/@n8n/task-runner-python/.venv/bin/python --version && n8n --version
RUN mkdir -p /home/node && chown -R 1000:1000 /home/node /usr/local/lib/node_modules/@n8n/task-runner-python && rm -rf /tmp/* /root/.cache

WORKDIR /home/node
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown 1000:1000 /entrypoint.sh
EXPOSE 5678
USER 1000:1000
ENTRYPOINT ["tini", "--", "/bin/sh", "/entrypoint.sh"]
