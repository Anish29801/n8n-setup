# Subagent 07: Deployment, Maintenance & Production Configuration

## Role

Final deployment trigger, ongoing maintenance (updates, backups, monitoring), and a complete production-ready configuration reference.

---

## Part A: Final Deployment

### Prerequisites Check

Before deploying, verify all prior subagents completed:

- [ ] **Subagent 01**: Railway project created, Docker image selected (`n8nio/n8n`)
- [ ] **Subagent 02**: Port configuration correct (`N8N_PORT=${{PORT}}`)
- [ ] **Subagent 03**: All env vars set (auth, encryption key, timezone, etc.)
- [ ] **Subagent 04**: PostgreSQL service created and connected
- [ ] **Subagent 05**: Volume mounted at `/home/node/.n8n`
- [ ] **Subagent 06**: Public domain generated, URLs updated

### Deploy

1. In Railway Dashboard, select the n8n service
2. Click **Deploy** (or **Redeploy** if already running)
3. Monitor the deployment logs:

   ```
   Pulling image: n8nio/n8n:latest
   Pulling complete
   Starting container...
   Running database migrations...
   n8n ready on port XXXX
   ✅ Successfully deployed
   ```

### Post-Deployment Verification

```bash
# Health check
curl -I https://my-n8n.up.railway.app/healthz
# Expected: HTTP/2 200

# Access editor
open https://my-n8n.up.railway.app
# Login with Basic Auth credentials
```

### First-Run Actions in n8n Editor

1. Change the default owner password (if using owner account, not Basic Auth)
2. Create a test workflow with a Webhook trigger
3. Execute the workflow to verify end-to-end functionality
4. Check **Settings** → **Database** confirms PostgreSQL

---

## Part B: Updating n8n

### Standard Update

1. Open Railway Dashboard
2. Select the n8n service
3. Click **Redeploy**
4. Railway pulls the latest `n8nio/n8n:latest` image
5. Container restarts — database migrations run automatically

**Expected downtime**: ~30-60 seconds (container swap)

### Zero-Downtime Update (Advanced)

For production with minimal interruption:

1. Ensure PostgreSQL + Volume are configured (makes restart stateless)
2. Railway's rolling update mechanism replaces containers gradually
3. If using a single container, brief downtime is unavoidable

### Version Pinning (Production Stability)

To avoid unexpected breaking changes:

1. Use a specific image tag instead of `latest`:

   ```
   n8nio/n8n:1.70.0
   ```

2. Upgrade deliberately after reading release notes:
   - https://github.com/n8n-io/n8n/releases
3. To upgrade, change the image tag and redeploy

---

## Part C: Backup Strategy

### PostgreSQL Backups

Railway automated:
- Daily snapshots
- 7-day retention
- One-click restore from Dashboard

### Volume Backups

Railway does NOT automatically back up volumes. For critical binary data:

1. **Manual backup**: SSH into a temporary pod and archive the volume:

   ```bash
   tar -czf n8n-backup-$(date +%Y%m%d).tar.gz /home/node/.n8n
   ```

2. **Automation**: Create an n8n workflow that exports via API and stores in cloud storage (S3, Google Drive, etc.)

### Full System Recovery

To recover from complete failure:
1. Create a new Railway project
2. Set up PostgreSQL (restore from snapshot)
3. Set up volume (restore from tar backup)
4. Configure same `N8N_ENCRYPTION_KEY`
5. Set env vars and deploy

---

## Part D: Monitoring & Logging

### Railway Logs

1. Select n8n service → **Logs** tab
2. Filter by severity (info, warn, error)
3. Search log history via the search bar

### n8n Log Levels

Set via `N8N_LOG_LEVEL`:

| Level | Volume | Use Case |
|-------|--------|----------|
| `error` | Low | Production — errors only |
| `warn` | Low | Production — warnings + errors |
| `info` | Medium | Default — general operations |
| `debug` | High | Development — verbose |

### Health Monitoring

Railway automatically:
- Pings `/healthz` every 30 seconds
- Restarts on 3 consecutive failures
- Restarts on crash (non-zero exit code)

---

## Part E: Production Configuration Reference

| Component | Recommendation | Set By |
|-----------|---------------|--------|
| Docker Image | `n8nio/n8n` | Subagent 02 |
| Database | PostgreSQL | Subagent 04 |
| Storage | Railway Volume (`/home/node/.n8n`) | Subagent 05 |
| Authentication | Basic Auth | Subagent 03 |
| Webhook URL | Configured | Subagent 03, 06 |
| HTTPS | Railway Domain or Custom Domain | Subagent 06 |
| Encryption | Fixed `N8N_ENCRYPTION_KEY` | Subagent 03, 05 |
| Timezone | `Asia/Kolkata` or your local zone | Subagent 03 |
| Logging | `info` (or `warn` in production) | Subagent 03 |
| Execution Data | Save on error only | Subagent 03 |
| Backups | PostgreSQL snapshots + manual volume | Subagent 04, 07 |

---

## Part F: Useful Commands

```bash
# Generate encryption key
openssl rand -hex 32

# Health check
curl https://my-n8n.up.railway.app/healthz

# Test webhook
curl -X POST https://my-n8n.up.railway.app/webhook-test/test \
  -H "Content-Type: application/json" \
  -d '{"msg": "hello"}' \

# Check n8n version (from container)
docker run --rm n8nio/n8n n8n --version
```

---

## Part G: References

- https://docs.railway.com/guides/n8n
- https://docs.n8n.io/hosting/
- https://hub.docker.com/r/n8nio/n8n
- https://github.com/n8n-io/n8n/releases
- https://docs.railway.com/deploy/docker
