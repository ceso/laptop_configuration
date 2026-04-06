#!/usr/bin/env bash
# shellcheck shell=bash
# Bootstrap a fresh Linux laptop
set -euo pipefail

LOG_FILE="/tmp/bootstrap_$(date -u +"%Y_%m_%d").log"
REPO_DIR="${HOME}/Projects/laptop_configuration"
REPO_URL="https://github.com/ceso/laptop_configuration.git"
REPO_BRANCH="master"
HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
HOMEBREW_BIN_PATH="/home/linuxbrew/.linuxbrew/bin"
UV_INSTALL_URL="https://astral.sh/uv/install.sh"
UV_BIN_PATH="${HOME}/.local/bin"
INVENTORY_FILE="inventory.ini"
PLAYBOOK="laptop.yml"
LAPTOP="tuxedo"
LAPTOP_PROVIDED="false"
LAPTOP_HOSTNAME=""

usage() {
  cat <<'EOF'
Usage: bash bootstrap.sh [OPTIONS]

Options:
  --repo-dir <path>     Directory to clone the repo into (default: ~/Projects/laptop_configuration)
  --laptop <name>       Target laptop name (default: tuxedo)
  --hostname <hostname> Hostname for the laptop (only set if provided)
  -h, --help            Show this help message
EOF
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      usage
      ;;
    --repo-dir)
      REPO_DIR="${2:-}"
      if [[ -z "${REPO_DIR}" ]]; then
        echo "ERROR: --repo-dir requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --laptop)
      LAPTOP="${2:-}"
      if [[ -z "${LAPTOP}" ]]; then
        echo "ERROR: --laptop requires a value" >&2
        exit 1
      fi
      LAPTOP_PROVIDED=true
      shift 2
      ;;
    --hostname)
      LAPTOP_HOSTNAME="${2:-}"
      if [[ -z "${LAPTOP_HOSTNAME}" ]]; then
        echo "ERROR: --hostname requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
    esac
  done

  PLAYBOOK="${REPO_DIR}/${PLAYBOOK}"
}

logger() {
  local level="$1"
  shift
  local msg="$*"
  local datetime
  datetime="$(date -u +"%Y-%m-%d %H:%M:%S")"
  local color=""
  local reset='\033[0m'

  case "${level}" in
    INFO) color='\033[0;32m' ;;
    WARN) color='\033[0;33m' ;;
    ERROR) color='\033[0;31m' ;;
  esac

  echo -e "${datetime} ${color}${level}${reset} ${msg}" >&2
  echo "${datetime} ${level} ${msg}" >>"${LOG_FILE}"

  if [ "${level}" = "ERROR" ]; then
    exit 1
  fi
}

run_playbook() {
  logger INFO "Running laptop bootstrap playbook"
  ansible-playbook "${PLAYBOOK}" -i "${INVENTORY_FILE}" --ask-become-pass
}

ansible_galaxy_install() {
  local host_reqs="${REPO_DIR}/host_vars/${LAPTOP}/requirements.yml"
  local path_requirement_files=("${REPO_DIR}/requirements.yml")

  if [[ -f "${host_reqs}" ]]; then path_requirement_files+=("${host_reqs}"); fi

  for path_requirement in "${path_requirement_files[@]}"; do
    logger INFO "Installing required Ansible collections and roles from: ${path_requirement}"
    ansible-galaxy collection install -r "${path_requirement}" --force
    ansible-galaxy role install -r "${path_requirement}" --force
  done
}

prompt_host_setup() {
  local answer

  if [[ "${LAPTOP_PROVIDED}" == "true" ]]; then
    logger INFO "Using laptop: ${LAPTOP}"
    logger INFO "Please ensure ${REPO_DIR}/host_vars/${LAPTOP}/ exists with your config files"
    echo ""
    read -rp $'\033[0;36m>>>\033[0m Have you placed ${LAPTOP} host_vars directory? [y/N] ' answer
    case "${answer}" in
      [yY] | [yY][eE][sS]) ;;
      *) logger ERROR "Aborted by user" ;;
    esac
  else
    logger INFO "Using default laptop: ${LAPTOP}"
  fi

  if [[ ! -d "${REPO_DIR}/host_vars/${LAPTOP}" ]]; then
    logger ERROR "Directory ${REPO_DIR}/host_vars/${LAPTOP} not found"
  fi

  sed -i "s|^  hosts: .*|  hosts: ${LAPTOP}|" "${PLAYBOOK}"
  logger INFO "Generating inventory file for '${LAPTOP}' laptop"
  INVENTORY_FILE="${REPO_DIR}/${INVENTORY_FILE}"
  echo "${LAPTOP} ansible_connection=local" >"${INVENTORY_FILE}"
}

