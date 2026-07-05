# Subagent 01: Prerequisites & Project Initialization

## Role

Provision Railway account, GitHub integration (optional), and scaffold a new Railway project for n8n deployment.

---

## Prerequisites Checklist

| Item | Required | Notes |
|------|----------|-------|
| Railway account | Yes | Sign up at https://railway.app |
| GitHub account | Optional | Used for Railway login / CI |
| Railway CLI | Optional | For programmatic deployment |
| Basic Railway familiarity | Expected | Project, service, volume concepts |

---

## Step-by-Step

### 1. Create a Railway Account

1. Go to https://railway.app
2. Sign up via email, GitHub, or Google
3. Verify email if required
4. Confirm billing is set up (Railway requires a payment method even on free tier)

### 2. (Optional) Connect GitHub

1. Navigate to Settings → GitHub in Railway
2. Authorize Railway to access your GitHub account
3. This enables deployment from GitHub repos later

### 3. Create a New Railway Project

1. From the Railway dashboard, click **New Project**
2. Select **Deploy Docker Image** (NOT "Empty Service" or "From Repo")
3. In the image field, enter:

   ```
   n8nio/n8n
   ```

4. Railway validates the image exists on Docker Hub and begins pulling
5. Once pulled, the container starts automatically with default settings

### 4. Verify Initial Deployment

1. Railway shows a deployment log — watch for:

   ```
   ✅ Successfully deployed
   ```

2. Note the auto-generated domain (e.g., `https://n8n-xxxxx.up.railway.app`)
3. The service appears in the project dashboard with a green "Running" indicator

---

## Files / Services Created

```
Railway Project
└── n8n Service (Docker Image: n8nio/n8n)
    └── Auto-generated Public Domain
```

---

## Verification Command

```bash
curl -I https://your-app.up.railway.app/healthz
# Expected: HTTP/2 200
```

---

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| `Image pull failed` | Image name typo or Docker Hub unavailable | Verify `n8nio/n8n` is correct |
| `Deployment stuck` | Port mismatch or missing ENV | Ensure `N8N_PORT` is set (handled in Subagent 02) |
| `Service crashes on start` | Missing variables | Proceed to Subagent 02 — env vars fix this |
