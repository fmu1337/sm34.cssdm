#!/usr/bin/env bash
# Static checks on a CSS:DM css34 package.
set -euo pipefail

CSSDM_PACKAGE="${CSSDM_PACKAGE:?CSSDM_PACKAGE is required}"
# sm11: 1.ep1 + 2.ep1 against SM 1.10 headers (API 8). sm13: 2.ep1 only (MM 1.12 has no core-legacy).
CSSDM_SM_LINE="${CSSDM_SM_LINE:-sm11}"
case "${CSSDM_SM_LINE}" in
  sm11) EXT_API_MIN="${EXT_API_MIN:-8}"; EXT_API_MAX="${EXT_API_MAX:-8}" ;;
  sm13) EXT_API_MIN="${EXT_API_MIN:-9}"; EXT_API_MAX="${EXT_API_MAX:-11}" ;;
  *) echo "Unknown CSSDM_SM_LINE=${CSSDM_SM_LINE}" >&2; exit 1 ;;
esac
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

if [[ "${CSSDM_SM_LINE}" == "sm11" ]]; then
  require_file "addons/sourcemod/extensions/cssdm.ext.1.ep1.so" "cssdm.ext.1.ep1.so"
fi
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

EXTS=("${EXT2}")
if [[ "${CSSDM_SM_LINE}" == "sm11" ]]; then
  EXTS=("${EXT1}" "${EXT2}")
fi

# Extension API version: the immediate returned by IExtensionInterface::GetExtensionVersion().
ext_api_version() {
  local so="$1" addr size end imm
  read -r addr size < <(nm -S -C --defined-only "${so}" 2>/dev/null |
    awk '/::GetExtensionVersion\(\)/ { print $1, $2; exit }') || true
  [[ -n "${addr:-}" && -n "${size:-}" ]] || return 1
  end="$(printf '0x%x' $((0x${addr} + 0x${size})))"
  imm="$(objdump -d --start-address="0x${addr}" --stop-address="${end}" "${so}" |
    grep -oE 'mov +\$0x[0-9a-f]+,%eax' | head -n1 | grep -oE '0x[0-9a-f]+')" || return 1
  echo $((imm))
}

for ext in "${EXTS[@]}"; do
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

for ext in "${EXTS[@]}"; do
  [[ -f "${ext}" ]] || continue
  if api="$(ext_api_version "${ext}")"; then
    if (( api >= EXT_API_MIN && api <= EXT_API_MAX )); then
      echo "OK: $(basename "${ext}") extension API ${api} (want ${EXT_API_MIN}..${EXT_API_MAX})"
    else
      echo "FAIL: $(basename "${ext}") extension API ${api} (want ${EXT_API_MIN}..${EXT_API_MAX})" >&2
      fail=1
    fi
  else
    echo "FAIL: $(basename "${ext}") could not read GetExtensionVersion()" >&2
    fail=1
  fi
done

if [[ "${fail}" -ne 0 ]]; then
  echo "CSS:DM package check FAILED"
  exit 1
fi

echo "CSS:DM package check PASSED"
