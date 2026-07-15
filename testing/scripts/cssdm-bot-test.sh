#!/usr/bin/env bash
# Smoke + short botplay for CSS:DM on CS:S v34, reusing fmu1337/sourcemod-css34 testing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SM_CSS34_ROOT="${SM_CSS34_ROOT:-}"
SERVER_DIR="${SERVER_DIR:-${ROOT}/.ci-server}"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
CSSDM_PACKAGE="${CSSDM_PACKAGE:-}"
RECORD_SECS="${RECORD_SECS:-180}"
RUN_BOTPLAY="${RUN_BOTPLAY:-1}"
APPLY_SRCDS_PATCH="${APPLY_SRCDS_PATCH:-1}"
APPLY_VALVE_RC="${APPLY_VALVE_RC:-1}"

if [[ -z "${CSSDM_PACKAGE}" ]]; then
  CSSDM_PACKAGE="$(ls -1 "${ROOT}"/packages/cssdm-*-css34-linux.tar.gz "${ROOT}"/OUT/package/cssdm-*-css34-linux.tar.gz 2>/dev/null | head -n1 || true)"
fi
if [[ -z "${CSSDM_PACKAGE}" || ! -f "${CSSDM_PACKAGE}" ]]; then
  echo "Set CSSDM_PACKAGE to a built cssdm-*-css34-linux.tar.gz" >&2
  exit 1
fi
CSSDM_PACKAGE="$(cd "$(dirname "${CSSDM_PACKAGE}")" && pwd)/$(basename "${CSSDM_PACKAGE}")"

resolve_sm_css34() {
  if [[ -n "${SM_CSS34_ROOT}" && -d "${SM_CSS34_ROOT}/testing/scripts" ]]; then
    return 0
  fi
  if [[ -d "${ROOT}/.ci-vendor/sourcemod-css34/testing/scripts" ]]; then
    SM_CSS34_ROOT="${ROOT}/.ci-vendor/sourcemod-css34"
    return 0
  fi
  mkdir -p "${ROOT}/.ci-vendor"
  echo "Cloning fmu1337/sourcemod-css34 for shared CI testing scripts..."
  git clone --depth 1 https://github.com/fmu1337/sourcemod-css34 "${ROOT}/.ci-vendor/sourcemod-css34"
  SM_CSS34_ROOT="${ROOT}/.ci-vendor/sourcemod-css34"
}

resolve_sm_css34
chmod +x "${ROOT}/testing/scripts/"*.sh "${SM_CSS34_ROOT}/testing/scripts/"*.sh

echo "Using sourcemod-css34 testing from ${SM_CSS34_ROOT}"
echo "Using CSS:DM package ${CSSDM_PACKAGE}"

export SERVER_DIR CACHE_DIR
export SM_CSS34_ROOT

# Package sanity before touching the server.
CSSDM_PACKAGE="${CSSDM_PACKAGE}" "${ROOT}/testing/scripts/check-cssdm-package.sh"

if [[ ! -x "${SERVER_DIR}/srcds_i686" && ! -x "${SERVER_DIR}/srcds_i486" ]]; then
  echo "Fetching CS:S v34 server tree..."
  SERVER_DIR="${SERVER_DIR}" CACHE_DIR="${CACHE_DIR}" \
    "${SM_CSS34_ROOT}/testing/scripts/fetch-server.sh"
  if [[ "${APPLY_VALVE_RC}" == "1" ]]; then
    SERVER_DIR="${SERVER_DIR}" "${SM_CSS34_ROOT}/testing/scripts/apply-valve-rc-fix.sh"
  fi
  if [[ "${APPLY_SRCDS_PATCH}" == "1" ]]; then
    SERVER_DIR="${SERVER_DIR}" "${SM_CSS34_ROOT}/testing/scripts/apply-srcds-patch.sh" || true
  fi
  KEEP_MAPS="${KEEP_MAPS:-de_dust2,de_inferno,de_nuke}" SERVER_DIR="${SERVER_DIR}" \
    "${SM_CSS34_ROOT}/testing/scripts/trim-server-maps.sh"
