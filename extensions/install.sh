#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

ext::need curl
ext::need jq
ext::need unzip
ext::need gnome-shell

shell_major="$(ext::detect_gnome_major)"
ext_base="$(ext::skel_extensions_dir)"

echo "GNOME Shell major: ${shell_major}"
echo "Installing into: ${ext_base}"
echo

mapfile -t ids < <(ext::read_ids)

if [[ "${#ids[@]}" -eq 0 ]]; then
  echo "No extension IDs found in ${LIST_FILE}" >&2
  exit 1
fi

installed=0
failed=0

for id in "${ids[@]}"; do
  echo "→ Installing ID ${id}..."
  if uuid="$(ext::install_one_id "${id}" "${shell_major}")"; then
    echo "  OK: ${uuid}"
    installed=$((installed + 1))
  else
    echo "  FAIL: ${id}"
    failed=$((failed + 1))
  fi
done

echo
echo "Done. Installed: ${installed}, Failed: ${failed}"
