# Subagent 05: Persistent Storage & Encryption Key

## Role

Configure Railway Volumes for persistent n8n data and set a permanent encryption key so credentials survive redeployments.

---

## Part A: Persistent Storage (Railway Volume)

### Why Volumes Matter

Without a volume, Railway destroys the container's filesystem on every redeploy. This means:

| Data Lost | Impact |
|-----------|--------|
| Encryption key file | All stored credentials become unrecoverable |
| Local configuration | Database connection, settings reset |
| Binary data files | Workflow binary data lost |
| SQLite database | **All workflows and credentials lost** (mitigated by PostgreSQL) |
| SSH keys | Any imported keys removed |

### Create a Volume

1. Open the n8n service in Railway Dashboard
2. Go to the **Volumes** tab
3. Click **Add Volume**
4. Configure:

| Field | Value |
|-------|-------|
| Mount Path | `/home/node/.n8n` |
| Size | Start with 1 GB (expandable later) |
| Name | `n8n-data` (or similar descriptive name) |

### What Gets Stored

The mount path `/home/node/.n8n` is n8n's home directory. It stores:

```
/home/node/.n8n/
├── config         # Local n8n config (database settings, encryption key)
├── database.sqlite  # Only if NOT using PostgreSQL
├── binaryData/    # Binary files (images, PDFs, etc.)
├── ssh/          # SSH keys (if configured)
└── secrets/      # Encrypted credential secrets
```

### Volume Sizing Guide

| Use Case | Recommended Size |
|----------|-----------------|
| Light usage, no binary data | 1 GB |
| Moderate workflows, some files | 5 GB |
| Heavy binary data (PDFs, images) | 10-20 GB |
| Enterprise / data-heavy | 50+ GB |

Railway volumes can be resized later without data loss.

---

## Part B: Encryption Key

### Purpose

The `N8N_ENCRYPTION_KEY` encrypts all sensitive data stored by n8n:
- Credentials (API keys, passwords, tokens)
- OAuth tokens
- Webhook secrets
- Database connection strings in the config file

### Generate a Key

```bash
openssl rand -hex 32
```

Example output:

```
6fd81b35af7d3f5f14e92d0c58b7d3ecb4bb0fd5c62c4a2f4ef5a7d0b2f87e34
```

### Set the Key as an Environment Variable

Add to n8n service Variables:

```env
N8N_ENCRYPTION_KEY=6fd81b35af7d3f5f14e92d0c58b7d3ecb4bb0fd5c62c4a2f4ef5a7d0b2f87e34
```

### Critical Rules

| Rule | Explanation |
|------|-------------|
| **Never change after first use** | Existing credentials become permanently unreadable |
| **Store the key securely** | Password manager, vault, or encrypted note |
| **Set BEFORE storing credentials** | Changing after credentials exist renders them inaccessible |
| **Same key for all replicas** | If scaling horizontally, all instances must use the same key |

### Key Rotation (if absolutely necessary)

1. Export all workflows and credentials from the old instance
2. Deploy a fresh n8n with the new key
3. Re-import everything (you will need to re-enter credential values)
4. Delete the old instance

---

## Verification Checklist

After completing both steps:

- [ ] Volume mounted at `/home/node/.n8n` (check Volumes tab)
- [ ] Volume size is sufficient for expected data
- [ ] `N8N_ENCRYPTION_KEY` set in Environment Variables
- [ ] Key is stored securely in a password manager
- [ ] Key was set **before** any credentials were saved

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Credentials lost after redeploy | Volume missing or wrong mount path | Verify `/home/node/.n8n` |
| "Cannot decrypt" errors | Encryption key changed | Restore original key or re-import credentials |
| Volume disk full | Binary data accumulation | Resize volume or set `EXECUTIONS_DATA_SAVE_ON_SUCCESS=none` |
| Volume not attaching | Name conflict | Delete unused volumes with same name |