fi

# Install rom4s reference MM+SM (same baseline botplay uses), then CSS:DM.
export BOTPLAY_PROFILE=rom4s
unset MM_PACKAGE SM_PACKAGE USE_BUILT_MM BUILT_MM_DIR BUILT_MM_PACKAGE || true
SERVER_DIR="${SERVER_DIR}" CACHE_DIR="${CACHE_DIR}" \
  "${SM_CSS34_ROOT}/testing/scripts/install-addons.sh"
SERVER_DIR="${SERVER_DIR}" CSSDM_PACKAGE="${CSSDM_PACKAGE}" \
  "${ROOT}/testing/scripts/install-cssdm.sh"

# Short console probe: extensions + DM plugins must load.
export MAP="${MAP:-de_dust2}"
export PORT="${PORT:-27015}"
export TIMEOUT_SECS="${TIMEOUT_SECS:-120}"
export SMOKE_VERBOSE="${SMOKE_VERBOSE:-1}"
export SMOKE_CONDEBUG="${SMOKE_CONDEBUG:-1}"
export MM_VERSION_EXPECT="${MM_VERSION_EXPECT:-1.10.6}"
export SM_VERSION_EXPECT="${SM_VERSION_EXPECT:-1.11.0.6572}"
# Skip CSS34 pack commit pin: we use published rom4s packages, not this repo's pack stamp.
unset CSS34_PACK_COMMIT_EXPECT || true
unset MM_COMMIT_EXPECT SM_COMMIT_EXPECT || true

# Patch smoke expectations lightly: run stock smoke first, then assert CSSDM.
cd "${SERVER_DIR}"
export LD_LIBRARY_PATH=".:bin:${LD_LIBRARY_PATH:-}"
LOG_FILE="${SERVER_DIR}/cssdm-smoke.log"
CONSOLE_PROBE_LOG="${SERVER_DIR}/console-probe.log"
ENGINE_CONSOLE_LOG="${SERVER_DIR}/cstrike/console.log"
SM_LOG_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/logs"
rm -f "${LOG_FILE}" "${CONSOLE_PROBE_LOG}" "${ENGINE_CONSOLE_LOG}"
rm -f "${SM_LOG_DIR}"/L*.log 2>/dev/null || true
mkdir -p "${SM_LOG_DIR}"

SRCDS_BINARY="${SRCDS_BINARY:-./srcds_i686}"
if [[ ! -x "${SRCDS_BINARY}" ]]; then
  if [[ -x ./srcds_i486 ]]; then
    SRCDS_BINARY=./srcds_i486
  else
    echo "No srcds binary found" >&2
    exit 1
  fi
fi

export SERVER_DIR MAP PORT SRCDS_BINARY CONSOLE_PROBE_LOG
export CONSOLE_PROBE_TIMEOUT="${TIMEOUT_SECS}"
export SMOKE_VERBOSE SMOKE_CONDEBUG

echo "Running CSS:DM console probe (${TIMEOUT_SECS}s)..."
/usr/bin/expect "${SM_CSS34_ROOT}/testing/scripts/console-probe.exp" >"${LOG_FILE}" 2>&1 || {
  echo "Console probe failed (see ${LOG_FILE})" >&2
  tail -n 160 "${LOG_FILE}" >&2 || true
  tail -n 160 "${CONSOLE_PROBE_LOG}" >&2 || true
  exit 1
}

fail=0
require_grep() {
  local file="$1" pat="$2" label="$3"
  if [[ -f "${file}" ]] && grep -Eiq -- "${pat}" "${file}"; then
    echo "OK: ${label}"
  else
    echo "FAIL: ${label} (/${pat}/ in ${file})" >&2
    fail=1
  fi
}

