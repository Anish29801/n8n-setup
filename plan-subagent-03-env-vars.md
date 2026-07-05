# Subagent 03: Environment Variables Configuration

## Role

Set all required and recommended environment variables for n8n on Railway, including authentication, timezone, logging, and execution data policies.

---

## How to Set Variables

In Railway Dashboard:
1. Select the n8n service
2. Go to the **Variables** tab
3. Add each variable as a key-value pair
4. Railway supports `${{Service.VAR}}` interpolation for cross-service references

---

## Required Variables (Minimal Viable Deployment)

```env
N8N_PORT=${{PORT}}
```

| Variable | Value | Purpose |
|----------|-------|---------|
| `N8N_PORT` | `${{PORT}}` | Binds n8n to Railway's dynamic port. **Without this, the service is unreachable.** |

> Note: `${{PORT}}` is a Railway system variable — do NOT hardcode a number.

---

## Protocol & Host Configuration

```env
N8N_PROTOCOL=https
N8N_HOST=my-n8n.up.railway.app
WEBHOOK_URL=https://my-n8n.up.railway.app
N8N_EDITOR_BASE_URL=https://my-n8n.up.railway.app
```

| Variable | Value | Purpose |
|----------|-------|---------|
| `N8N_PROTOCOL` | `https` | Required for Railway's auto-generated domain (all HTTPS) |
| `N8N_HOST` | Your domain | Hostname for the n8n instance |
| `WEBHOOK_URL` | Full URL | Public-facing webhook endpoint; **critical for incoming webhooks** |
| `N8N_EDITOR_BASE_URL` | Full URL | Sets the base URL for the n8n editor UI |

**Update after generating a public domain** (see Subagent 06).

---

## Authentication Variables

```env
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=yourStrongPassword
```

| Variable | Value | Purpose |
|----------|-------|---------|
| `N8N_BASIC_AUTH_ACTIVE` | `true` | Enables HTTP Basic Auth on the editor |
| `N8N_BASIC_AUTH_USER` | Your username | Login username |
| `N8N_BASIC_AUTH_PASSWORD` | Strong password | Login password |

**Security**: Use a long (20+ char) random password. Consider using Railway's built-in variable generator.

---

## Encryption Key

```env
N8N_ENCRYPTION_KEY=your-64-char-hex-key
```

| Variable | Value | Purpose |
|----------|-------|---------|
| `N8N_ENCRYPTION_KEY` | 64-char hex string | Encrypts stored credentials |

**Generate a secure key**:

```bash
openssl rand -hex 32
```

Example output: `6fd81b35af7d3f5f14e92d0c58b7d3ecb4bb0fd5c62c4a2f4ef5a7d0b2f87e34`

> **Critical**: Never change this after storing credentials. Existing credentials become unreadable and unrecoverable.

---

## Timezone

```env
GENERIC_TIMEZONE=Asia/Kolkata
```

Set to your local IANA timezone. Common values:
- `Asia/Kolkata` — India Standard Time (UTC+5:30)
- `America/New_York` — Eastern Time
- `Europe/London` — British Time
- `UTC` — Universal Coordinated Time

Affects: time displays in the editor, schedule trigger execution times.

---

## Execution Data Retention

```env
EXECUTIONS_DATA_SAVE_ON_SUCCESS=none
EXECUTIONS_DATA_SAVE_ON_ERROR=all
```

| Variable | Value | Effect |
|----------|-------|--------|
| `EXECUTIONS_DATA_SAVE_ON_SUCCESS` | `none` | Saves no execution data on success (saves volume space) |
| `EXECUTIONS_DATA_SAVE_ON_ERROR` | `all` | Saves full execution data on failure (helps debugging) |

Alternatives:
- `all` / `all` — full history (needs more volume space)
- `none` / `none` — minimal (harder to debug)

---

## Logging

```env
N8N_LOG_LEVEL=info
```

| Level | Use Case |
|-------|----------|
| `error` | Production — minimal logs |
| `warn` | Production — warnings only |
| `info` | Default — general operational logs |
| `debug` | Development — verbose |

---

## Complete Variable Reference Table

| Variable | Required | Example Value | Notes |
|----------|----------|---------------|-------|
| `N8N_PORT` | **Yes** | `${{PORT}}` | Railway system variable |
| `N8N_PROTOCOL` | **Yes** | `https` | Railway uses HTTPS |
| `WEBHOOK_URL` | **Yes** | `https://my-n8n.up.railway.app` | Must match domain |
| `N8N_EDITOR_BASE_URL` | **Yes** | `https://my-n8n.up.railway.app` | Must match domain |
| `N8N_BASIC_AUTH_ACTIVE` | Recommended | `true` | Enables login |
| `N8N_BASIC_AUTH_USER` | Recommended | `admin` | Change from default |
| `N8N_BASIC_AUTH_PASSWORD` | Recommended | `random-strong-pass` | 20+ chars |
| `GENERIC_TIMEZONE` | Recommended | `Asia/Kolkata` | Your IANA zone |
| `N8N_ENCRYPTION_KEY` | **Yes** | `hex-64-chars` | Never change after set |
| `N8N_HOST` | Optional | `my-n8n.up.railway.app` | If different from URL |
| `N8N_LOG_LEVEL` | Optional | `info` | Or `warn` / `debug` |
| `EXECUTIONS_DATA_SAVE_ON_SUCCESS` | Optional | `none` | Or `all` / `metadata` |
| `EXECUTIONS_DATA_SAVE_ON_ERROR` | Optional | `all` | Or `none` / `metadata` |
