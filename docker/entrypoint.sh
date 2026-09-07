#!/usr/bin/env bash
set -Eeuo pipefail

readonly HERMES_BIN="/opt/hermes/.venv/bin/hermes"
readonly HERMES_PYTHON="/opt/hermes/.venv/bin/python"
readonly DATA_DIR="${HERMES_HOME:-/home/container}"

export HOME="${DATA_DIR}"
export HERMES_HOME="${DATA_DIR}"
export HERMES_WRITE_SAFE_ROOT="${DATA_DIR}"
export HERMES_LAZY_INSTALL_TARGET="${DATA_DIR}/lazy-packages"

mkdir -p "${DATA_DIR}" "${HERMES_LAZY_INSTALL_TARGET}"
cd "${DATA_DIR}"

if [[ ! -e "${DATA_DIR}/config.yaml" ]]; then
    echo "[Pterodactyl] Creating the initial Hermes configuration."

    # Start from the schema-matched template baked into the upstream image.
    # This keeps _config_version current when the weekly image rebuild picks
    # up a newer Hermes release.
    if [[ -f /opt/hermes/cli-config.yaml.example ]]; then
        cp /opt/hermes/cli-config.yaml.example "${DATA_DIR}/config.yaml"
    fi

    "${HERMES_BIN}" config set model.provider "${MODEL_PROVIDER:-openrouter}"
    "${HERMES_BIN}" config set model.default "${MODEL_NAME:-anthropic/claude-sonnet-4.6}"

    if [[ -n "${MODEL_BASE_URL:-}" ]]; then
        "${HERMES_BIN}" config set model.base_url "${MODEL_BASE_URL}"
    fi
fi

if [[ ! -e "${DATA_DIR}/SOUL.md" && -f /opt/hermes/docker/SOUL.md ]]; then
    echo "[Pterodactyl] Seeding SOUL.md."
    cp /opt/hermes/docker/SOUL.md "${DATA_DIR}/SOUL.md"
fi

if [[ -f "${DATA_DIR}/config.yaml" && -f /opt/hermes/scripts/docker_config_migrate.py ]]; then
    echo "[Pterodactyl] Migrating the Hermes configuration."
    "${HERMES_PYTHON}" /opt/hermes/scripts/docker_config_migrate.py || \
        echo "[Pterodactyl] WARNING: Hermes config migration failed; continuing." >&2
fi

if [[ -d /opt/hermes/skills && -f /opt/hermes/tools/skills_sync.py ]]; then
    echo "[Pterodactyl] Synchronizing bundled skills."
    "${HERMES_PYTHON}" /opt/hermes/tools/skills_sync.py || \
        echo "[Pterodactyl] WARNING: Bundled skill sync failed; continuing." >&2
fi

if [[ -z "${AGENT_BROWSER_EXECUTABLE_PATH:-}" && -d "${PLAYWRIGHT_BROWSERS_PATH:-/opt/hermes/.playwright}" ]]; then
    browser_path="$(find "${PLAYWRIGHT_BROWSERS_PATH:-/opt/hermes/.playwright}" -type f -executable \
        \( -name chrome -o -name chromium -o -name chrome-headless-shell \
           -o -name headless_shell -o -name chromium-browser \) -print -quit 2>/dev/null || true)"
    if [[ -n "${browser_path}" ]]; then
        export AGENT_BROWSER_EXECUTABLE_PATH="${browser_path}"
    fi
fi

generate_token() {
    local bytes="${1}"
    "${HERMES_PYTHON}" -c "import secrets; print(secrets.token_urlsafe(${bytes}))"
}

read_or_create_secret() {
    local path="${1}"
    local bytes="${2}"

    if [[ ! -s "${path}" ]]; then
        umask 077
        generate_token "${bytes}" > "${path}"
    fi

    tr -d '\r\n' < "${path}"
}

