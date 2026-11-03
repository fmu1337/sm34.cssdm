#!/usr/bin/env bash
# One cell of the CSS:DM compatibility table: install a Metamod + SourceMod build and a
# CSS:DM package into a fetched CS:S v34 tree (SERVER_DIR), boot it with
# compat-run.py, let bots play, and append one JSON result line to RESULTS.
#
#   SERVER_DIR      CS:S v34 tree (testing/scripts/fetch-server.sh of fmu1337/sourcemod-css34)
#   SM_ID, SM_LABEL build id/label from testing/compat/sm-builds.json
#   SM_PACKAGE      SourceMod archive (.tar.gz or .zip; may also contain Metamod)
#   MM_PACKAGE      Metamod archive (optional when SM_PACKAGE ships Metamod)
#   CSSDM_ID        CSS:DM variant id (sm11, sm12, sm13, myarena-ext, ...)
#   CSSDM_PACKAGE   cssdm-*-css34-*linux.tar.gz (plugins, gamedata, cfg, extension)
#   CSSDM_EXT       optional cssdm.ext.2.ep1.so that replaces the package's extensions
#   RESULTS         JSON lines file; OUT_DIR keeps the console log per cell
#   BOT_SECS        bot play length (default 90)
#   SRCDS_PREFIX    command prefix for srcds, e.g. FEX on ARM (passed to compat-run.py)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
: "${SERVER_DIR:?}" "${SM_ID:?}" "${SM_PACKAGE:?}" "${CSSDM_ID:?}" "${CSSDM_PACKAGE:?}" "${RESULTS:?}"
SM_LABEL="${SM_LABEL:-${SM_ID}}"
MM_PACKAGE="${MM_PACKAGE:-}"
CSSDM_EXT="${CSSDM_EXT:-}"
OUT_DIR="${OUT_DIR:-$(dirname "${RESULTS}")}"
export BOT_SECS="${BOT_SECS:-90}"

cell="${SM_ID}__${CSSDM_ID}"
mkdir -p "${OUT_DIR}"
console_log="${OUT_DIR}/${cell}.console.log"
maps_file="${OUT_DIR}/${cell}.maps.txt"
cs="${SERVER_DIR}/cstrike"

extract() {
  case "$1" in
    *.zip) python3 -m zipfile -e "$1" "${cs}" ;;
    *) tar -xzf "$1" -C "${cs}" ;;
  esac
}

echo "== ${SM_LABEL} x cssdm ${CSSDM_ID}"
rm -rf "${cs}/addons" "${cs}/cfg/cssdm" "${cs}/logs" "${cs}/console.log"
[[ -n "${MM_PACKAGE}" ]] && extract "${MM_PACKAGE}"
extract "${SM_PACKAGE}"
if [[ ! -f "${cs}/addons/metamod/sourcemod.vdf" ]]; then
  mkdir -p "${cs}/addons/metamod"
  printf '"Metamod Plugin"\n{\n\t"alias"\t\t"sourcemod"\n\t"file"\t\t"addons/sourcemod/bin/sourcemod_mm"\n}\n' \
    >"${cs}/addons/metamod/sourcemod.vdf"
fi
sed -i 's/"AutoUpdate"[[:space:]]*"yes"/"AutoUpdate"\t\t"no"/' \
  "${cs}/addons/sourcemod/configs/core.cfg" 2>/dev/null || true

# CSS:DM from the package; an SM package's own cssdm.ext (MyArena 1.9) is replaced too.
rm -f "${cs}"/addons/sourcemod/extensions/cssdm.ext.*.so
tar -xzf "${CSSDM_PACKAGE}" -C "${cs}"
if [[ -n "${CSSDM_EXT}" ]]; then
  rm -f "${cs}"/addons/sourcemod/extensions/cssdm.ext.*.so
  cp -f "${CSSDM_EXT}" "${cs}/addons/sourcemod/extensions/cssdm.ext.2.ep1.so"
fi
touch "${cs}/addons/sourcemod/extensions/cssdm.autoload"
sed -i 's/^cssdm_enabled[[:space:]]*".*"/cssdm_enabled "1"/' "${cs}/cfg/cssdm/cssdm.cfg" 2>/dev/null || true

set +e
SERVER_DIR="${SERVER_DIR}" COMPAT_LOG="${console_log}" MAPS_FILE="${maps_file}" \
  timeout $((BOT_SECS + 400)) python3 "${ROOT}/testing/scripts/compat-run.py" >"${OUT_DIR}/${cell}.runner.txt" 2>&1
rc=$?
set -e
cat "${OUT_DIR}/${cell}.runner.txt"

python3 "${ROOT}/testing/scripts/compat-table.py" parse \
  --sm-id "${SM_ID}" --sm-label "${SM_LABEL}" --cssdm-id "${CSSDM_ID}" \
  --console "${console_log}" --maps "${maps_file}" --runner-out "${OUT_DIR}/${cell}.runner.txt" \
  --rc "${rc}" --logs-dir "${cs}/logs" >>"${RESULTS}"
tail -n1 "${RESULTS}"
