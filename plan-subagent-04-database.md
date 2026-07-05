# Subagent 04: PostgreSQL Database Configuration

## Role

Provision a PostgreSQL service in Railway and configure n8n to use it as the primary database instead of the default SQLite.

---

## Why PostgreSQL Over SQLite

| Feature | SQLite (Default) | PostgreSQL (Recommended) |
|---------|-------------------|--------------------------|
| Concurrency | Single-writer | Multi-writer |
| Scalability | Limited | High |
| Data safety | Single file | ACID-compliant server |
| Railway Volumes | Required for persistence | Built-in persistence |
| Production-ready | No | Yes |

---

## Step 1: Create the PostgreSQL Service

1. In the same Railway project, click **New**
2. Select **Database** → **PostgreSQL**
3. Railway provisions a managed PostgreSQL instance (~30 seconds)
4. The service appears as `Postgres` in the project dashboard

Railway automatically sets:
- `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`
- `DATABASE_URL` (full connection string)

These are available as `${{Postgres.VAR}}` in other services.

---

## Step 2: Connect n8n to PostgreSQL

In the n8n service's **Variables** tab, add:

```env
DB_TYPE=postgresdb

DB_POSTGRESDB_HOST=${{Postgres.PGHOST}}
DB_POSTGRESDB_PORT=${{Postgres.PGPORT}}
DB_POSTGRESDB_DATABASE=${{Postgres.PGDATABASE}}
DB_POSTGRESDB_USER=${{Postgres.PGUSER}}
DB_POSTGRESDB_PASSWORD=${{Postgres.PGPASSWORD}}
```

### How Railway Interpolation Works

`${{Postgres.PGHOST}}` is a Railway template variable that:
1. References the service named "Postgres"
2. Extracts its `PGHOST` environment variable
3. Injects the value at deploy time

**Do NOT hardcode database credentials** — use template variables so they auto-update if Railway rotates credentials.

---

## Step 3: Redeploy n8n

After adding database variables:
1. Go to the n8n service
2. Click **Redeploy**
3. On restart, n8n detects `DB_TYPE=postgresdb` and runs PostgreSQL migrations automatically
4. Migration log shows:

```
Running database migrations...
Migrations completed successfully.
```

---

## Step 4: Verify Database Connection

**From within n8n**:
1. Open the editor
2. Navigate to **Settings** → **Database**
3. Confirm it shows "PostgreSQL"

**From Railway**:
1. Open the Postgres service
2. Go to **Data** tab
3. You can browse tables created by n8n (`workflow_entity`, `user`, etc.)

---

## Postgres Connection String (Alternative)

If you prefer a single connection string:

```env
DB_TYPE=postgresdb
DATABASE_URL=${{Postgres.DATABASE_URL}}
```

But using individual `DB_POSTGRESDB_*` variables is more explicit and recommended for debugging.

---

## Backup Strategy

Railway provides automatic backups for PostgreSQL:
- Daily automated snapshots
- Retained for 7 days
- Manual backup available via **Data** → **Backups**

To restore:
1. Go to Postgres service → **Data** → **Backups**
2. Select a snapshot
3. Click **Restore**

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| n8n fails to start | PostgreSQL not ready | Wait 30s, then redeploy n8n |
| `ECONNREFUSED` | Wrong host/port | Verify `${{Postgres.PGHOST}}` interpolation |
| `password authentication failed` | Wrong password | Check `${{Postgres.PGPASSWORD}}` |
| `database does not exist` | Wrong DB name | Ensure `${{Postgres.PGDATABASE}}` is correct |
| n8n still uses SQLite | `DB_TYPE` not set | Verify `DB_TYPE=postgresdb` is present |

---

## Directory Structure After This Step

```
Railway Project
├── n8n Service (Docker)
│   └── Environment Variables → PostgreSQL config
└── Postgres Service
```
