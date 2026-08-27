#!/usr/bin/env bash
set -euo pipefail

# Read-only. Keep the output out of the repo, it has your username and package list in it.
#   ./tools/audit-current.sh > /tmp/report.yml

yaml_quote() {
  local value=${1//\'/\'\'}
  printf "'%s'" "$value"
}

yaml_list() {
  local value
  while IFS= read -r value; do
    [[ -n "$value" ]] || continue
    printf '  - '
    yaml_quote "$value"
    printf '\n'
  done
}

block_scalar() {
  sed 's/^/    /'
}

source /etc/os-release

printf '%s\n' '---'
printf 'generated_at: '
yaml_quote "$(date --iso-8601=seconds)"
printf '\nos:\n'
printf '  id: '; yaml_quote "${ID:-unknown}"; printf '\n'
printf '  version: '; yaml_quote "${VERSION_ID:-unknown}"; printf '\n'
printf '  variant: '; yaml_quote "${VARIANT_ID:-unknown}"; printf '\n'
printf '  architecture: '; yaml_quote "$(uname -m)"; printf '\n'

printf '%s\n' \
  'notes:' \
  "  - 'RPM candidates include Fedora image/group packages; review them instead of copying the list wholesale.'" \
  "  - 'Flatpak output contains applications only, never runtimes.'" \
  "  - 'No browser data, histories, credentials, keys, projects, caches, or machine identifiers are collected.'"

printf '%s\n' 'enabled_repositories:'
dnf5 repolist --enabled 2>/dev/null \
  | awk 'NR > 1 && NF { print $1 }' \
  | sort -u \
  | yaml_list

printf '%s\n' 'user_installed_rpm_candidates:'
dnf5 repoquery --userinstalled --qf '%{name}|' 2>/dev/null \
  | tr '|' '\n' \
  | sort -u \
  | yaml_list

printf '%s\n' 'flatpak_applications:'
if command -v flatpak >/dev/null 2>&1; then
  while IFS=$'\t' read -r app origin branch; do
    [[ -n "$app" ]] || continue
    printf '  - application: '; yaml_quote "$app"; printf '\n'
    printf '    origin: '; yaml_quote "$origin"; printf '\n'
    printf '    branch: '; yaml_quote "$branch"; printf '\n'
  done < <(flatpak list --system --app --columns=application,origin,branch 2>/dev/null | sort)
fi

printf '%s\n' 'gnome_extensions:'
find "$HOME/.local/share/gnome-shell/extensions" \
  -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
  | sort \
  | yaml_list

printf '%s\n' 'manual_desktop_entries:'
find "$HOME/.local/share/applications" -maxdepth 1 -type f -name '*.desktop' -printf '%f\n' 2>/dev/null \
  | sort \
  | yaml_list

printf '%s\n' 'manual_application_artifacts:'
find "$HOME/AppImages" "$HOME/Apps" -maxdepth 2 -type f -printf '%p\n' 2>/dev/null \
  | sort \
  | yaml_list

printf '%s\n' 'bun_global_packages: |'
if [[ -x "$HOME/.bun/bin/bun" ]]; then
  "$HOME/.bun/bin/bun" pm ls --global 2>/dev/null | block_scalar || true
else
  printf '%s\n' '    not installed'
fi

printf '%s\n' 'cargo_installed_crates: |'
if [[ -x "$HOME/.cargo/bin/cargo" ]]; then
  "$HOME/.cargo/bin/cargo" install --list 2>/dev/null | block_scalar || true
else
  printf '%s\n' '    not installed'
fi

printf '%s\n' 'dnf_history: |'
dnf5 history list 2>/dev/null | block_scalar || printf '%s\n' '    unavailable'
