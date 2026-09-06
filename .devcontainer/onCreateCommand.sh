#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    printf '%b\n' "${BLUE}[INFO]${NC} $1"
}

log_success() {
    printf '%b\n' "${GREEN}[OK]${NC} $1"
}

log_warning() {
    printf '%b\n' "${YELLOW}[WARN]${NC} $1"
}

fail() {
    printf '%b\n' "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

is_valid_venv() {
    local venv_dir="$1"
    [[ -f "${venv_dir}/pyvenv.cfg" && -x "${venv_dir}/bin/python" ]]
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workspace_root="${HELIOS_DEVCONTAINER_WORKSPACE:-$(cd "${script_dir}/.." && pwd)}"
python_spoke="${workspace_root}/src/ai/python"
venv_dir="${python_spoke}/.venv"

printf '%s\n' "=========================================="
printf '%s\n' "HELIOS devcontainer post-create setup"
printf '%s\n' "=========================================="

[[ -f "${workspace_root}/HELIOS.sln" ]] || fail "Expected HELIOS.sln under ${workspace_root}"
[[ -f "${python_spoke}/pyproject.toml" ]] || fail "Expected Python spoke at ${python_spoke}"

require_command dotnet
require_command python3
require_command pwsh

log_info "Workspace: ${workspace_root}"
log_info "dotnet: $(dotnet --version)"
log_info "python3: $(python3 --version)"
log_info "pwsh: $(pwsh --version)"

if command -v cmake >/dev/null 2>&1 && [[ -x "${workspace_root}/scripts/build/build-native.sh" ]]; then
    log_info "Optional native spoke build"
    if "${workspace_root}/scripts/build/build-native.sh"; then
        log_success "Native spoke build completed"
    else
        log_warning "Native spoke build failed; AIHub keeps its managed fallback"
    fi
else
    log_info "Skipping optional native spoke build (cmake or build script unavailable)"
fi

if [[ -d "${venv_dir}" ]] && ! is_valid_venv "${venv_dir}"; then
    log_warning "Removing invalid Python virtual environment at ${venv_dir}"
    rm -rf "${venv_dir}"
fi

if ! is_valid_venv "${venv_dir}"; then
    log_info "Creating Python virtual environment at ${venv_dir}"
    python3 -m venv "${venv_dir}"
fi

log_info "Installing Python spoke in editable mode with dev test extras"
"${venv_dir}/bin/python" -m pip install --upgrade pip setuptools wheel
"${venv_dir}/bin/python" -m pip install -e "${python_spoke}[dev]"

log_info "Building HELIOS portable solution"
(
    cd "${workspace_root}"
    dotnet build HELIOS.sln -c Release
)
log_success "HELIOS.sln built successfully"

log_info "Readiness probe"
(
    cd "${workspace_root}"
    pwsh -NoLogo -NoProfile -File scripts/build/verify-readiness.ps1
)

printf '\n'
printf '%s\n' "Next steps:"
printf '  %s\n' "cd ${workspace_root}"
printf '  %s\n' "dotnet test tests/HELIOS.AIHub.Tests -c Release"
printf '  %s\n' "cd src/ai/python && source .venv/bin/activate && python -m pytest tests"
printf '  %s\n' "docker compose --env-file .devcontainer/local.env --profile database -f .devcontainer/docker-compose.yml up -d postgres"
printf '\n'
log_success "Devcontainer setup finished."
