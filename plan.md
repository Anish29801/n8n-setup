````markdown
# Deploy n8n on Railway Using the Official Docker Image

This guide explains how to deploy **n8n** on **Railway** using the official Docker image.

---

## Prerequisites

- A Railway account
- A GitHub account (optional)
- Basic familiarity with Railway

---

## Step 1: Create a New Railway Project

1. Log in to Railway.
2. Click **New Project**.
3. Select **Deploy Docker Image**.
4. Enter the official n8n image:

```text
n8nio/n8n
```

Railway will pull the latest official image and begin deployment.

---

## Step 2: Configure Environment Variables

Open your service and navigate to:

```
Variables
```

Add the following required variables:

```env
N8N_PORT=${{PORT}}
N8N_PROTOCOL=https
WEBHOOK_URL=https://your-app.up.railway.app
```

Replace `your-app.up.railway.app` with your Railway-generated domain.

### Recommended Variables

```env
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=yourStrongPassword

GENERIC_TIMEZONE=Asia/Kolkata
```

These enable authentication and set the correct timezone.

---

## Step 3: Use PostgreSQL (Recommended)

Instead of SQLite, create a PostgreSQL service in Railway.

Once created, configure n8n with:

```env
DB_TYPE=postgresdb

DB_POSTGRESDB_HOST=${{Postgres.PGHOST}}
DB_POSTGRESDB_PORT=${{Postgres.PGPORT}}
DB_POSTGRESDB_DATABASE=${{Postgres.PGDATABASE}}
DB_POSTGRESDB_USER=${{Postgres.PGUSER}}
DB_POSTGRESDB_PASSWORD=${{Postgres.PGPASSWORD}}
```

Railway automatically injects these values from the PostgreSQL service.

---

## Step 4: Add Persistent Storage

Without persistent storage, credentials and local files can be lost after redeployments.

1. Open the n8n service.
2. Add a **Volume**.
3. Mount it at:

```text
/home/node/.n8n
```

This directory stores:

- Encryption key
- Local configuration
- Binary data (when applicable)

---

## Step 5: Generate a Public Domain

Navigate to:

```
Settings
→ Networking
→ Generate Domain
```

Example:

```text
https://my-n8n.up.railway.app
```

Update your environment variables:

```env
WEBHOOK_URL=https://my-n8n.up.railway.app
N8N_EDITOR_BASE_URL=https://my-n8n.up.railway.app
```

Redeploy the service after making changes.

---

## Step 6: Configure an Encryption Key

Set a permanent encryption key:

```env
N8N_ENCRYPTION_KEY=generate-a-long-random-secret-key
```

> **Important:** Never change this value after storing credentials in n8n. Changing it will make existing credentials unreadable.

Generate a secure key with:

```bash
openssl rand -hex 32
```

Example output:

```text
6fd81b35af7d3f5f14e92d0c58b7d3ecb4bb0fd5c62c4a2f4ef5a7d0b2f87e34
```

---

## Step 7: Optional Environment Variables

```env
N8N_HOST=my-n8n.up.railway.app

EXECUTIONS_DATA_SAVE_ON_SUCCESS=none
EXECUTIONS_DATA_SAVE_ON_ERROR=all

N8N_LOG_LEVEL=info
```

---

## Step 8: Deploy

Click **Deploy** or **Redeploy**.

After deployment, visit:

```text
https://my-n8n.up.railway.app
```

Log in using the Basic Auth credentials configured earlier.

---

# Updating n8n

To update to the latest version:

1. Open the Railway project.
2. Select the n8n service.
3. Click **Redeploy**.

Railway will pull the latest version of the official Docker image.

---

# Recommended Production Configuration

| Component | Recommendation |
|-----------|----------------|
| Docker Image | `n8nio/n8n` |
| Database | PostgreSQL |
| Storage | Railway Volume |
| Authentication | Basic Auth |
| Webhook URL | Configured |
| HTTPS | Railway Domain or Custom Domain |
| Encryption | Fixed `N8N_ENCRYPTION_KEY` |
| Timezone | `Asia/Kolkata` |
| Logging | `info` |
| Backups | PostgreSQL + Volume |

---

## Directory Structure

```text
Railway Project
├── n8n Service
│   ├── Docker Image: n8nio/n8n
│   ├── Environment Variables
│   ├── Volume (/home/node/.n8n)
│   └── Public Domain
│
└── PostgreSQL Service
```

---

## Useful Commands

Generate a secure encryption key:

```bash
openssl rand -hex 32
```

Restart the deployment:

```text
Railway Dashboard → n8n Service → Redeploy
```

---

## References

- https://docs.railway.com/guides/n8n
- https://docs.n8n.io/hosting/
- https://hub.docker.com/r/n8nio/n8n
````
Let's s