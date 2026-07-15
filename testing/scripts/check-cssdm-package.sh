#!/usr/bin/env bash
# Static checks on a CSS:DM css34 package.
set -euo pipefail

CSSDM_PACKAGE="${CSSDM_PACKAGE:?CSSDM_PACKAGE is required}"
TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

tar -xzf "${CSSDM_PACKAGE}" -C "${TMP}"

fail=0
require_file() {
  local path="$1" label="$2"
  if [[ -f "${TMP}/${path}" ]]; then
    echo "OK: ${label}"
  else
    echo "FAIL: missing ${label} (${path})" >&2
    fail=1
  fi
}

require_file "addons/sourcemod/extensions/cssdm.ext.1.ep1.so" "cssdm.ext.1.ep1.so"
require_file "addons/sourcemod/extensions/cssdm.ext.2.ep1.so" "cssdm.ext.2.ep1.so"
require_file "addons/sourcemod/gamedata/cssdm.games.txt" "cssdm.games.txt"
require_file "addons/sourcemod/plugins/cssdm/dm_basics.smx" "dm_basics.smx"
require_file "addons/sourcemod/plugins/cssdm/dm_equipment.smx" "dm_equipment.smx"
require_file "addons/sourcemod/plugins/cssdm/dm_bot_quotas.smx" "dm_bot_quotas.smx"
require_file "addons/sourcemod/plugins/cssdm/dm_preset_spawns.smx" "dm_preset_spawns.smx"
require_file "addons/sourcemod/plugins/cssdm/dm_spawn_protection.smx" "dm_spawn_protection.smx"
require_file "cfg/cssdm/cssdm.cfg" "cssdm.cfg"

EXT1="${TMP}/addons/sourcemod/extensions/cssdm.ext.1.ep1.so"
EXT2="${TMP}/addons/sourcemod/extensions/cssdm.ext.2.ep1.so"

for ext in "${EXT1}" "${EXT2}"; do
  if file "${ext}" | grep -q 'ELF 32-bit LSB'; then
    echo "OK: $(basename "${ext}") is ELF 32-bit"
  else
    echo "FAIL: $(basename "${ext}") is not ELF 32-bit" >&2
    file "${ext}" >&2 || true
    fail=1
  fi
  if readelf -h "${ext}" 2>/dev/null | grep -qi 'Machine:[[:space:]]*Intel 80386'; then
    echo "OK: $(basename "${ext}") Machine=Intel 80386"
  else
    echo "FAIL: $(basename "${ext}") unexpected ELF machine" >&2
    fail=1
  fi
done

if [[ "${fail}" -ne 0 ]]; then
  echo "CSS:DM package check FAILED"
  exit 1
fi

echo "CSS:DM package check PASSED"
