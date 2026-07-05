#!/usr/bin/env bash
# ======================================================================
# PART 3: PostgreSQL, Persistent Storage & Domain Configuration
# ======================================================================
# Module:  setup-part3-database-domain.sh
# Purpose: Configure PostgreSQL, Railway Volume, public domain, redeploy,
#          health check, and print deployment summary for n8n on Railway.
#
# Usage:
#   Source functions:  source setup-part3-database-domain.sh
#   Run all steps:     bash setup-part3-database-domain.sh [--flags]
#
# Functions:
#   setup_postgresql()   - Provision/manage PostgreSQL + set n8n env vars
#   create_volume()      - Create Railway Volume at /home/node/.n8n
#   setup_domain()       - Generate Railway public domain + update URLs
#   redeploy_service()   - Trigger railway redeploy
#   health_check()       - Ping /healthz until HTTP 200
#   setup_complete()     - Print full deployment summary
#   run_all()            - Execute all steps in order with flags
#
# Prerequisites:
#   - Railway CLI (https://docs.railway.com/develop/cli)
#   - Authenticated CLI session (railway login)
#   - Linked Railway project with n8n service deployed
# ======================================================================
set -euo pipefail

# ---- Color Codes -----------------------------------------------------------
readonly NC="\033[0m"
readonly RED="\033[0;31m"
readonly GREEN="\033[0;32m"
readonly YELLOW="\033[1;33m"
readonly BLUE="\033[0;34m"
readonly CYAN="\033[0;36m"
readonly BOLD="\033[1m"
readonly DIM="\033[2m"

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    {
  echo -e "\n${CYAN}=============================${NC}"
  echo -e "${BOLD} $*${NC}"
  echo -e "${CYAN}=============================${NC}"
}
log_header()  { echo -e "${BOLD}--- $* ---${NC}"; }
log_muted()   { echo -e "${DIM}$*${NC}"; }

# ---- Default Configuration -------------------------------------------------
DEFAULT_VOLUME_SIZE="1"
DEFAULT_VOLUME_PATH="/home/node/.n8n"
DEFAULT_VOLUME_NAME="n8n-data"
N8N_SERVICE_NAME="n8n"
HEALTH_CHECK_RETRIES=18
HEALTH_CHECK_INTERVAL=10
RAILWAY_BIN="${RAILWAY_BIN:-railway}"

# Global state (set by functions, used by downstream functions)
_N8N_DOMAIN=""
_N8N_HOSTNAME=""
_PROJECT_NAME=""
_PG_SERVICE_NAME=""
_PG_PROVISIONED=false
_REDEPLOY_TRIGGERED=false

# ---- Utility Functions -------------------------------------------------

# _check_railway_cli: Verify Railway CLI is installed and authenticated
_check_railway_cli() {
  if ! command -v "$RAILWAY_BIN" &>/dev/null; then
    log_error "Railway CLI not found."
    echo ""
    echo "  Install it with one of:"
    echo "    npm install -g @railway/cli"
    echo "    curl -fsSL https://railway.app/install.sh | sh"
    echo "    brew install railwayapp/railway/railway"
    echo ""
    echo "  Docs: https://docs.railway.com/develop/cli"
    echo ""
    return 1
  fi

  local cli_version
  cli_version=$($RAILWAY_BIN --version 2>/dev/null || echo "unknown")
  log_info "Railway CLI version: $cli_version"

  if ! $RAILWAY_BIN whoami &>/dev/null; then
    log_warn "Railway CLI is not authenticated."
    echo ""
    echo "  Run 'railway login' to authenticate:"
    echo "    $RAILWAY_BIN login"
    echo ""
    return 1
  fi

  log_success "Railway CLI detected and authenticated"
  return 0
}

# _check_project_linked: Ensure a Railway project is linked in the CWD
_check_project_linked() {
  if ! $RAILWAY_BIN status &>/dev/null; then
    log_warn "No Railway project linked in this directory."
    echo ""
    echo "  Link an existing project:"
    echo "    $RAILWAY_BIN link"
    echo ""
    echo "  Or create a new one:"
    echo "    $RAILWAY_BIN init"
    echo ""
    return 1
  fi
  log_success "Railway project linked"
  return 0
}

