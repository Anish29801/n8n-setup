#!/usr/bin/env bash
#
# setup.sh - One-click n8n deployment on Railway
# ================================================
# A unified setup script for deploying n8n workflow automation
# on Railway using the official Docker image.
#
# **Always pulls the latest n8n Docker image from Docker Hub**
# - Initial deploy: forces fresh pull via --rerun
# - Menu option 6 "Update n8n": reconnects image source + fresh pull
# - Railway `railway redeploy` reuses cached images, so this script
#   uses `railway up --rerun` and `railway service source connect`
#   to guarantee the latest n8nio/n8n:latest is always running.
#
# Supports: Linux, macOS, WSL (Windows Subsystem for Linux)
#
# Usage:
#   ./setup.sh              Interactive menu
#   ./setup.sh --full       Full non-interactive setup
#   ./setup.sh --quick      Quick deploy (minimal prompts)
#   ./setup.sh --update     Force update to latest n8n image
#   ./setup.sh --help       Show help
#
# Exit codes:
#   0  Success
#   1  General error
#   2  Missing dependency
#   3  Railway CLI / auth error
#   4  Deployment error
#   5  Health check failure
#
# Environment variables (CI mode):
#   RAILWAY_TOKEN      Project-scoped Railway token
#   RAILWAY_API_TOKEN  Account-scoped Railway token
#   CI                 Set to any value to enable non-interactive mode
#
# ================================================

set -Eeuo pipefail

# ============================================================
# SCRIPT METADATA
# ============================================================
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-setup.sh}")"

# ============================================================
# GLOBALS
# ============================================================
OS_TYPE=""
PKG_MANAGER=""
INSTALL_CMD=""

readonly DEFAULT_VOLUME_SIZE="1"
readonly DEFAULT_VOLUME_PATH="/home/node/.n8n"
readonly DEFAULT_VOLUME_NAME="n8n-data"
readonly N8N_SERVICE_NAME="n8n"
readonly N8N_DOCKER_IMAGE="n8nio/n8n"
readonly HEALTH_CHECK_RETRIES=18
readonly HEALTH_CHECK_INTERVAL=10

# ============================================================
# COLOR & MESSAGING HELPERS
# ============================================================
readonly C_RED="$(printf '\033[0;31m')"
readonly C_GREEN="$(printf '\033[0;32m')"
readonly C_YELLOW="$(printf '\033[1;33m')"
readonly C_BLUE="$(printf '\033[0;34m')"
readonly C_CYAN="$(printf '\033[0;36m')"
readonly C_BOLD="$(printf '\033[1m')"
readonly C_DIM="$(printf '\033[2m')"
readonly C_NC="$(printf '\033[0m')"

die()    { printf "${C_RED}[FATAL]${C_NC} %s\n" "$*" >&2; exit 1; }
error()  { printf "${C_RED}[ERROR]${C_NC} %s\n" "$*" >&2; }
warn()   { printf "${C_YELLOW}[WARN]${C_NC}  %s\n" "$*"; }
info()   { printf "${C_BLUE}[INFO]${C_NC}  %s\n" "$*"; }
ok()     { printf "${C_GREEN}[OK]${C_NC}    %s\n" "$*"; }
header() { printf "\n${C_CYAN}═══════════════════════════════════════════════${C_NC}\n"; \
           printf "${C_BOLD}  %s${C_NC}\n" "$*"; \
           printf "${C_CYAN}═══════════════════════════════════════════════${C_NC}\n"; }
step()   { printf "\n${C_CYAN}--- %s${C_NC}\n" "$*"; }
muted()  { printf "${C_DIM}%s${C_NC}\n" "$*"; }

# ============================================================
# CI DETECTION
# ============================================================
is_ci() {
    [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${RAILWAY_CI:-}" \
    || -n "${NONINTERACTIVE:-}" || -n "${TF_BUILD:-}" || -n "${CIRCLECI:-}" \
    || -n "${JENKINS_URL:-}" ]]
}

# ============================================================
# INTERACTIVE PROMPT HELPERS
# ============================================================

confirm() {
    local prompt="${1:-Are you sure?}" default="${2:-y}" reply
    if is_ci; then return 0; fi
    local dsp
    if [[ "$default" =~ ^[Yy] ]]; then dsp="Y/n"; else dsp="y/N"; fi
    read -r -p "$(printf "${C_YELLOW}?${C_NC} %s [${dsp}]: " "${prompt}")" reply
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[Yy] ]]
}

prompt_with_default() {
    local prompt="$1" default="${2:-}" var_name="$3" input
    if is_ci; then
        printf -v "${var_name}" "%s" "${default}"
        return 0
    fi
    if [[ -n "$default" ]]; then
        read -r -p "$(printf "${C_CYAN}?${C_NC} %s [${C_YELLOW}%s${C_NC}]: " "${prompt}" "${default}")" input
        printf -v "${var_name}" "%s" "${input:-${default}}"
    else
        read -r -p "$(printf "${C_CYAN}?${C_NC} %s: " "${prompt}")" input
        printf -v "${var_name}" "%s" "${input}"
    fi
}

# ============================================================
# PART 1: OS DETECTION & PREREQUISITES
# ============================================================