clone_repo() {
  if [ -d "${REPO_DIR}/.git" ]; then
    logger INFO "Repo already cloned, updating to latest"
    git -C "${REPO_DIR}" fetch origin
    git -C "${REPO_DIR}" reset --hard "origin/${REPO_BRANCH}"
    return
  fi

  logger INFO "Cloning repo to ${REPO_DIR}"
  mkdir -p "$(dirname "${REPO_DIR}")"
  git clone --branch "${REPO_BRANCH}" "${REPO_URL}" "${REPO_DIR}"
}

is_tool_installed() {
  local tool_bin_path="${1}"

  if [[ -x "${tool_bin_path}" ]]; then
    logger INFO "'$(basename "${tool_bin_path}")' already installed"
    return 0
  fi

  return 1
}

install_ansible() {
  if is_tool_installed "${UV_BIN_PATH}/ansible-playbook"; then return 0; fi
  logger INFO "Installing Ansible via uv"
  sleep 2
  "${UV_BIN_PATH}/uv" tool install -q ansible --with ansible-lint --with ansible-doctor
}

safe_run_remote_script() {
  local url="$1"
  local script_name="${2:-remote-script}"
  local bash_env_vars="${3:-}"
  local answer
  local tmpfile
  tmpfile="$(mktemp)"

  logger INFO "Downloading ${script_name} for review"
  curl -fsSL -o "${tmpfile}" "${url}"

  logger INFO "Displaying ${script_name} - review before executing. After review, leave pager"
  sleep 2
  less "${tmpfile}"
  echo ""
  read -rp $'\033[0;36m>>>\033[0m '"Execute ${script_name}? [y/N] " answer
  case "${answer}" in
    [yY] | [yY][eE][sS])
      logger INFO "Executing ${script_name}"
      if [[ -n "${bash_env_vars}" ]]; then
        env "${bash_env_vars}" /bin/bash "${tmpfile}"
      else
        /bin/bash "${tmpfile}"
      fi
      ;;
    *)
      rm -f "${tmpfile}"
      logger WARN "Execution of ${script_name} aborted by user"
      ;;
  esac

  rm -f "${tmpfile}"
}

install_homebrew() {
  if is_tool_installed "${HOMEBREW_BIN_PATH}/brew"; then return 0; fi
  safe_run_remote_script "${HOMEBREW_INSTALL_URL}" "Homebrew installer" "NONINTERACTIVE=1"
  local brew_env
  brew_env="$("${HOMEBREW_BIN_PATH}"/brew shellenv)"
  eval "${brew_env}"
}

install_uv() {
  if is_tool_installed "${UV_BIN_PATH}/uv"; then return 0; fi
  safe_run_remote_script "${UV_INSTALL_URL}" "uv installer" "UV_INSTALL_DIR=${UV_BIN_PATH}"
  export PATH="${UV_BIN_PATH}:${PATH}"
}

install_system_deps() {
  logger INFO "Attempting to update system & install dependencies"
  sleep 2

  if [ -f /etc/os-release ]; then
    # shellcheck source=/etc/os-release
    . /etc/os-release
    case "${ID_LIKE:-${ID}}" in
      *debian* | ubuntu)
        sudo apt-get update -q
        sudo apt-get install -y -q build-essential git
        ;;
      *fedora* | *rhel*)
        sudo dnf update -y -q
        sudo dnf install -y -q @development-tools
        ;;
      *) logger ERROR "Unsupported OS: ${ID}" ;;
    esac
  else
    logger ERROR "Cannot detect OS: /etc/os-release not found"
  fi
}

main() {
  if [[ $# -eq 1 ]]; then
    usage
  fi

  parse_args "$@"
  logger INFO "Starting laptop bootstrap"
  logger INFO "Repo directory: ${REPO_DIR}"

  if [[ -n "${LAPTOP_HOSTNAME}" ]]; then
    logger INFO "Setting laptop hostname to: ${LAPTOP_HOSTNAME}"
    sudo hostnamectl set-hostname "${LAPTOP_HOSTNAME}"
  fi
  
  install_system_deps
  install_uv
  install_ansible
  install_homebrew
  clone_repo
  prompt_host_setup
  ansible_galaxy_install
  run_playbook
  logger INFO "Bootstrap complete"
  logger INFO "Log saved to ${LOG_FILE}"
}

main "$@"