# _get_project_name: Retrieve the current Railway project name
_get_project_name() {
  if [[ -n "$_PROJECT_NAME" ]]; then
    echo "$_PROJECT_NAME"
    return 0
  fi

  local name=""
  name=$($RAILWAY_BIN status --json 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('\''projectName'\'','\'' '\''))" 2>/dev/null \
    || true)
  if [[ -z "$name" ]]; then
    name=$($RAILWAY_BIN status 2>/dev/null \
      | grep -i "Project" | head -1 \
      | sed 's/.*Project:\s*//I')
  fi
  name="${name:-unknown}"
  _PROJECT_NAME="$name"
  echo "$name"
}

# _service_exists: Check if a service exists by name
_service_exists() {
  local service_name="$1"
  local output
  output=$($RAILWAY_BIN service list 2>/dev/null || true)
  echo "$output" | grep -qi "$service_name"
}

# _get_env_var: Get Railway env var (with .env.local fallback)
_get_env_var() {
  local var_name="$1"
  local value=""
  value=$($RAILWAY_BIN variables get "$var_name" 2>/dev/null || echo "")
  if [[ -z "$value" && -f ".env.local" ]]; then
    value=$(grep -E "^${var_name}=" ".env.local" 2>/dev/null | head -1 | cut -d'=' -f2-)
  fi
  echo "$value"
}

# _set_env_var: Set a Railway environment variable
_set_env_var() {
  local key="$1"
  local value="$2"
  log_info "  Setting: ${key}"

  if $RAILWAY_BIN variables set "${key}=${value}" 2>/dev/null; then
    log_success "  ${key} set"
    return 0
  fi

  log_warn "  Could not set ${key} via CLI."
  log_muted "  Set it manually in Railway Dashboard -> Variables tab."
  return 1
}