detect_os() {
    local kernel
    kernel=$(uname -s)

    case "$kernel" in
        Darwin)
            OS_TYPE="macos"
            if command -v brew &>/dev/null; then
                PKG_MANAGER="brew"
                INSTALL_CMD="brew install"
            else
                die "Homebrew is required on macOS. Install from https://brew.sh"
            fi
            ;;
        Linux)
            if [[ -f /proc/version ]] && grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
                OS_TYPE="wsl"
            elif uname -r | grep -qiE "microsoft|wsl" 2>/dev/null; then
                OS_TYPE="wsl"
            else
                OS_TYPE="linux"
            fi
            if command -v apt-get &>/dev/null; then
                PKG_MANAGER="apt"
                INSTALL_CMD="apt-get install -y"
            elif command -v dnf &>/dev/null; then
                PKG_MANAGER="dnf"
                INSTALL_CMD="dnf install -y"
            elif command -v yum &>/dev/null; then
                PKG_MANAGER="yum"
                INSTALL_CMD="yum install -y"
            else
                die "Unsupported Linux: no apt-get, dnf, or yum found."
            fi
            ;;
        *)
            die "Unsupported OS: $kernel"
            ;;
    esac
    ok "Detected OS: $OS_TYPE (pkg: $PKG_MANAGER)"
}

