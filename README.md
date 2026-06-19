# n8n Render Python Runtime

Custom Render-compatible n8n image used by the `n8n-5` Render service.

## Purpose

The official `docker.n8n.io/n8nio/n8n:latest` image started n8n successfully but logged Python task-runner startup failures because Python 3 was not present in the container. This image keeps n8n on the same current release line and adds Python 3 so n8n Code node Python execution can start cleanly.

## Base image

`docker.n8n.io/n8nio/n8n:2.4.5`

## Runtime changes

- Installs Python 3.
- Installs pip where available from the base OS package manager.
- Adds `/usr/local/bin/python` as a symlink to `python3`.
- Leaves n8n entrypoint, command, port behavior, and user model unchanged.

## Render service

The Render service should continue to provide all sensitive runtime configuration through Render environment variables, including:

- PostgreSQL connection variables
- `N8N_ENCRYPTION_KEY`
- `WEBHOOK_URL`
- `N8N_EDITOR_BASE_URL`

No secrets belong in this repository.
