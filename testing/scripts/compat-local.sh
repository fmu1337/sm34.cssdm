#!/usr/bin/env bash
# Run CSS:DM compatibility cells outside GitHub Actions, e.g. on the ARM host under FEX
# (SRCDS_PREFIX=FEX plus the FEX_* variables). Covers the "local" builds of
# testing/compat/sm-builds.json (incl. "local" archives, which are not downloadable).
#
#   SERVER_DIR  CS:S v34 tree; its cstrike/addons is replaced for every cell
#   PKG_DIR     sm11/sm12/sm13.tar.gz (CSS:DM packages from a Build run), the "local" archives
#               named in sm-builds.json;
#               downloaded MM/SM archives are cached here
#   BUILDS      build ids to run (default: all whose archives are available)
#   CSSDM       variants to run (default: none and the sm11/sm12/sm13 packages present)
#   RESULTS     JSON lines file (default: $PKG_DIR/../out/local.jsonl)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
: "${SERVER_DIR:?}" "${PKG_DIR:?}"
RESULTS="${RESULTS:-$(dirname "${PKG_DIR}")/out/local.jsonl}"
mkdir -p "$(dirname "${RESULTS}")"

if [[ -z "${CSSDM:-}" ]]; then
  CSSDM="none"
  for v in sm11 sm12 sm13; do [[ -f "${PKG_DIR}/${v}.tar.gz" ]] && CSSDM+=" ${v}"; done
fi

# id, label, local file, mm url, mm sha, sm url, sm sha; split on \x1f, which (unlike a tab)
# keeps empty fields
mapfile -t rows < <(python3 "${ROOT}/testing/scripts/compat-builds.py" "${ROOT}/testing/compat/sm-builds.json" |
  python3 -c '
import json, sys
for b in json.load(sys.stdin):
    print("\x1f".join([b["id"], b["label"], b["local"], b.get("mm_url", ""), b.get("mm_sha", ""),
                         b.get("sm_url", ""), b.get("sm_sha", "")]))')

fetch() {  # url sha cache-name -> cached path
  local out="${PKG_DIR}/dl-$3"
  [[ -s "${out}" ]] || curl -fsSL --retry 5 --retry-delay 3 -o "${out}" "$1"
  echo "$2  ${out}" | sha256sum -c - >/dev/null
  echo "${out}"
}

for row in "${rows[@]}"; do
  IFS=$'\x1f' read -r id label local_file mm_url mm_sha sm_url sm_sha <<<"${row}"
  if [[ -n "${BUILDS:-}" && " ${BUILDS} " != *" ${id} "* ]]; then
    continue
  fi
  if [[ -n "${local_file}" ]]; then
    [[ -f "${PKG_DIR}/${local_file}" ]] || { echo "skip ${id}: ${local_file} not in PKG_DIR"; continue; }
    sm_pkg="${PKG_DIR}/${local_file}" mm_pkg=""
  else
    # Pointer releases share file names across lines, so the cache key includes the build id.
    mm_pkg="$(fetch "${mm_url}" "${mm_sha}" "${id}-mm-$(basename "${mm_url}")")"
    sm_pkg="$(fetch "${sm_url}" "${sm_sha}" "${id}-sm-$(basename "${sm_url}")")"
  fi
  for v in ${CSSDM}; do
    ext="" gamedata="" pkg="${PKG_DIR}/${v}.tar.gz"
    SM_ID="${id}" SM_LABEL="${label}" SM_PACKAGE="${sm_pkg}" MM_PACKAGE="${mm_pkg}" \
      CSSDM_ID="${v}" CSSDM_PACKAGE="${pkg}" CSSDM_EXT="${ext}" CSSDM_GAMEDATA="${gamedata}" \
      RESULTS="${RESULTS}" bash "${ROOT}/testing/scripts/compat-smoke.sh" || echo "cell ${id}/${v} failed to run"
  done
done
python3 "${ROOT}/testing/scripts/compat-table.py" table --builds "${ROOT}/testing/compat/sm-builds.json" "${RESULTS}"