install_missing() {
    local packages=("$@")
    [[ ${#packages[@]} -eq 0 ]] && return 0
    info "Installing: ${packages[*]}"
    case "$PKG_MANAGER" in
        brew) brew install "${packages[@]}" ;;
        apt|yum|dnf)
            if command -v sudo &>/dev/null; then
                sudo $INSTALL_CMD "${packages[@]}"
            else
                $INSTALL_CMD "${packages[@]}"
            fi
            ;;
        *) die "Cannot auto-install. Manually install: ${packages[*]}" ;;
    esac
    local failed=()
    for pkg in "${packages[@]}"; do
        command -v "$pkg" &>/dev/null && ok "$pkg installed" || failed+=("$pkg")
    done
    [[ ${#failed[@]} -eq 0 ]] || die "Failed to install: ${failed[*]}"
}

check_prereqs() {
    local missing=()
    if [[ ${BASH_VERSINFO[0]:-0} -lt 4 ]]; then
        die "Bash 4+ required (current: ${BASH_VERSION:-unknown})"
    fi
    ok "Bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
    command -v curl &>/dev/null && ok "curl" || missing+=("curl")
    command -v openssl &>/dev/null && ok "openssl" || missing+=("openssl")
    command -v git &>/dev/null && ok "git" || warn "git not installed (optional)"
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing: ${missing[*]}"
        confirm "Attempt auto-install?" && install_missing "${missing[@]}" \
            || die "Install missing prerequisites and re-run."
    fi
    ok "All prerequisites satisfied"
}

install_railway_cli() {
    if command -v railway &>/dev/null; then
        local ver; ver=$(railway --version 2>/dev/null || true)
        ok "Railway CLI already installed${ver:+ ($ver)}"
        return 0
    fi
    info "Installing Railway CLI..."
    local installed=false
    if [[ "$OS_TYPE" == "macos" ]] && command -v brew &>/dev/null; then
        brew install railway 2>/dev/null && installed=true
    fi
    if ! $installed && [[ "$OS_TYPE" =~ ^(linux|wsl)$ ]]; then
        bash <(curl -fsSL https://railway.com/install.sh) -y 2>/dev/null && installed=true
    fi
    if ! $installed && [[ "$OS_TYPE" == "macos" ]]; then
        bash <(curl -fsSL https://railway.com/install.sh) -y 2>/dev/null && installed=true
    fi
    if ! $installed && command -v npm &>/dev/null; then
        npm install -g @railway/cli 2>/dev/null && installed=true
    fi
    if $installed && command -v railway &>/dev/null; then
        local ver; ver=$(railway --version 2>/dev/null || true)
        ok "Railway CLI installed${ver:+ ($ver)}"
    else
        die "Railway CLI install failed. Manual: https://docs.railway.com/cli"
    fi
}

check_docker() {
    if ! command -v docker &>/dev/null; then
        warn "Docker not installed (optional — for local dev)"
        return 1
    fi
    ok "Docker $(docker --version 2>/dev/null || true)"
    docker info &>/dev/null && ok "Docker daemon running" || {
        warn "Docker daemon not accessible"
        return 1
    }
}

# ============================================================
# PART 2: KEY GENERATION & RAILWAY AUTH
# ============================================================

generate_encryption_key() {
    local key=""
    if command -v openssl &>/dev/null; then
        key=$(openssl rand -hex 32 2>/dev/null) || true
    fi
    if [[ -z "$key" && -f /dev/urandom ]]; then
        key=$(head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 64) || true
    fi
    if [[ -z "$key" ]]; then
        key=$(date +%s%N | sha256sum | head -c 64) 2>/dev/null || true
    fi
    if [[ -z "$key" ]]; then
        error "Cannot generate encryption key"; return 1
    fi
    echo "$key"
}

generate_password() {
    local len="${1:-20}" pass=""
    if command -v openssl &>/dev/null; then
        pass=$(openssl rand -base64 48 2>/dev/null | head -c "$len") || true
    fi
    if [[ -z "$pass" && -f /dev/urandom ]]; then
        pass=$(head -c 60 /dev/urandom | base64 | head -c "$len") 2>/dev/null || true
    fi
    if [[ -z "$pass" ]]; then
        pass=$(date +%s%N | sha256sum | base64 | head -c "$len") 2>/dev/null || true
    fi
    [[ -n "$pass" ]] || { error "Cannot generate password"; return 1; }
    echo "$pass"
}

_railway_api_call() {
    local query="$1" variables="${2:-{}}"
    local token="${RAILWAY_API_TOKEN:-${RAILWAY_TOKEN:-}}"
    [[ -n "$token" ]] || { error "RAILWAY_API_TOKEN or RAILWAY_TOKEN required"; return 1; }
    curl -s -f -X POST "https://backboard.railway.com/graphql/v2" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}' 2>/dev/null \
            || printf '{"query":%s,"variables":%s}' "$(echo "$query" | jq -Rs .)" "$variables")"
}

railway_login() {
    local use_browserless=false
    [[ "${1:-}" == "--browserless" ]] && use_browserless=true

    header "Railway Authentication"
    if command -v railway &>/dev/null && railway whoami &>/dev/null 2>&1; then
        local who; who=$(railway whoami --json 2>/dev/null | jq -r '.name // .email // "authenticated"' 2>/dev/null || echo "authenticated")
        ok "Already logged in as: $who"
        return 0
    fi
    if [[ -n "${RAILWAY_TOKEN:-}" ]]; then
        info "RAILWAY_TOKEN detected — CI mode"
        return 0
    fi
    if [[ -n "${RAILWAY_API_TOKEN:-}" ]]; then
        info "RAILWAY_API_TOKEN detected — CI mode"
        return 0
    fi
    command -v railway &>/dev/null || die "Railway CLI not installed"
    if $use_browserless || [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        info "Browserless login..."
        railway login --browserless
    else
        info "Opening browser for Railway login..."
        railway login
    fi
    railway whoami &>/dev/null 2>&1 || die "Railway login failed"
    ok "Authentication successful"
}

# ============================================================
# PART 2: PROJECT & SERVICE CREATION
# ============================================================

_railway_cli_check() {
    command -v railway &>/dev/null || die "Railway CLI not found"
    railway whoami &>/dev/null 2>&1 || die "Not authenticated — run railway login first"
}

_railway_project_check() {
    railway status &>/dev/null || die "No Railway project linked — run railway init or railway link first"
}

_ensure_n8n_service() {
    local image="$N8N_DOCKER_IMAGE" sname="$N8N_SERVICE_NAME"
    info "Checking for n8n service..."
    local svc_json; svc_json=$(railway service list --json 2>/dev/null || echo "[]")
    if echo "$svc_json" | jq -e '.[] | select(.name == "n8n")' &>/dev/null 2>&1; then
        ok "n8n service already exists"
        return 0
    fi
    info "Creating service '$sname' from image '$image'..."
    if railway add --image "$image" --service "$sname" 2>&1; then
        ok "n8n service created"
        return 0
    fi
    warn "Direct CLI add failed — trying fallback..."
    if railway add --service "$sname" 2>&1; then
        railway service source connect --image "$image" --service "$sname" 2>&1 && {
            ok "n8n service created (fallback)"; return 0
        }
    fi
    error "Could not create n8n service. Create it manually in Railway dashboard."
    return 1
}

create_project() {
    local project_name=""
    [[ $# -gt 0 ]] && project_name="$1"
    prompt_with_default "Project name" "${project_name:-n8n-deploy}" project_name

    header "Creating Railway Project"
    _railway_cli_check
    info "Project: $project_name | Image: $N8N_DOCKER_IMAGE"

    if railway status &>/dev/null 2>&1; then
        local cur; cur=$(railway status --json 2>/dev/null | jq -r '.project.name // ""' 2>/dev/null || true)
        if [[ -n "$cur" ]]; then
            info "Already linked to '$cur'"
            confirm "Create new project anyway?" "n" || { ok "Using existing project '$cur'"; _ensure_n8n_service; return $?; }
            railway unlink 2>/dev/null || true
        fi
    fi

    info "Creating project '$project_name'..."
    railway init --name "$project_name" 2>&1 || die "Failed to create project"
    ok "Project '$project_name' created"

    _ensure_n8n_service
}

_create_project_api() {
    local project_name="$1"
    local token="${RAILWAY_API_TOKEN:-${RAILWAY_TOKEN:-}}"
    [[ -n "$token" ]] || die "RAILWAY_API_TOKEN required for API mode"

    info "[API] Creating project '$project_name'..."
    local result; result=$(_railway_api_call \
        'mutation projectCreate($input: ProjectCreateInput!) { projectCreate(input: $input) { id } }' \
        "{\"input\": {\"name\": \"$project_name\"}}") || die "API: projectCreate failed"
    local pid; pid=$(echo "$result" | jq -r '.data.projectCreate.id // empty') || die "API: no project ID"
    ok "Project created (ID: $pid)"

    local env_result; env_result=$(_railway_api_call \
        'query project($id: String!) { project(id: $id) { environments { edges { node { id name } } } } }' \
        "{\"id\": \"$pid\"}") || die "API: failed to fetch environments"
    local eid; eid=$(echo "$env_result" | jq -r '.data.project.environments.edges[0].node.id // empty') || die "API: no environments"
    info "Environment ID: $eid"

    info "[API] Creating n8n service..."
    local svc_result; svc_result=$(_railway_api_call \
        'mutation serviceCreate($input: ServiceCreateInput!) { serviceCreate(input: $input) { id name } }' \
        "{\"input\": {\"projectId\": \"$pid\", \"name\": \"n8n\", \"source\": {\"image\": \"$N8N_DOCKER_IMAGE\"}}}") || die "API: serviceCreate failed"
    local sid; sid=$(echo "$svc_result" | jq -r '.data.serviceCreate.id // empty') || die "API: no service ID"
    ok "n8n service created (ID: $sid)"

    info "[API] Triggering deploy..."
    _railway_api_call \
        'mutation serviceInstanceDeploy($serviceId: String!, $environmentId: String!) { serviceInstanceDeploy(serviceId: $serviceId, environmentId: $environmentId) }' \
        "{\"serviceId\": \"$sid\", \"environmentId\": \"$eid\"}" 2>/dev/null || \
        warn "Auto-deploy failed — deploy from dashboard"

    RAILWAY_PROJECT_ID="$pid"; RAILWAY_ENVIRONMENT_ID="$eid"; RAILWAY_SERVICE_ID="$sid"
    export RAILWAY_PROJECT_ID RAILWAY_ENVIRONMENT_ID RAILWAY_SERVICE_ID

    echo
    info "Link CLI: railway link $pid"
    info "Dashboard: https://railway.app/project/$pid"
}

# ============================================================
# PART 2: ENVIRONMENT VARIABLES
# ============================================================

set_env_vars() {
    local domain="" timezone="" auth_user="" service_name=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain) domain="$2"; shift 2 ;;
            --timezone) timezone="$2"; shift 2 ;;
            --auth-user) auth_user="$2"; shift 2 ;;
            --service) service_name="$2"; shift 2 ;;
            *) error "Unknown: $1"; return 1 ;;
        esac
    done

    header "n8n Environment Variables"

    prompt_with_default "Domain (N8N_HOST)" "${domain:-}" domain
    [[ -n "$domain" ]] || die "Domain is required"

    prompt_with_default "Timezone" "${timezone:-Asia/Kolkata}" timezone
    prompt_with_default "Auth username" "${auth_user:-admin}" auth_user

    info "Generating credentials..."
    local enc_key; enc_key=$(generate_encryption_key) || die "Failed to generate encryption key"
    local auth_pass; auth_pass=$(generate_password 20) || die "Failed to generate password"
    ok "Encryption key: ${enc_key:0:8}...${enc_key: -8}"
    ok "Auth password: ${auth_pass:0:4}...${auth_pass: -4}"

    local -a svc_flag=(); [[ -n "$service_name" ]] && svc_flag=(--service "$service_name")

    local ok_count=0 fail_count=0
    _set_one() {
        local k="$1" v="$2" label="${3:-$v}"
        if railway variables set "${k}=${v}" "${svc_flag[@]}" 2>&1; then
            printf "  ${C_GREEN}✓${C_NC} %s = %s\n" "$k" "$label"; ((ok_count++))
        else
            printf "  ${C_RED}✗${C_NC} %s\n" "$k" >&2; ((fail_count++))
        fi
    }

    step "Mandatory variables"
    info "N8N_PORT = \${{PORT}} (Railway auto-inject)"
    railway variables set 'N8N_PORT=${{PORT}}' "${svc_flag[@]}" 2>&1 || \
        railway variables set 'N8N_PORT=${PORT}' "${svc_flag[@]}" 2>&1 || \
        warn "Could not set N8N_PORT — n8n may auto-detect"
    ((ok_count++))

    _set_one "N8N_PROTOCOL" "https"
    _set_one "N8N_HOST" "$domain"
    _set_one "WEBHOOK_URL" "https://${domain}"
    _set_one "N8N_EDITOR_BASE_URL" "https://${domain}"
    _set_one "N8N_ENCRYPTION_KEY" "$enc_key" "*** (64 hex chars)"
    _set_one "N8N_BASIC_AUTH_ACTIVE" "true"
    _set_one "N8N_BASIC_AUTH_USER" "$auth_user"
    _set_one "N8N_BASIC_AUTH_PASSWORD" "$auth_pass" "*** (20 chars)"
    _set_one "GENERIC_TIMEZONE" "$timezone"

    step "Optional variables (Enter to skip)"
    local input=""
    prompt_with_default "N8N_LOG_LEVEL" "" input; [[ -n "$input" ]] && _set_one "N8N_LOG_LEVEL" "$input"
    prompt_with_default "EXECUTIONS_DATA_SAVE_ON_SUCCESS" "true" input; [[ "$input" =~ ^(true|false)$ ]] && _set_one "EXECUTIONS_DATA_SAVE_ON_SUCCESS" "$input"
    prompt_with_default "EXECUTIONS_DATA_SAVE_ON_ERROR" "true" input; [[ "$input" =~ ^(true|false)$ ]] && _set_one "EXECUTIONS_DATA_SAVE_ON_ERROR" "$input"

    echo
    info "Set: $ok_count | Failed: $fail_count"
    echo
    info "╔══════════════════════════════════════════╗"
    info "║  Save these credentials securely!        ║"
    info "║  User:     $auth_user"
    info "║  Password: $auth_pass"
    info "║  Key:      ${enc_key:0:8}... (64 hex)    "
    info "╚══════════════════════════════════════════╝"

    [[ $fail_count -eq 0 ]] || return 1
}

# ============================================================
# PART 3: POSTGRESQL DATABASE
# ============================================================

_service_exists() {
    local name="$1"
    railway service list 2>/dev/null | grep -qi "$name"
}

_get_env_var() {
    local var="$1" val=""
    val=$(railway variables get "$var" 2>/dev/null || echo "")
    if [[ -z "$val" && -f ".env.local" ]]; then
        val=$(grep -E "^${var}=" ".env.local" 2>/dev/null | head -1 | cut -d'=' -f2-)
    fi
    echo "$val"
}

_set_railway_var() {
    local k="$1" v="$2"
    railway variables set "${k}=${v}" 2>/dev/null || \
        warn "Failed to set $k — set manually in Railway dashboard"
}

setup_postgresql() {
    header "PostgreSQL Database Setup"
    _railway_cli_check; _railway_project_check

    local project_name; project_name=$(railway status --json 2>/dev/null | jq -r '.project.name // "unknown"' 2>/dev/null || echo "unknown")
    info "Project: $project_name"

    step "Checking for existing PostgreSQL"
    local pg_svc=""
    for svc in postgres Postgres postgresql PostgreSQL pg PG; do
        _service_exists "$svc" && { pg_svc="$svc"; break; }
    done

    if [[ -n "$pg_svc" ]]; then
        ok "PostgreSQL service found: '$pg_svc'"
    else
        warn "No PostgreSQL service detected"
        echo "  Add via: railway add postgres"
        echo "  Or: Railway Dashboard → New → Database → PostgreSQL"
        if confirm "Add PostgreSQL now via CLI?"; then
            railway add postgres 2>&1 || die "Failed to add PostgreSQL"
            sleep 3
            for svc in postgres Postgres postgresql PostgreSQL pg PG; do
                _service_exists "$svc" && { pg_svc="$svc"; break; }
            done
            pg_svc="${pg_svc:-Postgres}"
            ok "PostgreSQL provisioned"
        else
            confirm "Continue with SQLite (not production-safe)?" "n" || return 1
            warn "Continuing without PostgreSQL"
            return 0
        fi
    fi

    local template_svc="$pg_svc"
    case "${pg_svc,,}" in postgres|postgresql|pg) template_svc="Postgres";; esac

    step "Configuring n8n → PostgreSQL"
    _set_railway_var "DB_TYPE" "postgresdb"
    _set_railway_var "DB_POSTGRESDB_HOST" "\${{${template_svc}.PGHOST}}"
    _set_railway_var "DB_POSTGRESDB_PORT" "\${{${template_svc}.PGPORT}}"
    _set_railway_var "DB_POSTGRESDB_DATABASE" "\${{${template_svc}.PGDATABASE}}"
    _set_railway_var "DB_POSTGRESDB_USER" "\${{${template_svc}.PGUSER}}"
    _set_railway_var "DB_POSTGRESDB_PASSWORD" "\${{${template_svc}.PGPASSWORD}}"

    # Clean obsolete vars
    for var in DB_SQLITE_HOST DB_SQLITE_PORT DB_SQLITE_DATABASE; do
        local val; val=$(_get_env_var "$var")
        [[ -n "$val" ]] && railway variables remove "$var" 2>/dev/null || true
    done

    step "Verification"
    local vt; vt=$(_get_env_var "DB_TYPE")
    [[ "$vt" == "postgresdb" ]] && ok "DB_TYPE = postgresdb" || warn "DB_TYPE = $vt"
    ok "PostgreSQL configured via template refs (\${{${template_svc}.*}})"
}

# ============================================================
# PART 3: PERSISTENT VOLUME
# ============================================================

create_volume() {
    header "Persistent Storage (Railway Volume)"
    _railway_cli_check; _railway_project_check

    step "Checking existing volumes"
    local vol_out; vol_out=$(railway volume list 2>/dev/null || echo "")
    if echo "$vol_out" | grep -qi "$DEFAULT_VOLUME_PATH" || echo "$vol_out" | grep -qi "$DEFAULT_VOLUME_NAME"; then
        ok "Volume already exists at $DEFAULT_VOLUME_PATH"
        return 0
    fi

    info "Without a volume, redeploys lose encryption key, binary data, and config."
    echo "  Mount path: $DEFAULT_VOLUME_PATH"
    echo "  Size: ${DEFAULT_VOLUME_SIZE}GB (expandable later)"
    echo

    local vol_size="$DEFAULT_VOLUME_SIZE"
    prompt_with_default "Volume size (GB)" "$DEFAULT_VOLUME_SIZE" vol_size
    [[ "$vol_size" =~ ^[0-9]+$ ]] || vol_size="$DEFAULT_VOLUME_SIZE"

    step "Creating volume"
    local created=false
    if railway volume create --help &>/dev/null 2>&1; then
        if confirm "Create volume via CLI?"; then
            railway volume create \
                --name "$DEFAULT_VOLUME_NAME" \
                --size "${vol_size}GB" \
                --mount "$DEFAULT_VOLUME_PATH" \
                --service "$N8N_SERVICE_NAME" 2>&1 && created=true
        fi
    fi

    if ! $created; then
        local pname; pname=$(railway status --json 2>/dev/null | jq -r '.project.name // "unknown"' 2>/dev/null || echo "unknown")
        echo "  Create via Railway Dashboard:"
        echo "  1. https://railway.app/project/${pname}"
        echo "  2. Select '$N8N_SERVICE_NAME' → Volumes → Add Volume"
        echo "  3. Mount: $DEFAULT_VOLUME_PATH | Size: ${vol_size}GB | Name: $DEFAULT_VOLUME_NAME"
        confirm "Press Enter after creating (or type 'skip')" || { warn "Volume skipped — data may not persist!"; return 0; }
    fi

    ok "Volume ready at $DEFAULT_VOLUME_PATH"
}

# ============================================================
# PART 3: DOMAIN & HTTPS
# ============================================================

setup_domain() {
    header "Domain & HTTPS Configuration"
    _railway_cli_check; _railway_project_check

    local domain="" hostname=""
    step "Checking existing domain"
    local dom_out; dom_out=$(railway domain list 2>/dev/null || echo "")
    domain=$(echo "$dom_out" | grep -oE 'https?://[a-zA-Z0-9.-]+\.up\.railway\.app' | head -1 || true)
    [[ -z "$domain" ]] && domain=$(_get_env_var "WEBHOOK_URL")
    [[ -z "$domain" && -f ".env.local" ]] && domain=$(grep -E "^RAILWAY_PUBLIC_DOMAIN=" ".env.local" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^/https:\/\//')

    if [[ -n "$domain" ]]; then
        ok "Domain: $domain"
    else
        warn "No domain found"
        if confirm "Generate Railway public domain?"; then
            railway domain generate 2>&1 || railway domain 2>&1 || true
            dom_out=$(railway domain list 2>/dev/null || echo "")
            domain=$(echo "$dom_out" | grep -oE 'https?://[a-zA-Z0-9.-]+\.up\.railway\.app' | head -1 || true)
        fi
        if [[ -z "$domain" ]]; then
            local pname; pname=$(railway status --json 2>/dev/null | jq -r '.project.name // "unknown"' 2>/dev/null || echo "unknown")
            echo "  Generate via Dashboard:"
            echo "  https://railway.app/project/${pname} → ${N8N_SERVICE_NAME} → Settings → Networking → Generate Domain"
            prompt_with_default "Enter domain (with https://)" "" domain
        fi
    fi

    domain="${domain%/}"
    [[ -n "$domain" ]] || die "Domain is required"
    hostname=$(echo "$domain" | sed -E 's|^https?://||' | sed 's|/.*||')

    step "Updating environment variables"
    _set_railway_var "WEBHOOK_URL" "$domain"
    _set_railway_var "N8N_EDITOR_BASE_URL" "$domain"
    _set_railway_var "N8N_HOST" "$hostname"
    _set_railway_var "N8N_PROTOCOL" "https"

    echo
    echo "  Domain: $domain"
    echo "  TLS:    Automatic (Let's Encrypt)"
    ok "Domain configured"
}

# ============================================================
# PART 3: REDEPLOY (ALWAYS LATEST IMAGE) & HEALTH CHECK
# ============================================================
# Railway's `railway redeploy` reuses the cached Docker image.
# For n8n we MUST always pull the latest image from Docker Hub.
# Strategy:
#   1. Re-connect service source to n8nio/n8n (resets image ref)
#   2. Use --rerun to force a fresh image pull
#   3. Fallback: standard redeploy

redeploy_latest() {
    header "Update n8n to Latest Docker Image"
    _railway_cli_check; _railway_project_check

    info "Step 1: Reconnecting service source to $N8N_DOCKER_IMAGE:latest"
    echo "  This resets Railway's image cache and forces a fresh pull."
    railway service source connect --image "$N8N_DOCKER_IMAGE" --service "$N8N_SERVICE_NAME" 2>&1 || \
        warn "Source reconnect failed (may not be supported in this CLI version)"

    info "Step 2: Triggering redeploy with fresh image pull..."
    local start; start=$(date +%s)

    # Try --rerun first (forces rebuild/re-pull), fallback to redeploy
    if railway up --rerun --service "$N8N_SERVICE_NAME" --detach 2>/dev/null; then
        ok "Deploy triggered via --rerun (pulling latest n8n image)"
    elif railway service redeploy 2>/dev/null; then
        ok "Service redeployed (using latest available image)"
    elif railway redeploy --service "$N8N_SERVICE_NAME" -y 2>&1; then
        ok "Redeploy triggered"
    else
        error "All redeploy methods failed. Use Railway dashboard for manual redeploy."
        return 1
    fi

    local elapsed; elapsed=$(( $(date +%s) - start ))
    info "Deploy initiated in ${elapsed}s"
    info "Monitor: railway logs --service $N8N_SERVICE_NAME"
    _REDEPLOY_TRIGGERED=true
    return 0
}

redeploy_service() {
    header "Redeploy n8n Service (Latest Image)"
    _railway_cli_check; _railway_project_check

    info "This redeploy will:"
    echo "  - Pull the latest n8nio/n8n Docker image from Docker Hub"
    echo "  - Apply all env/volume/domain changes"
    echo "  - Restart the container (~30-60s downtime)"
    echo
    confirm "Proceed?" || { info "Skipped. Run: railway redeploy"; return 0; }

    if is_ci; then
        NONINTERACTIVE=1 redeploy_latest
    else
        redeploy_latest
    fi
}

# Alias for backward compatibility
redeploy_n8n() { redeploy_latest; }

health_check() {
    header "Health Check Verification"
    local domain
    domain=$(_get_env_var "WEBHOOK_URL")
    domain="${domain:-$(_get_env_var "N8N_EDITOR_BASE_URL")}"
    [[ -n "$domain" ]] || die "No domain configured — run setup_domain first"

    domain="${domain%/}"
    local url="${domain}/healthz"
    info "URL: $url | Retries: $HEALTH_CHECK_RETRIES × ${HEALTH_CHECK_INTERVAL}s"

    local attempt=1
    while [[ $attempt -le $HEALTH_CHECK_RETRIES ]]; do
        printf "  [%2d/%2d] " "$attempt" "$HEALTH_CHECK_RETRIES"
        local code; code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$url" 2>/dev/null || echo "000")
        if [[ "$code" == "200" ]]; then
            echo "HTTP 200 OK"
            echo; ok "n8n is healthy!"; return 0
        fi
        [[ "$code" == "000" ]] && echo "Connection refused" || echo "HTTP ${code}"
        ((attempt < HEALTH_CHECK_RETRIES)) && muted "  Waiting ${HEALTH_CHECK_INTERVAL}s..." && sleep "$HEALTH_CHECK_INTERVAL"
        ((attempt++))
    done

    error "Health check failed after $HEALTH_CHECK_RETRIES attempts"
    echo "  Check: railway logs --service $N8N_SERVICE_NAME"
    echo "  Ensure: N8N_PORT=\${{PORT}} is set"
    return 1
}

# ============================================================
# PART 3: SETUP COMPLETE SUMMARY
# ============================================================

setup_complete() {
    header "n8n Deployment Summary"

    local domain; domain=$(_get_env_var "WEBHOOK_URL")
    local hostname; hostname=$(_get_env_var "N8N_HOST")
    local db_type; db_type=$(_get_env_var "DB_TYPE"); db_type="${db_type:-SQLite (default)}"
    local auth_user; auth_user=$(_get_env_var "N8N_BASIC_AUTH_USER")
    local tz; tz=$(_get_env_var "GENERIC_TIMEZONE")
    local log_lvl; log_lvl=$(_get_env_var "N8N_LOG_LEVEL")
    local pg_host; pg_host=$(_get_env_var "DB_POSTGRESDB_HOST")
    local pg_db; pg_db=$(_get_env_var "DB_POSTGRESDB_DATABASE")

    local has_vol=false
    railway volume list 2>/dev/null | grep -qi "$DEFAULT_VOLUME_PATH" && has_vol=true

    echo
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║         n8n Deployment Summary               ║"
    echo "  ╠══════════════════════════════════════════════╣"
    [[ -n "$domain" ]] && printf "  ║  URL:      %-36s ║\n" "$domain"
    printf "  ║  Database: %-36s ║\n" "$db_type"
    [[ -n "$pg_host" ]] && printf "  ║  DB Host:  %-36s ║\n" "$pg_host"
    printf "  ║  Volume:   %-36s ║\n" "$($has_vol && echo "Mounted at $DEFAULT_VOLUME_PATH" || echo "NOT MOUNTED")"
    printf "  ║  HTTP:     HTTPS (Let's Encrypt)            ║\n"
    printf "  ║  Auth:     %-36s ║\n" "${auth_user:+Basic Auth ($auth_user)}"
    [[ -n "$tz" ]] && printf "  ║  Timezone: %-36s ║\n" "$tz"
    [[ -n "$log_lvl" ]] && printf "  ║  Log:      %-36s ║\n" "$log_lvl"
    echo "  ╚══════════════════════════════════════════════╝"
    echo
    info "Next steps:"
    echo "  1. Visit ${domain:-<your-domain>}/healthz"
    echo "  2. Open the editor URL in your browser"
    echo "  3. Log in with Basic Auth credentials"
    info "Commands:"
    echo "  railway logs --service $N8N_SERVICE_NAME"
    echo "  railway dashboard"
    echo
    ok "n8n is ready at ${domain:-<no domain>}"
}

# ============================================================
# PART 4: BACKUP & RESTORE
# ============================================================

backup_workflow() {
    header "📦 n8n Workflow Backup"
    local n8n_url="" api_key="" backup_dir="" ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local default_dir="./n8n-backup-${ts}"

    prompt_with_default "n8n URL (e.g., https://n8n.example.com)" "" n8n_url
    if is_ci; then
        n8n_url="${N8N_URL:-}"
        api_key="${N8N_API_KEY:-}"
        backup_dir="${BACKUP_DIR:-${default_dir}}"
    else
        [[ -z "$n8n_url" ]] && n8n_url=$(_get_env_var "WEBHOOK_URL")
        read -r -s -p "$(printf "${C_CYAN}?${C_NC} Enter n8n API key: ")" api_key; echo
        prompt_with_default "Backup directory" "$default_dir" backup_dir
    fi

    if [[ -z "${n8n_url}" || -z "${api_key}" ]]; then
        warn "URL or API key missing — showing manual instructions"
        echo "1. Export workflows from n8n: Settings → Workflows → Export"
        echo "2. Backup PostgreSQL: Railway → Postgres → Data → Backups"
        echo "3. Save N8N_ENCRYPTION_KEY (mandatory for restore)"
        return 1
    fi

    mkdir -p "${backup_dir}" || die "Cannot create $backup_dir"
    info "Exporting to: $backup_dir"

    local code
    code=$(curl -s -o "${backup_dir}/n8n-workflows.json" -w "%{http_code}" \
        -H "X-N8N-API-KEY: ${api_key}" --connect-timeout 10 --max-time 30 \
        "${n8n_url}/rest/workflows" 2>/dev/null)
    case "$code" in
        200) ok "Workflows exported" ;;
        401) die "Auth failed — check API key" ;;
        000) die "Cannot reach $n8n_url" ;;
        *)   warn "HTTP $code — partial export" ;;
    esac

    code=$(curl -s -o "${backup_dir}/n8n-credentials.json" -w "%{http_code}" \
        -H "X-N8N-API-KEY: ${api_key}" --connect-timeout 10 --max-time 30 \
        "${n8n_url}/rest/credentials" 2>/dev/null)
    [[ "$code" == "200" ]] && ok "Credentials exported" || warn "Credentials export: HTTP $code"

    echo
    ok "Backup complete → $backup_dir"
    info "Remember: back up PostgreSQL (Railway snapshots) and the encryption key!"
}

