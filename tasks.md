# AGY CLI Setup Guide: Deploy Latest n8n on Railway with Docker and Gmail OAuth

## Goal

Deploy the latest stable n8n using Docker on Railway, configure persistent storage, and connect Gmail using OAuth2 so the **Gmail Send Message** node works correctly.

---

# Project Structure

```
n8n-railway/
├── Dockerfile
├── docker-compose.yml (optional for local)
├── .dockerignore
├── .env.example
├── README.md
```

---

# Step 1 — Create Railway Project

1. Log in to Railway.
2. Create a **New Project**.
3. Choose **Empty Project**.
4. Add a new service.
5. Select **Deploy from Dockerfile**.

---

# Step 2 — Dockerfile

Always use the latest official n8n image.

```dockerfile
FROM docker.n8n.io/n8nio/n8n:latest

EXPOSE 5678
```

---

# Step 3 — Railway Variables

Configure the following environment variables.

```
N8N_HOST=<railway-domain>
N8N_PORT=5678
N8N_PROTOCOL=https

WEBHOOK_URL=https://<railway-domain>/

N8N_SECURE_COOKIE=true

N8N_EDITOR_BASE_URL=https://<railway-domain>

GENERIC_TIMEZONE=Asia/Kolkata

TZ=Asia/Kolkata

N8N_ENCRYPTION_KEY=<generate-a-random-32+-character-string>

N8N_RUNNERS_ENABLED=true

N8N_DIAGNOSTICS_ENABLED=false

N8N_VERSION_NOTIFICATIONS_ENABLED=false

N8N_HIRING_BANNER_ENABLED=false

NODE_ENV=production
```

---

# Step 4 — Persistent Storage

Attach a Railway Volume.

Mount path:

```
/home/node/.n8n
```

This keeps:

* credentials
* workflows
* executions
* encryption data

safe between deployments.

---

# Step 5 — Deploy

Deploy the project.

Open

```
https://<railway-domain>
```

You should see the n8n editor.

---

# Step 6 — Secure n8n

Enable basic authentication.

Environment variables:

```
N8N_BASIC_AUTH_ACTIVE=true

N8N_BASIC_AUTH_USER=admin

N8N_BASIC_AUTH_PASSWORD=<strong-password>
```

Redeploy.

---

# Step 7 — Google Cloud Project

Open

https://console.cloud.google.com

Create a project.

Enable:

* Gmail API

---

# Step 8 — OAuth Consent Screen

Create an OAuth Consent Screen.

Choose:

External

Add:

* App name
* Support email
* Developer email

Scopes:

```
gmail.send
```

---

# Step 9 — OAuth Client

Create

```
OAuth Client ID
```

Application type:

```
Web Application
```

Authorized Redirect URI:

```
https://<railway-domain>/rest/oauth2-credential/callback
```

Save.

Google provides:

```
Client ID

Client Secret
```

---

# Step 10 — Gmail Credential in n8n

Open

Credentials

Create Credential

Choose

```
Gmail OAuth2 API
```

Fill in:

Client ID

Client Secret

Click

```
Connect OAuth Account
```

Log in to Gmail.

Grant permissions.

The credential should now show

```
Connected
```

---

# Step 11 — Gmail Node

Use

```
Gmail

↓

Send Message
```

Settings

To

```
example@gmail.com
```

Subject

```
Daily Weather Report
```

Email Type

```
HTML
```

Message

```
{{$json.output}}
```

or

```
{{$json.html}}
```

depending on the previous node.

---

# Step 12 — Weather Workflow

Workflow

```
Schedule Trigger

↓

HTTP Request

↓

AI Agent (Gemini)

↓

Code (optional)

↓

Gmail Send Message
```

---

# Step 13 — OpenWeather

Example request

```
https://api.openweathermap.org/data/2.5/weather?q=Hyderabad&units=metric&appid=<OPENWEATHER_API_KEY>
```

---

# Step 14 — Gemini

Recommended model

```
gemini-2.5-flash
```

Prompt should:

* read the JSON
* produce raw HTML
* return HTML only
* never output Markdown
* never output JavaScript
* never output PHP
* never output template placeholders

---

# Step 15 — Railway Health Check

Health Check Path

```
/
```

Port

```
5678
```

---

# Step 16 — Automatic Updates

Whenever updating:

```
FROM docker.n8n.io/n8nio/n8n:latest
```

Redeploy Railway.

---

# Secrets

Do **not** hardcode or commit API keys, OAuth client secrets, encryption keys, or passwords into the repository or documentation. Store them only as Railway environment variables or another secure secret manager.

Use placeholders such as:

```
OPENWEATHER_API_KEY=<your-openweather-api-key>

GOOGLE_CLIENT_ID=<your-google-client-id>

GOOGLE_CLIENT_SECRET=<your-google-client-secret>

N8N_ENCRYPTION_KEY=<random-32+-character-secret>
```

---

# Final Architecture

```
Railway
    │
    ▼
Latest n8n Docker
    │
    ▼
Schedule Trigger
    │
    ▼
OpenWeather API
    │
    ▼
Gemini AI Agent
    │
    ▼
(Optional) Code Node
    │
    ▼
Gmail Send Message
    │
    ▼
HTML Weather Email
```
