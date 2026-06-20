ARG NODE_VERSION=22-bookworm-slim
ARG PYTHON_VERSION=3.13-slim-bookworm
ARG N8N_VERSION=2.15.0

FROM node:${NODE_VERSION} AS node-runtime
FROM python:${PYTHON_VERSION}

ARG N8N_VERSION=2.15.0
ARG UV_VERSION=0.8.14

USER root
ENV NODE_ENV=production
ENV N8N_PORT=5678
ENV N8N_RUNNERS_ENABLED=true
ENV N8N_RUNNERS_MODE=external
ENV N8N_NATIVE_PYTHON_RUNNER=true
ENV N8N_RUNNERS_BROKER_LISTEN_ADDRESS=127.0.0.1
ENV N8N_RUNNERS_BROKER_PORT=5679
ENV N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT=0
ENV HOME=/home/node
ENV NODE_PATH=/usr/local/lib/node_modules/n8n/node_modules:/usr/local/lib/node_modules
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

RUN cat > /usr/local/bin/start-n8n-render.sh <<'EOF'
#!/bin/sh
set -eu

BROKER_HOST="127.0.0.1"
BROKER_PORT="${N8N_RUNNERS_BROKER_PORT:-5679}"
BROKER_URI="http://${BROKER_HOST}:${BROKER_PORT}"
BROKER_PATH="${N8N_RUNNERS_PATH:-/runners}"
JS_PID=""
PY_PID=""

if [ -z "${N8N_RUNNERS_AUTH_TOKEN:-}" ]; then
  N8N_RUNNERS_AUTH_TOKEN="$(python -c 'import secrets; print(secrets.token_hex(32))')"
  export N8N_RUNNERS_AUTH_TOKEN
fi

export HOME=/home/node
export N8N_RUNNERS_ENABLED=true
export N8N_RUNNERS_MODE=external
export N8N_NATIVE_PYTHON_RUNNER=true
export N8N_RUNNERS_BROKER_LISTEN_ADDRESS="${N8N_RUNNERS_BROKER_LISTEN_ADDRESS:-127.0.0.1}"
export N8N_RUNNERS_BROKER_PORT="$BROKER_PORT"
export N8N_RUNNERS_TASK_BROKER_URI="$BROKER_URI"
export N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT=0

log() {
  echo "[entrypoint] $*"
}

request_grant_token() {
  python - "$BROKER_URI" "$BROKER_PATH" "$N8N_RUNNERS_AUTH_TOKEN" <<'PY'
import json
import sys
import time
import urllib.request

broker_uri, broker_path, shared_token = sys.argv[1], sys.argv[2], sys.argv[3]
url = broker_uri.rstrip('/') + broker_path.rstrip('/') + '/auth'
body = json.dumps({'token': shared_token}).encode('utf-8')
headers = {'Content-Type': 'application/json'}

for _ in range(30):
    try:
        req = urllib.request.Request(url, data=body, headers=headers, method='POST')
        with urllib.request.urlopen(req, timeout=3) as response:
            payload = json.loads(response.read().decode('utf-8'))
            token = payload.get('token') or payload.get('data', {}).get('token')
            if token:
                print(token)
                raise SystemExit(0)
    except Exception:
        time.sleep(1)

raise SystemExit(1)
PY
}

start_js_runner() {
  while kill -0 "$N8N_PID" 2>/dev/null; do
    GRANT_TOKEN="$(request_grant_token)" || {
      log "JS runner could not obtain grant token; retrying"
      sleep 3
      continue
    }
    N8N_RUNNERS_GRANT_TOKEN="$GRANT_TOKEN" \
    N8N_RUNNERS_TASK_BROKER_URI="$BROKER_URI" \
    node --disallow-code-generation-from-strings --disable-proto=delete "$(node -p 'require.resolve("@n8n/task-runner/start")')" || true
    sleep 2
  done
}

start_python_runner() {
  cd /usr/local/lib/node_modules/@n8n/task-runner-python
  while kill -0 "$N8N_PID" 2>/dev/null; do
    GRANT_TOKEN="$(request_grant_token)" || {
      log "Python runner could not obtain grant token; retrying"
      sleep 3
      continue
    }
    N8N_RUNNERS_GRANT_TOKEN="$GRANT_TOKEN" \
    N8N_RUNNERS_TASK_BROKER_URI="$BROKER_URI" \
    ./.venv/bin/python -m src.main || true
    sleep 2
  done
}

cleanup() {
  log "Stopping"
  [ -n "$JS_PID" ] && kill "$JS_PID" 2>/dev/null || true
  [ -n "$PY_PID" ] && kill "$PY_PID" 2>/dev/null || true
  kill "$N8N_PID" 2>/dev/null || true
  wait "$N8N_PID" 2>/dev/null || true
}
trap cleanup INT TERM

log "Starting n8n"
n8n start &
N8N_PID=$!

log "Waiting for task broker on ${BROKER_HOST}:${BROKER_PORT}"
until nc -z "$BROKER_HOST" "$BROKER_PORT"; do
  if ! kill -0 "$N8N_PID" 2>/dev/null; then
    log "n8n exited before task broker became ready"
    wait "$N8N_PID"
    exit $?
  fi
  sleep 1
done

log "Task broker ready; starting local JS and Python runners"
start_js_runner &
JS_PID=$!
start_python_runner &
PY_PID=$!

wait "$N8N_PID"
EOF

RUN chmod +x /usr/local/bin/start-n8n-render.sh && mkdir -p /home/node && chown -R 1000:1000 /home/node /usr/local/lib/node_modules/@n8n/task-runner-python /usr/local/bin/start-n8n-render.sh && rm -rf /tmp/* /root/.cache

WORKDIR /home/node
EXPOSE 5678
USER 1000:1000
ENTRYPOINT ["tini", "--", "/usr/local/bin/start-n8n-render.sh"]
