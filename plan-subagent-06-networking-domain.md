# Subagent 06: Networking & Public Domain

## Role

Generate a Railway public domain (or configure a custom domain), set up HTTPS, and update n8n's webhook and editor URLs to match the public endpoint.

---

## Part A: Generate a Railway Public Domain

### Steps

1. In the Railway Dashboard, select the n8n service
2. Go to **Settings** → **Networking**
3. Click **Generate Domain**
4. Railway immediately assigns a domain:

   ```
   https://my-n8n.up.railway.app
   ```

5. The domain is active within ~30 seconds
6. HTTPS (TLS) is **automatic** — Railway provisions a Let's Encrypt certificate

### Domain Format

```
https://<project-name>-<random-hash>.up.railway.app
```

Example: `https://n8n-3a7f2b.up.railway.app`

---

## Part B: Update Environment Variables

After generating the domain, update these variables in the n8n service:

### Required Updates

```env
WEBHOOK_URL=https://my-n8n.up.railway.app
N8N_EDITOR_BASE_URL=https://my-n8n.up.railway.app
```

Replace `my-n8n.up.railway.app` with your actual Railway domain.

### Optional Updates

```env
N8N_HOST=my-n8n.up.railway.app
```

(Only needed if n8n should report its hostname separately from the editor URL.)

### Redeploy

After updating variables:
1. Go to the n8n service
2. Click **Deploy** or **Redeploy**
3. Railway restarts the container with new URLs

---

## Part C: Custom Domain (Optional)

### Prerequisites

- A domain you own (e.g., `n8n.example.com`)
- Access to your DNS provider

### Steps

1. In Railway n8n service → **Settings** → **Networking**
2. Click **Custom Domain**
3. Enter your domain: `n8n.example.com`
4. Railway shows DNS records to add:

   | Record Type | Name | Value |
   |-------------|------|-------|
   | `CNAME` | `n8n` | `n8n-3a7f2b.up.railway.app` |

5. Add the record at your DNS provider (may take 5-30 min to propagate)
6. Railway auto-provisions a Let's Encrypt certificate for your domain
7. Update environment variables:

   ```env
   WEBHOOK_URL=https://n8n.example.com
   N8N_EDITOR_BASE_URL=https://n8n.example.com
   N8N_HOST=n8n.example.com
   ```

### Custom Domain HTTPS

Railway handles TLS automatically:
- Certificate: Let's Encrypt
- Auto-renewal: Yes (automated)
- Forced HTTPS: Yes (HTTP → 301 redirect)

---

## Part D: Verify Networking

### Webhook Test

```bash
curl -I https://my-n8n.up.railway.app/healthz
# Expected: HTTP/2 200
```

### Webhook URL Test

```bash
curl -X POST https://my-n8n.up.railway.app/webhook-test/test \
  -H "Content-Type: application/json" \
  -d '{"test": true}'
# Expected: HTTP 200 (n8n returns "Webhook Test Received")
```

### Editor Access

1. Open `https://my-n8n.up.railway.app` in a browser
2. You should see the n8n login page
3. Log in with Basic Auth credentials (if enabled)

---

## Network Architecture

```
Internet
  │
  ▼
Railway Edge (CDN, DDoS protection, TLS termination)
  │
  ▼
Railway Router (forwards to service on ${{PORT}})
  │
  ▼
n8n Container (binds to ${{PORT}}, serves n8n)
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ERR_CONNECTION_REFUSED` | Domain not propagated | Wait 5 min, check DNS |
| `502 Bad Gateway` | n8n not listening on correct port | Verify `N8N_PORT=${{PORT}}` |
| `ERR_SSL_PROTOCOL_ERROR` | TLS certificate not provisioned | Wait 2 min for Let's Encrypt |
| Webhook returns 404 | `WEBHOOK_URL` not updated | Set correct domain, redeploy |
| Redirect loop | `N8N_EDITOR_BASE_URL` mismatch | Ensure it matches exact domain |