restore_workflow() {
    header "📥 n8n Workflow Restore"
    local n8n_url="" api_key="" backup_file=""

    prompt_with_default "n8n URL" "" n8n_url
    read -r -s -p "$(printf "${C_CYAN}?${C_NC} Enter n8n API key: ")" api_key; echo
    prompt_with_default "Backup JSON file path" "" backup_file

    if [[ -z "${n8n_url}" || -z "${api_key}" || -z "${backup_file}" ]]; then
        warn "Missing inputs — manual restore: Settings → Workflows → Import"
        echo "Restore PostgreSQL: Railway → Postgres → Data → Backups → Restore"
        echo "Ensure N8N_ENCRYPTION_KEY matches the original deployment!"
        return 1
    fi

    [[ -f "$backup_file" ]] || die "File not found: $backup_file"
    [[ -s "$backup_file" ]] || die "File empty: $backup_file"
    jq empty "$backup_file" 2>/dev/null || die "Invalid JSON: $backup_file"

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" -H "X-N8N-API-KEY: ${api_key}" \
        -d "@${backup_file}" --connect-timeout 10 --max-time 30 \
        "${n8n_url}/rest/workflows" 2>/dev/null)
    [[ "$code" =~ ^(200|201)$ ]] && ok "Restored successfully" || die "Restore failed (HTTP $code)"
}