# _set_env_var_batch: Set multiple environment variables
_set_env_var_batch() {
  local vars=("$@")
  if [[ ${#vars[@]} -eq 0 ]]; then return 0; fi
  local success=true
  for var_def in "${vars[@]}"; do
    local key="${var_def%%=*}"
    local value="${var_def#*=}"
    _set_env_var "$key" "$value" || success=false
  done
  $success && return 0 || return 1
}

# _prompt_yes_no: Ask a yes/no question with default
_prompt_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  local answer
  if [[ "$default" =~ ^[Yy] ]]; then
    read -rp "$prompt [Y/n]: " answer
    answer="${answer:-y}"
  else
    read -rp "$prompt [y/N]: " answer
    answer="${answer:-n}"
  fi
  [[ "$answer" =~ ^[Yy]$ ]]
}

# _prompt_value: Ask for text input with optional default
_prompt_value() {
  local prompt="$1"
  local default="${2:-}"
  local value
  if [[ -n "$default" ]]; then
    read -rp "$prompt [$default]: " value
    echo "${value:-$default}"
  else
    read -rp "$prompt: " value
    echo "$value"
  fi
}

# _detect_postgres_service: Find PostgreSQL service in project
_detect_postgres_service() {
  local svc
  for svc in postgres Postgres postgresql PostgreSQL pg PG database Database; do
    if _service_exists "$svc"; then
      echo "$svc"
      return 0
    fi
  done
  return 1
}

# ------------------------------------------------------------------
# setup_postgresql()
#   Provisions PostgreSQL in Railway and configures n8n DB env vars.
#   Uses Railway template interpolation (${{Postgres.VAR}}) so creds
#   auto-update on rotation. Detects existing service or creates new.
# ------------------------------------------------------------------
setup_postgresql() {
  log_step "STEP 1: PostgreSQL Database Setup"
  _check_railway_cli || return 1
  _check_project_linked || return 1

  local project_name
  project_name=$(_get_project_name)
  log_info "Project: ${project_name}"

  # Check for existing PostgreSQL service
  log_header "Checking for existing PostgreSQL service"
  local pg_found=false pg_svc="" detected
  detected=$(_detect_postgres_service) || true

  if [[ -n "$detected" ]]; then
    pg_found=true; pg_svc="$detected"
    log_success "PostgreSQL service found: '${pg_svc}'"
    _PG_SERVICE_NAME="$pg_svc"; _PG_PROVISIONED=true
  else
    log_warn "No PostgreSQL service detected in this project."
    echo ""
    echo "  Option A: Railway CLI (recommended)"
    echo "    $RAILWAY_BIN add postgres"
    echo ""
    echo "  Option B: Railway Dashboard"
    echo "    1. https://railway.app/project/${project_name}"
    echo "    2. New -> Database -> PostgreSQL (wait ~30s)"
    echo ""

    if _prompt_yes_no "Add PostgreSQL via Railway CLI?"; then
      log_info "Adding PostgreSQL service..."
      if $RAILWAY_BIN add postgres 2>&1; then
        log_success "PostgreSQL provisioned!"; sleep 3
        detected=$(_detect_postgres_service) || true
        pg_svc="${detected:-Postgres}"
        _PG_SERVICE_NAME="$pg_svc"; _PG_PROVISIONED=true
      else
        log_error "CLI failed. Add PostgreSQL from Railway Dashboard."
        return 1
      fi
    else
      if _prompt_yes_no "Continue without PostgreSQL (SQLite)?" "n"; then
        log_warn "Skipping PostgreSQL. Not recommended for production."
        return 0
      else
        return 1
      fi
    fi
  fi

  # Normalise service name for template interpolation
  local template_svc="$pg_svc"
  case "${pg_svc,,}" in
    postgres|postgresql|pg) template_svc="Postgres" ;;
  esac
  log_info "Template ref: \${${template_svc}}"

  # Audit current DB env vars
  log_header "Auditing current database environment variables"
  local current_db_type; current_db_type=$(_get_env_var "DB_TYPE")
  local current_host; current_host=$(_get_env_var "DB_POSTGRESDB_HOST")

  if [[ -n "$current_db_type" || -n "$current_host" ]]; then
    log_info "Existing DB config detected"
    if [[ "$current_host" == *"\${"* ]]; then
      log_success "Already using Railway template variables"
    elif [[ -n "$current_host" ]]; then
      log_warn "DB_POSTGRESDB_HOST has a hardcoded value"
      _prompt_yes_no "Migrate to Railway template variables?" && \
        log_info "Will use \${{${template_svc}.*}} references" || \
        log_info "Keeping existing hardcoded values"
    fi
  fi

  # Set n8n PostgreSQL environment variables
  log_header "Configuring n8n PostgreSQL environment variables"

  local use_templates=true
  if [[ -n "$current_host" && "$current_host" != *"\${"* ]]; then
    [[ -f ".env.local" ]] && grep -q "DB_POSTGRESDB_HOST=" ".env.local" 2>/dev/null && use_templates=false
  fi

  local pg_vars=()
  pg_vars+=("DB_TYPE=postgresdb")

  if $use_templates; then
    pg_vars+=("DB_POSTGRESDB_HOST=\${{${template_svc}.PGHOST}}")
    pg_vars+=("DB_POSTGRESDB_PORT=\${{${template_svc}.PGPORT}}")
    pg_vars+=("DB_POSTGRESDB_DATABASE=\${{${template_svc}.PGDATABASE}}")
    pg_vars+=("DB_POSTGRESDB_USER=\${{${template_svc}.PGUSER}}")
    pg_vars+=("DB_POSTGRESDB_PASSWORD=\${{${template_svc}.PGPASSWORD}}")
  elif [[ -f ".env.local" ]]; then
    for v in HOST PORT DATABASE USER PASSWORD; do
      local key="DB_POSTGRESDB_${v}"
      local val; val=$(grep "^${key}=" .env.local | head -1 | cut -d'=' -f2-)
      pg_vars+=("${key}=${val}")
    done
  else
    pg_vars+=("DB_POSTGRESDB_HOST=\${{${template_svc}.PGHOST}}")
    pg_vars+=("DB_POSTGRESDB_PORT=\${{${template_svc}.PGPORT}}")
    pg_vars+=("DB_POSTGRESDB_DATABASE=\${{${template_svc}.PGDATABASE}}")
    pg_vars+=("DB_POSTGRESDB_USER=\${{${template_svc}.PGUSER}}")
    pg_vars+=("DB_POSTGRESDB_PASSWORD=\${{${template_svc}.PGPASSWORD}}")
  fi

  _set_env_var_batch "${pg_vars[@]}"

  # Clean obsolete SQLite-only vars
  log_header "Cleaning up obsolete variables"
  for var in DB_SQLITE_HOST DB_SQLITE_PORT DB_SQLITE_DATABASE; do
    local val; val=$(_get_env_var "$var")
    [[ -n "$val" ]] && log_info "Removing $var" && $RAILWAY_BIN variables remove "$var" 2>/dev/null || true
  done

  # Verify
  log_header "Verifying PostgreSQL configuration"
  local verified=true
  local vt; vt=$(_get_env_var "DB_TYPE")
  if [[ "$vt" != "postgresdb" ]]; then
    log_warn "DB_TYPE = '${vt}' (expected: 'postgresdb')"; verified=false
  else
    log_success "DB_TYPE = postgresdb OK"
  fi

  for rv in DB_POSTGRESDB_HOST DB_POSTGRESDB_PORT DB_POSTGRESDB_DATABASE DB_POSTGRESDB_USER DB_POSTGRESDB_PASSWORD; do
    local vv; vv=$(_get_env_var "$rv")
    if [[ -z "$vv" ]]; then log_warn "${rv} = <empty>"; verified=false
    else log_success "${rv} = ${vv:0:30}..."
    fi
  done

  echo ""
  echo "  PostgreSQL Configuration Summary"
  echo "  --------------------------------"
  echo "  Service:    ${pg_svc}"
  echo "  DB_TYPE:    postgresdb"
  $use_templates && \
    echo "  Host:       \${{${template_svc}.PGHOST}} (template)" || \
    echo "  Host:       ${current_host} (hardcoded)"
  echo ""
  log_success "PostgreSQL setup complete"
  return 0
}

# ------------------------------------------------------------------
# create_volume()
#   Creates a Railway Volume mounted at /home/node/.n8n.
#   If CLI supports it, automates creation; otherwise guides via
#   dashboard. Default size 1GB, expandable later without data loss.
# ------------------------------------------------------------------
create_volume() {
  log_step "STEP 2: Persistent Storage (Railway Volume)"
  _check_railway_cli || return 1
  _check_project_linked || return 1

  local project_name
  project_name=$(_get_project_name)
  local volume_exists=false

  # Check if volume already exists
  log_header "Checking for existing volume"
  local volume_output
  volume_output=$($RAILWAY_BIN volume list 2>/dev/null || echo "")

  if echo "$volume_output" | grep -qi "$DEFAULT_VOLUME_PATH"; then
    volume_exists=true
    log_success "Volume at $DEFAULT_VOLUME_PATH already exists"
  elif echo "$volume_output" | grep -qi "$DEFAULT_VOLUME_NAME"; then
    volume_exists=true
    log_success "Volume '$DEFAULT_VOLUME_NAME' already exists"
  fi

  if $volume_exists; then
    log_success "Persistent storage configured"
    return 0
  fi

  # Explain why volumes are needed
  log_header "Why a volume is needed"
  echo ""
  echo "  Without a volume, n8n loses ALL data on every redeploy:"
  echo "    - Encryption key  -> Credentials become unreadable"
  echo "    - Database file   -> SQLite lost (mitigated by PostgreSQL)"
  echo "    - Binary data     -> Files in workflows are gone"
  echo "    - SSH keys        -> Imported keys are removed"
  echo "    - Config          -> Local settings reset"
  echo ""
  echo "  A volume survives redeploys and keeps your data safe."
  echo ""

  # Determine volume size
  echo "  Recommended sizes: 1GB (light), 5GB (moderate), 10GB+ (heavy)"
  echo ""
  local volume_size
  volume_size=$(_prompt_value "Volume size in GB" "$DEFAULT_VOLUME_SIZE")

  if ! [[ "$volume_size" =~ ^[0-9]+$ ]] || [[ "$volume_size" -lt 1 ]]; then
    log_warn "Invalid size, using default ${DEFAULT_VOLUME_SIZE}GB"
    volume_size="$DEFAULT_VOLUME_SIZE"
  fi

  # Attempt CLI creation
  log_header "Creating volume"
  if $RAILWAY_BIN volume create --help &>/dev/null 2>&1; then
    log_info "Attempting automated volume creation..."
    echo "  Name:    $DEFAULT_VOLUME_NAME"
    echo "  Mount:   $DEFAULT_VOLUME_PATH"
    echo "  Size:    ${volume_size}GB"
    echo "  Service: $N8N_SERVICE_NAME"
    echo ""

    if _prompt_yes_no "Create this volume?"; then
      if $RAILWAY_BIN volume create \
        --name "$DEFAULT_VOLUME_NAME" \
        --size "${volume_size}GB" \
        --mount "$DEFAULT_VOLUME_PATH" \
        --service "$N8N_SERVICE_NAME" 2>&1; then
        log_success "Volume created at $DEFAULT_VOLUME_PATH"
        return 0
      else
        log_warn "CLI volume create failed, guiding through dashboard..."
      fi
    fi
  else
    log_warn "Railway CLI does not support 'volume create' in this version."
  fi

  _guide_volume_dashboard "$project_name" "$volume_size"
  log_success "Volume setup complete"
  return 0
}

# _guide_volume_dashboard: Dashboard instructions for manual volume creation
_guide_volume_dashboard() {
  local project_name="$1"
  local size="${2:-1}"
  echo ""
  echo "  Create a Volume via Railway Dashboard"
  echo "  -------------------------------------"
  echo "  1. Open: https://railway.app/project/${project_name}"
  echo "  2. Select the '$N8N_SERVICE_NAME' service"
  echo "  3. Go to the 'Volumes' tab"
  echo "  4. Click 'Add Volume'"
  echo "  5. Configure:"
  echo "     Mount Path:  $DEFAULT_VOLUME_PATH"
  echo "     Size:        ${size} GB"
  echo "     Name:        $DEFAULT_VOLUME_NAME"
  echo "  6. Click 'Add Volume' to confirm"
  echo ""
  echo "  IMPORTANT: Mount path must be /home/node/.n8n"
  echo ""

  local confirm
  read -rp "Press Enter after creating volume (or type 'skip'): " confirm
  if [[ "$confirm" != "skip" ]]; then
    log_success "Volume creation acknowledged"
  else
    log_warn "Skipped. Data will NOT persist across redeploys!"
  fi
}

# ------------------------------------------------------------------
# setup_domain()
#   Generates or detects a Railway public domain and updates n8n
#   URL env vars: WEBHOOK_URL, N8N_EDITOR_BASE_URL, N8N_HOST, etc.
#   Railway provisions Let's Encrypt TLS automatically.
# ------------------------------------------------------------------
setup_domain() {
  log_step "STEP 3: Public Domain Configuration"
  _check_railway_cli || return 1
  _check_project_linked || return 1

  local project_name
  project_name=$(_get_project_name)
  local domain=""

  # Check for existing domain
  log_header "Checking for existing public domain"

  # Try CLI domain list
  local domain_output
  domain_output=$($RAILWAY_BIN domain list 2>/dev/null || echo "")
  if [[ -n "$domain_output" ]]; then
    domain=$(echo "$domain_output" | grep -oE 'https?://[a-zA-Z0-9.-]+\.up\.railway\.app' | head -1 || true)
  fi

  # Fallback: WEBHOOK_URL env var
  if [[ -z "$domain" ]]; then
    domain=$(_get_env_var "WEBHOOK_URL")
    domain="${domain%/}"
  fi

  # Fallback: .env.local
  if [[ -z "$domain" && -f ".env.local" ]]; then
    domain=$(grep -E "^RAILWAY_PUBLIC_DOMAIN=" ".env.local" 2>/dev/null | head -1 | cut -d'=' -f2-)
    [[ -n "$domain" ]] && domain="https://${domain}"
  fi

  if [[ -n "$domain" ]]; then
    log_success "Existing domain: $domain"
  else
    log_warn "No public domain found."
    echo ""
    echo "  A public domain is required for webhooks and HTTPS."
    echo ""

    if _prompt_yes_no "Generate a Railway public domain now?"; then
      log_info "Generating public domain..."
      local gen_domain=""
      if $RAILWAY_BIN domain generate --help &>/dev/null 2>&1; then
        gen_domain=$($RAILWAY_BIN domain generate 2>&1 || true)
      elif $RAILWAY_BIN domain --help &>/dev/null 2>&1; then
        gen_domain=$($RAILWAY_BIN domain 2>&1 || true)
      fi

      if [[ -n "$gen_domain" ]]; then
        echo "$gen_domain" | sed 's/^/  /'
        domain=$(echo "$gen_domain" | grep -oE 'https?://[a-zA-Z0-9.-]+\.up\.railway\.app' | head -1 || true)
      fi
    fi

    if [[ -z "$domain" ]]; then
      _guide_domain_dashboard "$project_name"
      echo ""
      domain=$(_prompt_value "Enter your Railway domain (with https://)" "")
    fi
  fi

  domain="${domain%/}"
  if [[ -z "$domain" ]]; then
    log_error "No domain configured."
    return 1
  fi

  local hostname
  hostname=$(echo "$domain" | sed -E 's|^https?://||' | sed 's|/.*||')
  log_info "Domain: $domain | Hostname: $hostname"
  _N8N_DOMAIN="$domain"
  _N8N_HOSTNAME="$hostname"

  # Update environment variables
  log_header "Updating n8n URL environment variables"
  local domain_vars=()
  domain_vars+=("WEBHOOK_URL=${domain}")
  domain_vars+=("N8N_EDITOR_BASE_URL=${domain}")
  domain_vars+=("N8N_HOST=${hostname}")
  domain_vars+=("N8N_PROTOCOL=https")
  _set_env_var_batch "${domain_vars[@]}"

  # Verify
  log_header "Verifying domain configuration"
  for cv in WEBHOOK_URL N8N_EDITOR_BASE_URL N8N_HOST N8N_PROTOCOL; do
    local val; val=$(_get_env_var "$cv")
    [[ -z "$val" ]] && log_warn "${cv} = <empty>" || log_success "${cv} = ${val}"
  done

  echo ""
  echo "  Domain Configuration Summary"
  echo "  ---------------------------"
  echo "  Domain:             $domain"
  echo "  WEBHOOK_URL:        ${domain}/"
  echo "  N8N_EDITOR_BASE_URL:${domain}/"
  echo "  N8N_HOST:           $hostname"
  echo "  N8N_PROTOCOL:       https"
  echo "  TLS:                Automatic (Let's Encrypt)"
  echo ""
  log_success "Domain setup complete"
  return 0
}

# _guide_domain_dashboard: Dashboard instructions for domain generation
_guide_domain_dashboard() {
  local project_name="$1"
  echo ""
  echo "  Generate Public Domain via Railway Dashboard"
  echo "  --------------------------------------------"
  echo "  1. Open: https://railway.app/project/${project_name}"
  echo "  2. Select the '$N8N_SERVICE_NAME' service"
  echo "  3. Settings -> Networking"
  echo "  4. Click 'Generate Domain'"
  echo "  5. Wait ~30s. Domain: https://<project>-<hash>.up.railway.app"
  echo "  6. Copy the domain URL"
  echo "  TLS is automatic (Let's Encrypt)"
  echo ""
}

# ------------------------------------------------------------------
# redeploy_service()
#   Triggers a Railway redeploy to apply config changes.
#   Railway pulls latest n8n image and restarts container.
#   Downtime: ~30-60s. Call this after changing env vars or volumes.
# ------------------------------------------------------------------
redeploy_service() {
  log_step "STEP 4: Redeploy n8n Service"
  _check_railway_cli || return 1
  _check_project_linked || return 1

  log_header "Preparing to redeploy"
  echo ""
  echo "  A redeploy will:"
  echo "    - Apply new env vars (PostgreSQL, domain URLs)"
  echo "    - Mount the volume for persistent storage"
  echo "    - Pull the latest n8nio/n8n Docker image"
  echo "    - Restart the container (~30-60s downtime)"
  echo ""

  if ! _prompt_yes_no "Trigger redeploy now?"; then
    log_info "Skipped. Run later: $RAILWAY_BIN redeploy"
    return 0
  fi

  log_header "Triggering redeploy"
  local deploy_start; deploy_start=$(date +%s)

  if $RAILWAY_BIN redeploy 2>&1; then
    local deploy_end; deploy_end=$(date +%s)
    log_success "Redeploy triggered ($(( deploy_end - deploy_start ))s)"
    _REDEPLOY_TRIGGERED=true
  else
    log_error "Redeploy command failed."
    log_info "Trigger manually from Railway Dashboard."
    return 1
  fi

  log_info "Monitor: $RAILWAY_BIN logs --service $N8N_SERVICE_NAME"
  return 0
}

# ------------------------------------------------------------------
# health_check()
#   Pings n8n /healthz up to HEALTH_CHECK_RETRIES times.
#   Retries every HEALTH_CHECK_INTERVAL seconds. Returns 0 on HTTP 200.
# ------------------------------------------------------------------
health_check() {
  log_step "STEP 5: Health Check Verification"

  local domain="${_N8N_DOMAIN:-}"
  [[ -z "$domain" ]] && domain=$(_get_env_var "WEBHOOK_URL")
  [[ -z "$domain" ]] && domain=$(_get_env_var "N8N_EDITOR_BASE_URL")

  if [[ -z "$domain" ]]; then
    log_error "No domain configured. Run setup_domain first."
    return 1
  fi

  domain="${domain%/}"
  local health_url="${domain}/healthz"

  log_header "Checking n8n health endpoint"
  log_info "URL:      $health_url"
  log_info "Retries:  $HEALTH_CHECK_RETRIES x ${HEALTH_CHECK_INTERVAL}s"
  echo ""

  local attempt=1
  while [[ $attempt -le $HEALTH_CHECK_RETRIES ]]; do
    printf "  [%2d/%2d] " "$attempt" "$HEALTH_CHECK_RETRIES"

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$health_url" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" ]]; then
      echo "HTTP 200 OK"
      echo ""
      log_success "n8n is healthy!"
      curl -I -s --max-time 10 "$health_url" 2>/dev/null | sed 's/^/  /'
      echo ""
      return 0
    fi

    if [[ "$http_code" == "000" ]]; then echo "Connection refused"
    else echo "HTTP ${http_code}"; fi

    if [[ $attempt -lt $HEALTH_CHECK_RETRIES ]]; then
      log_muted "  Waiting ${HEALTH_CHECK_INTERVAL}s..."
      sleep "$HEALTH_CHECK_INTERVAL"
    fi
    ((attempt++))
  done

  echo ""
  log_error "Health check failed after $HEALTH_CHECK_RETRIES attempts."
  echo ""
  echo "  Possible causes:"
  echo "    - Service still deploying: $RAILWAY_BIN logs --service $N8N_SERVICE_NAME"
  echo "    - Port mismatch: verify N8N_PORT=\${{PORT}}"
  echo "    - Domain not propagated yet (wait a few minutes)"
  echo "    - n8n failed to start (check deployment logs)"
  echo ""
  return 1
}

