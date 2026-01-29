#!/usr/bin/env bash
set -euo pipefail

# ---- config defaults (override by exporting vars before calling) ----
: "${SKEL_DIR:=/etc/skel}"
: "${LIST_FILE:=/usr/local/share/gnome-ext-skel/extensions.list}"
: "${EGO_BASE:=https://extensions.gnome.org}"

ext::need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }
}

ext::detect_gnome_major() {
  ext::need gnome-shell
  local v major
  v="$(gnome-shell --version | awk '{print $3}')"
  major="${v%%.*}"
  if [[ -z "${major}" || "${major}" == "${v}" && "${v}" != *.* ]]; then
    echo "Could not parse GNOME Shell version from: $(gnome-shell --version)" >&2
    exit 1
  fi
  printf '%s\n' "${major}"
}

ext::skel_extensions_dir() {
  printf '%s\n' "${SKEL_DIR}/.local/share/gnome-shell/extensions"
}

ext::read_ids() {
  if [[ ! -f "${LIST_FILE}" ]]; then
    echo "List file not found: ${LIST_FILE}" >&2
    exit 1
  fi
  # Strip comments/blank lines, then print IDs
  sed -e 's/#.*$//' -e 's/[[:space:]]*$//' -e '/^$/d' "${LIST_FILE}" | awk '{print $1}'
}

ext::extension_info_json() {
  ext::need curl
  local id="$1" shell_major="$2"
  curl -fsSL "${EGO_BASE}/extension-info/?pk=${id}&shell_version=${shell_major}"
}

ext::parse_uuid() {
  ext::need jq
  jq -r '.uuid // empty'
}

ext::parse_download_url() {
  ext::need jq
  jq -r '.download_url // empty'
}

ext::download_zip() {
  ext::need curl
  local download_url="$1" out_zip="$2"
  curl -fsSL "${EGO_BASE}${download_url}" -o "${out_zip}"
}

ext::install_zip_to_skel() {
  ext::need unzip
  local uuid="$1" zipfile="$2"
  local ext_base dest tmp_extract
  ext_base="$(ext::skel_extensions_dir)"
  dest="${ext_base}/${uuid}"

  tmp_extract="$(mktemp -d)"
  unzip -q "${zipfile}" -d "${tmp_extract}"

  mkdir -p "${ext_base}"
  rm -rf "${dest}"
  mkdir -p "${dest}"
  cp -a "${tmp_extract}/." "${dest}/"
  rm -rf "${tmp_extract}"

  if [[ ! -f "${dest}/metadata.json" ]]; then
    echo "WARNING: ${uuid} installed but metadata.json not found under ${dest}" >&2
  fi
}

ext::install_one_id() {
  local id="$1" shell_major="$2"
  local info uuid url zipfile

  info="$(ext::extension_info_json "${id}" "${shell_major}")"
  uuid="$(printf '%s' "${info}" | ext::parse_uuid)"
  url="$(printf '%s' "${info}" | ext::parse_download_url)"

  if [[ -z "${uuid}" || -z "${url}" ]]; then
    echo "ERROR: Could not resolve extension id=${id} for GNOME ${shell_major}." >&2
    echo "It may not support GNOME ${shell_major}, or the site/API changed." >&2
    return 1
  fi

  zipfile="$(mktemp --suffix=".${uuid}.zip")"
  ext::download_zip "${url}" "${zipfile}"
  ext::install_zip_to_skel "${uuid}" "${zipfile}"
  rm -f "${zipfile}"

  echo "${uuid}"
}