# ============================================================
# PART 4: FULL SETUP ORCHESTRATION
# ============================================================

full_setup() {
    local step=0 total=11 errors=0
    header "🚀 Full n8n Deployment on Railway"

    ((step++)); step "[${step}/${total}] Prerequisites"
    detect_os; check_prereqs; ok "Prerequisites OK"

    ((step++)); step "[${step}/${total}] Railway CLI"
    install_railway_cli; ok "Railway CLI ready"

    ((step++)); step "[${step}/${total}] Railway Login"
    railway_login || die "Login failed"

    ((step++)); step "[${step}/${total}] Create Project"
    create_project || die "Project creation failed"

    ((step++)); step "[${step}/${total}] Environment Variables"
    set_env_vars || die "Env vars failed"

    ((step++)); step "[${step}/${total}] PostgreSQL"
    setup_postgresql || { warn "PostgreSQL skipped — not production-safe"; ((errors++)); }

    ((step++)); step "[${step}/${total}] Persistent Volume"
    create_volume || { warn "Volume skipped"; ((errors++)); }

    ((step++)); step "[${step}/${total}] Domain & HTTPS"
    setup_domain || { warn "Domain config had issues"; ((errors++)); }

    ((step++)); step "[${step}/${total}] Pull latest n8n image + redeploy"
    redeploy_latest || { warn "Redeploy had issues"; ((errors++)); }

    ((step++)); step "[${step}/${total}] Health Check"
    health_check || { warn "Health check failed"; ((errors++)); }

    ((step++)); step "[${step}/${total}] Summary"
    setup_complete

    echo
    if (( errors == 0 )); then
        ok "═══════════════════════════════════════════"
        ok "  Full setup completed successfully!"
        ok "═══════════════════════════════════════════"
    else
        warn "Setup finished with ${errors} warning(s)"
    fi
}