# ------------------------------------------------------------------
# setup_complete()
#   Prints a comprehensive deployment summary: URLs, credentials
#   (masked), database, volume, and next steps.
# ------------------------------------------------------------------
setup_complete() {
  log_step "Setup Complete - Deployment Summary"
  echo ""

  local domain="${_N8N_DOMAIN:-}"
  local hostname="${_N8N_HOSTNAME:-}"
  local project_name; project_name=$(_get_project_name)

  [[ -z "$domain" ]] && domain=$(_get_env_var "WEBHOOK_URL")
  [[ -z "$hostname" ]] && hostname=$(_get_env_var "N8N_HOST")
  [[ -z "$hostname" && -n "$domain" ]] && hostname=$(echo "$domain" | sed -E 's|^https?://||' | sed 's|/.*||')

  local db_type; db_type=$(_get_env_var "DB_TYPE")
  [[ -z "$db_type" ]] && db_type="SQLite (default)"

  local basic_auth; basic_auth=$(_get_env_var "N8N_BASIC_AUTH_ACTIVE")
  local auth_user; auth_user=$(_get_env_var "N8N_BASIC_AUTH_USER")
  local enc_key; enc_key=$(_get_env_var "N8N_ENCRYPTION_KEY")
  local tz; tz=$(_get_env_var "GENERIC_TIMEZONE")
  local log_lvl; log_lvl=$(_get_env_var "N8N_LOG_LEVEL")
  local pg_host; pg_host=$(_get_env_var "DB_POSTGRESDB_HOST")
  local pg_db; pg_db=$(_get_env_var "DB_POSTGRESDB_DATABASE")

  local has_volume=false
  $RAILWAY_BIN volume list 2>/dev/null | grep -qi "$DEFAULT_VOLUME_PATH" && has_volume=true

  echo "  ============================================="
  echo "       n8n Deployment Summary"
  echo "  ============================================="
  echo ""
  echo "  URL:        ${domain:-<not configured>}"
  echo "  Project:    $project_name"
  echo "  Database:   $db_type"
  [[ "$db_type" == "postgresdb" && -n "$pg_host" ]] && \
    echo "  DB Host:    $pg_host" && \
    echo "  DB Name:    $pg_db"
  echo "  Volume:     ${DEFAULT_VOLUME_PATH} ($($has_volume && echo 'mounted' || echo 'NOT MOUNTED'))"
  echo "  Protocol:   HTTPS (Railway Let's Encrypt)"
  echo ""
  echo "  Auth:       $([[ "$basic_auth" == "true" ]] && echo 'Basic Auth ('${auth_user:-<no user>}')' || echo 'Not configured')"
  echo "  Enc Key:    $([[ -n "$enc_key" ]] && echo 'SET ('${enc_key:0:8}...')' || echo 'NOT SET')"
  [[ -n "$tz" ]] && echo "  Timezone:   $tz"
  [[ -n "$log_lvl" ]] && echo "  Log Level:  $log_lvl"
  echo ""

  # Commands
  echo "  --- Quick Commands ---"
  [[ -n "$domain" ]] && echo "  curl -I ${domain}/healthz"
  echo "  $RAILWAY_BIN logs --service $N8N_SERVICE_NAME"
  echo "  $RAILWAY_BIN dashboard"
  echo ""

  # Next steps
  echo "  --- Next Steps ---"
  echo "  1. Open the editor URL in your browser"
  echo "  2. Log in (Basic Auth credentials above)"
  echo "  3. Check Settings -> Database = PostgreSQL"
  echo "  4. Create a test workflow with a Webhook trigger"
  echo "  5. Store encryption key in a password manager"
  echo ""

  echo "  For production: pin n8n version, use custom domain,"
  echo "  enable monitoring. See docs.n8n.io for details."
  echo ""

  log_success "n8n is deployed and ready at ${domain:-<no domain>}"
  return 0
}

