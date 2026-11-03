#!/usr/bin/env bash
# Run CSS:DM compatibility cells outside GitHub Actions, e.g. on the ARM host under FEX
# (SRCDS_PREFIX=FEX plus the FEX_* variables). Covers the "local" builds of
# testing/compat/sm-builds.json and the MyArena cssdm extensions, which are not published.
#
#   SERVER_DIR  CS:S v34 tree; its cstrike/addons is replaced for every cell
#   PKG_DIR     sm11/sm12/sm13.tar.gz (CSS:DM packages from a Build run), the "local" archives
#               named in sm-builds.json, optional myarena19-cssdm.ext.2.ep1.so,
#               myarena111-cssdm.ext.2.ep1.so + myarena111-cssdm.games.txt;
#               downloaded MM/SM archives are cached here
#   BUILDS      build ids to run (default: all whose archives are available)
#   CSSDM       variants to run (default: sm11 sm12 sm13 and the MyArena ones present)
#   RESULTS     JSON lines file (default: $PKG_DIR/../out/local.jsonl)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
: "${SERVER_DIR:?}" "${PKG_DIR:?}"
RESULTS="${RESULTS:-$(dirname "${PKG_DIR}")/out/local.jsonl}"
mkdir -p "$(dirname "${RESULTS}")"

if [[ -z "${CSSDM:-}" ]]; then
  CSSDM="sm11 sm12 sm13"
  [[ -f "${PKG_DIR}/myarena19-cssdm.ext.2.ep1.so" ]] && CSSDM+=" myarena19"
  [[ -f "${PKG_DIR}/myarena111-cssdm.ext.2.ep1.so" ]] && CSSDM+=" myarena111"
fi

# id <TAB> label <TAB> local file <TAB> mm url <TAB> mm sha <TAB> sm url <TAB> sm sha
mapfile -t rows < <(python3 - "${ROOT}/testing/compat/sm-builds.json" <<'EOF'
import json, sys
for b in json.load(open(sys.argv[1]))['builds']:
    mm, sm = b.get('mm', {}), b.get('sm', {})
    print('\t'.join([b['id'], b['label'], b.get('local', ''), mm.get('url', ''), mm.get('sha256', ''),
                     sm.get('url', ''), sm.get('sha256', '')]))
EOF
)

fetch() {  # url sha -> cached path
  local out="${PKG_DIR}/dl-$(basename "$1")"
  [[ -s "${out}" ]] || curl -fsSL --retry 5 --retry-delay 3 -o "${out}" "$1"
  echo "$2  ${out}" | sha256sum -c - >/dev/null
  echo "${out}"
}

for row in "${rows[@]}"; do
  IFS=$'\t' read -r id label local_file mm_url mm_sha sm_url sm_sha <<<"${row}"
  if [[ -n "${BUILDS:-}" && " ${BUILDS} " != *" ${id} "* ]]; then
    continue
  fi
  if [[ -n "${local_file}" ]]; then
    [[ -f "${PKG_DIR}/${local_file}" ]] || { echo "skip ${id}: ${local_file} not in PKG_DIR"; continue; }
    sm_pkg="${PKG_DIR}/${local_file}" mm_pkg=""
  else
    mm_pkg="$(fetch "${mm_url}" "${mm_sha}")"
    sm_pkg="$(fetch "${sm_url}" "${sm_sha}")"
  fi
  for v in ${CSSDM}; do
    ext="" gamedata="" pkg="${PKG_DIR}/${v}.tar.gz"
    case "${v}" in
      myarena19) pkg="${PKG_DIR}/sm11.tar.gz" ext="${PKG_DIR}/myarena19-cssdm.ext.2.ep1.so" ;;
      myarena111)
        pkg="${PKG_DIR}/sm11.tar.gz" ext="${PKG_DIR}/myarena111-cssdm.ext.2.ep1.so"
        gamedata="${PKG_DIR}/myarena111-cssdm.games.txt" ;;
    esac
    SM_ID="${id}" SM_LABEL="${label}" SM_PACKAGE="${sm_pkg}" MM_PACKAGE="${mm_pkg}" \
      CSSDM_ID="${v}" CSSDM_PACKAGE="${pkg}" CSSDM_EXT="${ext}" CSSDM_GAMEDATA="${gamedata}" \
      RESULTS="${RESULTS}" bash "${ROOT}/testing/scripts/compat-smoke.sh" || echo "cell ${id}/${v} failed to run"
  done
done
python3 "${ROOT}/testing/scripts/compat-table.py" table --builds "${ROOT}/testing/compat/sm-builds.json" "${RESULTS}"
