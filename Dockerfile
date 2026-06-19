ARG N8N_VERSION=2.4.5
ARG PYTHON_VERSION=3.12-slim-bookworm

FROM python:${PYTHON_VERSION} AS python-runtime

FROM docker.n8n.io/n8nio/n8n:${N8N_VERSION}

USER root

COPY --from=python-runtime /usr/local /usr/local

ENV PATH="/usr/local/bin:${PATH}"

RUN set -eux;     python3 --version;     python --version;     python3 - <<'PY'
import json
print(json.dumps({"python_runtime_ok": True}))
PY

USER node
