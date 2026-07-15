#!/usr/bin/env bash
# Install a built CSS:DM css34 package into SERVER_DIR.
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
CSSDM_PACKAGE="${CSSDM_PACKAGE:?CSSDM_PACKAGE is required}"

if [[ ! -f "${CSSDM_PACKAGE}" ]]; then
  echo "CSSDM_PACKAGE not found: ${CSSDM_PACKAGE}" >&2
  exit 1
fi

echo "Installing CSS:DM from ${CSSDM_PACKAGE}"
tar -xzf "${CSSDM_PACKAGE}" -C "${SERVER_DIR}/cstrike"

# Ensure DM mode is on for CI botplay.
CFG="${SERVER_DIR}/cstrike/cfg/cssdm/cssdm.cfg"
if [[ -f "${CFG}" ]]; then
  sed -i 's/^cssdm_enabled[[:space:]]*".*"/cssdm_enabled "1"/' "${CFG}" || true
fi

# Autoload extension even if plugins load order races.
mkdir -p "${SERVER_DIR}/cstrike/addons/sourcemod/extensions"
touch "${SERVER_DIR}/cstrike/addons/sourcemod/extensions/cssdm.autoload"

echo "CSS:DM installed under ${SERVER_DIR}/cstrike"
ls -la "${SERVER_DIR}/cstrike/addons/sourcemod/extensions"/cssdm* || true
ls -la "${SERVER_DIR}/cstrike/addons/sourcemod/plugins/cssdm" || true
