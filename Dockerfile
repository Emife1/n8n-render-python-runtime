ARG NODE_VERSION=22-bookworm-slim
ARG N8N_VERSION=2.4.5

FROM node:${NODE_VERSION}

ARG N8N_VERSION=2.4.5

USER root

ENV NODE_ENV=production     N8N_PORT=5678     N8N_RUNNERS_ENABLED=true     N8N_RUNNERS_MODE=internal     N8N_NATIVE_PYTHON_RUNNER=true

RUN set -eux;     apt-get update;     apt-get install -y --no-install-recommends ca-certificates python3 python3-pip tini;     ln -sf /usr/bin/python3 /usr/local/bin/python;     npm install -g n8n@${N8N_VERSION};     npm cache clean --force;     apt-get clean;     rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*;     python3 --version;     python --version;     n8n --version

WORKDIR /home/node
EXPOSE 5678
USER node
ENTRYPOINT ["tini", "--"]
CMD ["n8n", "start"]