# ------------------------------------------------------------------
# run_all()
#   Orchestrates all setup steps in dependency order.
#   Flags: --skip-pg, --skip-volume, --skip-domain, --skip-redeploy,
#          --skip-health, --non-interactive, --help
# ------------------------------------------------------------------
run_all() {
  echo ""
  echo "  ============================================="
  echo "   n8n Railway Setup - Part 3: Database & Domain"
  echo "  ============================================="
  echo ""

  local skip_pg=false skip_volume=false skip_domain=false
  local skip_redeploy=false skip_health=false non_interactive=false

  for arg in "$@"; do
    case "$arg" in
      --skip-pg|--skip-postgres) skip_pg=true ;;
      --skip-volume) skip_volume=true ;;
      --skip-domain) skip_domain=true ;;
      --skip-redeploy) skip_redeploy=true ;;
      --skip-health) skip_health=true ;;
      --non-interactive) non_interactive=true ;;
      --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --skip-pg         Skip PostgreSQL setup"
        echo "  --skip-volume     Skip volume creation"
        echo "  --skip-domain     Skip domain configuration"
        echo "  --skip-redeploy   Skip service redeploy"
        echo "  --skip-health     Skip health check"
        echo "  --non-interactive Run with defaults (no prompts)"
        echo "  --help            Show this help message"
        echo ""
        echo "Functions available when sourced:"
        echo "  source setup-part3-database-domain.sh"
        echo "  setup_postgresql, create_volume, setup_domain,"
        echo "  redeploy_service, health_check, setup_complete"
        exit 0
        ;;
    esac
  done

  if $non_interactive; then
    _prompt_yes_no() { return 0; }
    _prompt_value() { local d="${2:-y}"; echo "$d"; }
  fi

  local status=0
  ! $skip_pg      && { setup_postgresql  || status=1; }
  ! $skip_volume  && { create_volume     || status=1; }
  ! $skip_domain  && { setup_domain      || status=1; }

  if ! $skip_redeploy; then
    redeploy_service || status=1
  fi

  if ! $skip_health; then
    if ! $skip_redeploy && [[ "$_REDEPLOY_TRIGGERED" == "true" ]]; then
      log_info "Waiting 15s for container restart..."
      sleep 15
    fi
    health_check || status=1
  fi

  echo ""
  setup_complete || true
  echo ""

  if [[ $status -eq 0 ]]; then
    log_success "Part 3 completed successfully!"
  else
    log_warn "Part 3 completed with warnings (exit: $status)"
  fi
  return $status
}

# ------------------------------------------------------------------
# Main Entry Point
# If executed directly, run all steps. If sourced, only provide
# functions to the calling environment.
# ------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
  run_all "$@"
fi