is_true() {
    case "${1,,}" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

dashboard_pid=""
gateway_pid=""

shutdown() {
    trap - INT TERM
    [[ -z "${gateway_pid}" ]] || kill -TERM "${gateway_pid}" 2>/dev/null || true
    [[ -z "${dashboard_pid}" ]] || kill -TERM "${dashboard_pid}" 2>/dev/null || true
    [[ -z "${gateway_pid}" ]] || wait "${gateway_pid}" 2>/dev/null || true
    [[ -z "${dashboard_pid}" ]] || wait "${dashboard_pid}" 2>/dev/null || true
}

trap shutdown INT TERM

if [[ -z "${API_SERVER_KEY:-}" ]]; then
    echo "[Pterodactyl] Loading the persistent API server key."
    export API_SERVER_KEY
    API_SERVER_KEY="$(read_or_create_secret "${DATA_DIR}/.api-server-key" 48)"
    if is_true "${API_SERVER_ENABLED:-false}"; then
        echo "[Pterodactyl] An API server key was generated at .api-server-key"
    fi
elif [[ ${#API_SERVER_KEY} -lt 16 ]]; then
    echo "[Pterodactyl] ERROR: API_SERVER_KEY must contain at least 16 characters." >&2
    exit 1
fi

if is_true "${API_SERVER_ENABLED:-false}"; then
    export API_SERVER_HOST="0.0.0.0"
else
    # Hermes' dashboard uses this loopback control plane for gateway actions.
    # Wings cannot publish it unless the administrator explicitly enables it.
    export API_SERVER_HOST="127.0.0.1"
fi

if is_true "${HERMES_DASHBOARD:-true}" && \
    [[ "${API_SERVER_PORT:-8642}" == "${HERMES_DASHBOARD_PORT:-${SERVER_PORT:-9119}}" ]]; then
    echo "[Pterodactyl] ERROR: The dashboard and API server cannot use the same port." >&2
    exit 1
fi

if is_true "${HERMES_DASHBOARD:-true}"; then
    export HERMES_DASHBOARD_HOST="${HERMES_DASHBOARD_HOST:-0.0.0.0}"
    export HERMES_DASHBOARD_PORT="${HERMES_DASHBOARD_PORT:-${SERVER_PORT:-9119}}"
    export HERMES_DASHBOARD_BASIC_AUTH_USERNAME="${HERMES_DASHBOARD_BASIC_AUTH_USERNAME:-admin}"

    if [[ -z "${HERMES_DASHBOARD_BASIC_AUTH_PASSWORD:-}" ]]; then
        export HERMES_DASHBOARD_BASIC_AUTH_PASSWORD
        HERMES_DASHBOARD_BASIC_AUTH_PASSWORD="$(read_or_create_secret "${DATA_DIR}/.dashboard-password" 24)"
        echo "[Pterodactyl] A dashboard password was generated at .dashboard-password"
    fi

    if [[ -z "${HERMES_DASHBOARD_BASIC_AUTH_SECRET:-}" ]]; then
        export HERMES_DASHBOARD_BASIC_AUTH_SECRET
        HERMES_DASHBOARD_BASIC_AUTH_SECRET="$(read_or_create_secret "${DATA_DIR}/.dashboard-session-secret" 48)"
    fi

    echo "[Pterodactyl] Starting Hermes dashboard on 0.0.0.0:${HERMES_DASHBOARD_PORT}."
    "${HERMES_BIN}" dashboard \
        --host "${HERMES_DASHBOARD_HOST}" \
        --port "${HERMES_DASHBOARD_PORT}" \
        --no-open &
    dashboard_pid="$!"
fi

startup_command="${STARTUP:-${HERMES_BIN} gateway run --no-supervise --external-supervisor}"
echo "[Pterodactyl] Hermes is starting."
echo "${DATA_DIR}\$ ${startup_command}"

if [[ -z "${dashboard_pid}" ]]; then
    exec /bin/bash -lc "${startup_command}"
fi

/bin/bash -lc "${startup_command}" &
gateway_pid="$!"

set +e
wait "${gateway_pid}"
gateway_status="$?"
set -e

gateway_pid=""
if [[ -n "${dashboard_pid}" ]]; then
    kill -TERM "${dashboard_pid}" 2>/dev/null || true
    wait "${dashboard_pid}" 2>/dev/null || true
    dashboard_pid=""
fi

exit "${gateway_status}"