require_grep "${CONSOLE_PROBE_LOG}" "Mapchange to ${MAP}|Mapchange to de_dust2" "map loaded"
require_grep "${CONSOLE_PROBE_LOG}" 'Metamod|MM:S' "meta version output"
require_grep "${CONSOLE_PROBE_LOG}" 'SourceMod|\[SM\]' "sm version output"
require_grep "${CONSOLE_PROBE_LOG}" "${MM_VERSION_EXPECT}" "Metamod ${MM_VERSION_EXPECT}"
require_grep "${CONSOLE_PROBE_LOG}" "${SM_VERSION_EXPECT}" "SourceMod ${SM_VERSION_EXPECT}"
require_grep "${CONSOLE_PROBE_LOG}" 'cssdm\.ext' "cssdm.ext listed"
require_grep "${CONSOLE_PROBE_LOG}" 'dm_basics' "dm_basics plugin listed"
require_grep "${CONSOLE_PROBE_LOG}" 'dm_equipment' "dm_equipment plugin listed"

if grep -Eiq 'cssdm\.ext.*<FAILED>|cssdm\.ext.*error' "${CONSOLE_PROBE_LOG}"; then
  echo "FAIL: cssdm.ext failed to load" >&2
  fail=1
fi
if grep -Eiq 'dm_basics.*<Failed>|dm_equipment.*<Failed>' "${CONSOLE_PROBE_LOG}"; then
  echo "FAIL: CSS:DM plugin failed" >&2
  fail=1
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "----- console probe (last 120) -----" >&2
  tail -n 120 "${CONSOLE_PROBE_LOG}" >&2 || true
  echo "CSS:DM smoke FAILED"
  exit 1
fi

echo "CSS:DM smoke PASSED"

if [[ "${RUN_BOTPLAY}" != "1" ]]; then
  exit 0
fi

echo "Running short botplay with CSS:DM (${RECORD_SECS}s)..."
export BOTPLAY_PROFILE=rom4s
export RECORD_SECS
export BOTPLAY_CFG="${BOTPLAY_CFG:-botplay-stress.cfg}"
export BOTPLAY_MAPS="${BOTPLAY_MAPS:-de_dust2,de_inferno,de_nuke}"
export REPORT_JSON="${SERVER_DIR}/cssdm-botplay-report.json"
export REPORT_TXT="${SERVER_DIR}/cssdm-botplay-report.txt"
export MIN_ROUND_START="${MIN_ROUND_START:-1}"
export MIN_ROUND_END="${MIN_ROUND_END:-1}"
export MIN_PLAYER_DEATH="${MIN_PLAYER_DEATH:-3}"
export MIN_SMAC_RUNNING="${MIN_SMAC_RUNNING:-0}"
export INSTALL_SMAC="${INSTALL_SMAC:-0}"
export INSTALL_BOTPLAY_PLUGINS="${INSTALL_BOTPLAY_PLUGINS:-1}"
export SKIP_INSTALL_ADDONS=1
export SERVER_DIR CACHE_DIR MM_VERSION_EXPECT SM_VERSION_EXPECT

# Re-copy CSS:DM after any botplay prepare steps that may touch plugins.
SERVER_DIR="${SERVER_DIR}" CSSDM_PACKAGE="${CSSDM_PACKAGE}" \
  "${ROOT}/testing/scripts/install-cssdm.sh"

"${SM_CSS34_ROOT}/testing/scripts/botplay-test.sh"

# Extra CSS:DM markers in botplay log / engine log.
BOTPLAY_LOG="${SERVER_DIR}/botplay.log"
ENGINE_CONSOLE_LOG="${SERVER_DIR}/cstrike/console.log"
cssdm_seen=0
for f in "${BOTPLAY_LOG}" "${ENGINE_CONSOLE_LOG}" "${CONSOLE_PROBE_LOG}"; do
  if [[ -f "${f}" ]] && grep -Eiq 'cssdm\.ext|\[CSSDM\]|cssdm_' "${f}"; then
    cssdm_seen=1
    break
  fi
done
if [[ "${cssdm_seen}" -ne 1 ]]; then
  echo "WARN: no explicit CSS:DM log marker during botplay (extension may still be loaded)"
fi

echo "CSS:DM botplay PASSED"