# ============================================================
# PART 4: INTERACTIVE MENU
# ============================================================

main_menu() {
    local choice
    while true; do
        printf "\033[2J\033[H" 2>/dev/null || true
        header "n8n Railway Deployer v${SCRIPT_VERSION}"
        echo "  Running on: ${OS_TYPE:-$(uname -s)}"
        echo
    echo "  1)  Full Setup           (Complete n8n deployment)"
    echo "  2)  Install Railway CLI  (only)"
    echo "  3)  Configure Environment Variables"
    echo "  4)  Set up PostgreSQL"
    echo "  5)  Set up Domain & HTTPS"
    echo "  6)  Update n8n            (Pull latest Docker image + redeploy)"
    echo "  7)  Redeploy n8n         (Reapply config, already on latest)"
    echo "  8)  Health Check"
    echo "  9)  Backup / Restore"
    echo " 10)  Exit"
    echo
    read -r -p "$(printf "${C_CYAN}▶${C_NC} Select [1-10]: ")" choice

    case "${choice}" in
        1) full_setup ;;
        2) detect_os; install_railway_cli ;;
        3) set_env_vars ;;
        4) setup_postgresql ;;
        5) setup_domain ;;
        6) redeploy_latest ;;
        7) redeploy_service ;;
        8) health_check ;;
        9) backup_restore_menu ;;
        10) echo; info "Goodbye!"; exit 0 ;;
        *) warn "Invalid option"; sleep 1 ;;
    esac
    [[ "${choice}" != 10 ]] && { echo; read -r -p "Press Enter to return to menu..."; }
    done
}

