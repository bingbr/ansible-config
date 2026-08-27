#!/usr/bin/env bash
set -euo pipefail

readonly PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly DEFAULT_PROFILES="snapshots,cleanup,system,desktop,zsh_ricing,containers"
readonly ALLOWED_PROFILES="snapshots cleanup system desktop zsh_ricing remote dns desktop_dev_rust web_dev containers all"
# Profiles that read vaulted variables. Anything listed here makes a run ask for the vault password.
readonly VAULT_PROFILES="dns"

profiles="$DEFAULT_PROFILES"
check_mode=false

usage() {
  printf '%s\n' \
    "Usage: ./bootstrap.sh [options]" \
    "" \
    "Options:" \
    "  --profiles LIST  Comma-separated profiles, or 'all'." \
    "                   Default: $DEFAULT_PROFILES" \
    "  --check          Run Ansible in check and diff mode." \
    "  -h, --help       Show this help." \
    "" \
    "Profiles: snapshots, cleanup, system, desktop, zsh_ricing, remote, dns," \
    "          desktop_dev_rust, web_dev, containers"
}

while (($#)); do
  case "$1" in
    --profiles)
      [[ $# -ge 2 ]] || { printf 'error: --profiles requires a value\n' >&2; exit 2; }
      profiles="$2"
      shift 2
      ;;
    --check)
      check_mode=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$profiles" =~ ^[a-z_]+(,[a-z_]+)*$ ]]; then
  printf 'error: invalid profile list: %s\n' "$profiles" >&2
  exit 2
fi

IFS=',' read -r -a requested_profiles <<< "$profiles"
for requested_profile in "${requested_profiles[@]}"; do
  if [[ " $ALLOWED_PROFILES " != *" $requested_profile "* ]]; then
    printf 'error: unknown profile: %s\n' "$requested_profile" >&2
    exit 2
  fi
done
unset requested_profile requested_profiles

if [[ ${EUID} -eq 0 ]]; then
  printf 'error: run this script as the desktop user, not root; sudo is requested when needed.\n' >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  printf 'error: /etc/os-release is unavailable.\n' >&2
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release
if [[ ${ID:-} != fedora ]]; then
  printf 'error: Fedora is required; detected %s.\n' "${ID:-unknown}" >&2
  exit 1
fi

if [[ $(uname -m) != x86_64 ]]; then
  printf 'error: x86_64 is required; detected %s.\n' "$(uname -m)" >&2
  exit 1
fi

if ! rpm --quiet --query fedora-release-workstation; then
  printf 'error: a Fedora Workstation installation is required.\n' >&2
  exit 1
fi

if [[ -e /run/ostree-booted ]]; then
  printf 'error: Fedora Atomic/rpm-ostree systems are not supported.\n' >&2
  exit 1
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  printf 'Installing Ansible Core...\n'
  sudo dnf5 install -y ansible-core
fi

printf 'Installing the pinned Ansible collections...\n'
ansible-galaxy collection install -r "$PROJECT_DIR/requirements.yml"

playbook_args=(
  --inventory "$PROJECT_DIR/inventory/localhost.ini"
  --ask-become-pass
  --extra-vars "workstation_profile_csv=$profiles"
  --extra-vars "workstation_target_user=$USER"
)

if [[ "$check_mode" == true ]]; then
  playbook_args+=(--check --diff)
fi

# Ansible decrypts the vault file as soon as it is passed, so only pass it when it is needed.
vault_file="$PROJECT_DIR/inventory/localhost.vault.yml"

vault_needed=false
for vault_profile in $VAULT_PROFILES; do
  if [[ ",$profiles," == *",$vault_profile,"* || ",$profiles," == *,all,* ]]; then
    vault_needed=true
    break
  fi
done
unset vault_profile

if [[ "$vault_needed" == true ]]; then
  # An empty endpoint list would wipe a working DNS config.
  if [[ ! -f "$vault_file" ]]; then
    printf 'error: profiles (%s) need %s, which does not exist.\n' "$profiles" "$vault_file" >&2
    printf '       Create and encrypt it, or choose profiles that leave out: %s\n' "$VAULT_PROFILES" >&2
    exit 1
  fi

  playbook_args+=(--extra-vars "@$vault_file" --ask-vault-pass)
fi

cd "$PROJECT_DIR"
exec ansible-playbook "${playbook_args[@]}" local.yml
