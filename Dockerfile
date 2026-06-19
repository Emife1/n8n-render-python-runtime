ARG N8N_VERSION=2.4.5
FROM docker.n8n.io/n8nio/n8n:${N8N_VERSION}

USER root

RUN set -eux;     if command -v apk >/dev/null 2>&1; then       apk add --no-cache python3 py3-pip;     elif command -v apt-get >/dev/null 2>&1; then       apt-get update;       apt-get install -y --no-install-recommends python3 python3-pip ca-certificates;       rm -rf /var/lib/apt/lists/*;     else       echo "Unsupported base image package manager" >&2;       exit 1;     fi;     ln -sf "$(command -v python3)" /usr/local/bin/python;     python3 --version;     python --version

USER node