backup_restore_menu() {
    echo
    echo "  1)  Backup workflows"
    echo "  2)  Restore workflows"
    echo "  3)  Back to main menu"
    read -r -p "$(printf "${C_CYAN}▶${C_NC} Select [1-3]: ")" ch
    case "$ch" in
        1) backup_workflow ;;
        2) restore_workflow ;;
        3) return ;;
        *) warn "Invalid" ;;
    esac
}

# ============================================================
# PART 4: USAGE & CLI PARSING
# ============================================================

print_usage() {
    cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} — One-click n8n deployment on Railway

USAGE:
    ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
    -h, --help        Show this help
    --version         Show version
    --full            Non-interactive full setup (all defaults)
    --quick           Quick deploy (minimal prompts)

STEPS:
    1.  Check prerequisites (bash 4+, curl, openssl)
    2.  Install Railway CLI
    3.  Log in to Railway
    4.  Create Railway project + n8n Docker service
    5.  Set env vars (auth, encryption, domain)
    6.  Provision PostgreSQL
    7.  Create persistent volume
    8.  Configure public domain + HTTPS
    9.  Redeploy + health check

EXAMPLES:
    ${SCRIPT_NAME}              Interactive menu
    ${SCRIPT_NAME} --full       Unattended deployment
    ${SCRIPT_NAME} --quick      Fewer prompts

ENVIRONMENT:
    RAILWAY_TOKEN               Project token (CI mode)
    RAILWAY_API_TOKEN           Account token (CI mode)
    CI                          Any value = non-interactive

REQUIREMENTS: bash 4+, curl, openssl
EOF
}

main() {
    if is_ci; then export NONINTERACTIVE=1; fi

    if [[ $# -eq 0 ]]; then
        [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
        detect_os
        main_menu
        return $?
    fi

    local parsed
    parsed=$(getopt --options=h --longoptions=help,version,full,quick --name "${SCRIPT_NAME}" -- "$@") || {
        echo "Try '${SCRIPT_NAME} --help'" >&2; return 1
    }
    eval set -- "${parsed}"

    while true; do
        case "$1" in
            -h|--help) print_usage; return 0 ;;
            --version) echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"; return 0 ;;
            --full) shift; export NONINTERACTIVE=1; detect_os; full_setup; return $? ;;
            --quick) shift; export QUICK_MODE=1; detect_os; full_setup; return $? ;;
            --) shift; break ;;
            *) error "Unknown: $1"; print_usage >&2; return 1 ;;
        esac
    done

    detect_os
    main_menu
}

# ============================================================
# ENTRY POINT
# ============================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
