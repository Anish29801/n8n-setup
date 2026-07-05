# Subagent 02: Docker Image Configuration

## Role

Configure the official n8n Docker image (`n8nio/n8n`) on Railway — image selection, port mapping, restart policy, and image update strategy.

---

## Docker Image Reference

| Field | Value |
|-------|-------|
| Image | `n8nio/n8n` |
| Source | Docker Hub (official) |
| Tag | `latest` (default, Railway pulls latest) |
| Port | `5678` (n8n default, mapped via `N8N_PORT`) |
| Base OS | Alpine Linux |
| Working Dir | `/home/node/.n8n` |

---

## How Railway Handles Docker Images

Railway does NOT use a Dockerfile — it pulls a pre-built image directly:

1. When you select **Deploy Docker Image**, Railway creates a service that wraps the container
2. Railway injects `${{PORT}}` as an environment variable (this is Railway's assigned port, NOT n8n's default 5678)
3. The container's `CMD` and `ENTRYPOINT` from the Docker image are respected

---

## Required Port Configuration

Set in Railway Variables (see Subagent 03):

```env
N8N_PORT=${{PORT}}
```

**Why**: Railway assigns a dynamic port. n8n MUST bind to Railway's `${{PORT}}` variable, not the static 5678. Without this, the health check fails and the service appears unreachable.

---

## Restart & Health

- Railway automatically restarts the container on crash
- n8n exposes a health endpoint at `/healthz`
- Railway pings this endpoint every 30 seconds
- If unhealthy for 3 consecutive checks, Railway restarts the container

---

## Updating the Image

To update n8n to the latest version:

1. Open the Railway project
2. Select the n8n service
3. Click **Redeploy**

Railway pulls the latest `n8nio/n8n:latest` tag and replaces the running container with zero-downtime (if PostgreSQL + Volume are configured — see Subagent 04, 05).

**Manual image pinning** (optional, for production stability):

```env
# No env var — Railway always uses :latest
# To pin a version, use the Image field directly:
n8nio/n8n:1.70.0
```

But pinning requires manual version bumps. `latest` is recommended for most deployments.

---

## Verification

```bash
railway service list
# Look for: n8n  |  Running  |  n8nio/n8n
```

Or via Railway Dashboard — the service card shows:

```
Image: n8nio/n8n
Status: Running
Uptime: XXh XXm
```
