#!/usr/bin/env bash
# Run cssdm_selftest on a CS:S v34 server, against the released cssdm.ext (MODE=ext)
# or against plugin/scripting/cssdm.sp (MODE=plugin). Used by .github/workflows/plugin-test.yml.
#
#   MODE=ext|plugin CSSDM_SM_LINE=sm11|sm12|sm13 SM_CSS34_ROOT=<sourcemod-css34 checkout> \
#   CSSDM_PACKAGE=<released cssdm-*-css34-*linux.tar.gz> plugin/test/run.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${MODE:?MODE=ext|plugin}"
CSSDM_SM_LINE="${CSSDM_SM_LINE:-sm13}"
SM_CSS34_ROOT="${SM_CSS34_ROOT:?}"
CSSDM_PACKAGE="${CSSDM_PACKAGE:?}"
SERVER_DIR="${SERVER_DIR:-${ROOT}/.ci-server}"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
OUT_DIR="${OUT_DIR:-${ROOT}/.ci-out}"
H="${SM_CSS34_ROOT}/testing/scripts"
export SERVER_DIR CACHE_DIR
mkdir -p "${OUT_DIR}"

# Server tree, as testing/scripts/cssdm-bot-test.sh builds it.
"${H}/fetch-server.sh"
"${H}/apply-valve-rc-fix.sh"
"${H}/apply-srcds-patch.sh" || true
KEEP_MAPS=de_dust2 "${H}/trim-server-maps.sh"

# Metamod + SourceMod of the line, then the released CSS:DM package.
eval "$(python3 "${ROOT}/builder/run/css34_line.py" "${CSSDM_SM_LINE}" "${CACHE_DIR}/line" sourcemod mmsource)"
MM_PACKAGE="${CSS34_MMSOURCE}" SM_PACKAGE="${CSS34_SOURCEMOD}" BOTPLAY_PROFILE=release "${H}/install-addons.sh"
CSSDM_PACKAGE="${CSSDM_PACKAGE}" "${ROOT}/testing/scripts/install-cssdm.sh"

SM="${SERVER_DIR}/cstrike/addons/sourcemod"
SPCOMP="${SM}/scripting/spcomp"
INC="${ROOT}/cssdm/scripting/include"

if [[ "${MODE}" == "plugin" ]]; then
  # Replace the extension with the plugin; the DM plugins are rebuilt against the
  # plugin's cssdm.inc (SharedPlugin instead of Extension).
  # The package ships cssdm.ext.1.ep1.so / cssdm.ext.2.ep1.so (one per Metamod API).
  rm -f "${SM}"/extensions/cssdm.ext*.so "${SM}/extensions/cssdm.autoload"
  if ls "${SM}"/extensions/cssdm* >/dev/null 2>&1; then
    echo "cssdm extension files still present:"; ls "${SM}"/extensions/cssdm*; exit 1
  fi
  git -C "${ROOT}/cssdm" checkout -q -- .
  git -C "${ROOT}/cssdm" apply --ignore-space-change --ignore-whitespace "${ROOT}/builder/patches/2.1/2.patch"
  INC="${ROOT}/plugin/scripting/include"
  "${SPCOMP}" -i"${SM}/scripting/include" -i"${INC}" "${ROOT}/plugin/scripting/cssdm.sp" -o"${SM}/plugins/cssdm.smx"
  for f in "${ROOT}"/cssdm/scripting/dm_*.sp; do
    "${SPCOMP}" -i"${SM}/scripting/include" -i"${INC}" "${f}" -o"${SM}/plugins/cssdm/$(basename "${f}" .sp).smx"
  done
  cp -f "${ROOT}/builder/patches/2.1/gamedata/cssdm.games.txt" "${SM}/gamedata/"
  git -C "${ROOT}/cssdm" checkout -q -- .

  python3 "${ROOT}/plugin/test/inspect-server.py" "${SERVER_DIR}/cstrike/bin/server_i486.so" \
    "${H}/check-css34-vtables.py" | tee "${OUT_DIR}/inspect-server.txt" || echo "inspect-server: FAIL"
fi

"${SPCOMP}" -i"${SM}/scripting/include" -i"${INC}" "${ROOT}/plugin/test/cssdm_selftest.sp" -o"${SM}/plugins/cssdm_selftest.smx"
cp -f "${ROOT}/plugin/test/cssdm_selftest.games.txt" "${SM}/gamedata/"

cd "${SERVER_DIR}"
export LD_LIBRARY_PATH=".:bin:${LD_LIBRARY_PATH:-}"
BIN=./srcds_i686
[[ -x "${BIN}" ]] || BIN=./srcds_i486
rm -f "${SM}"/logs/*.log
echo "Starting srcds (${MODE}, ${CSSDM_SM_LINE})"
set +e
"${ROOT}/plugin/test/run-srcds.exp" "${BIN}" de_dust2 >"${OUT_DIR}/srcds.log" 2>&1
rc=$?
set -e
echo "srcds exit ${rc}"

cp -f "${SM}"/logs/*.log "${OUT_DIR}/" 2>/dev/null || true
echo "----- sourcemod errors -----"
cat "${SM}"/logs/errors_*.log 2>/dev/null || echo "(none)"
echo "----- selftest -----"
if [[ ! -f "${SM}/logs/cssdm_selftest.log" ]]; then
  echo "no selftest log"; tail -n 80 "${OUT_DIR}/srcds.log"; exit 1
fi
sed 's/^L [^:]*:[^:]*:[^:]*: //' "${SM}/logs/cssdm_selftest.log" | tee "${OUT_DIR}/selftest.txt"
grep -q "^SUMMARY fails=0" "${OUT_DIR}/selftest.txt" || { tail -n 60 "${OUT_DIR}/srcds.log"; exit 1; }
