#!/usr/bin/env bash
# Fetch hl2sdk-episode1, Metamod:Source, SourceMod sources and a SourceMod package
# (for spcomp) into DEPS_DIR for the CSSDM_SM_LINE build.
#   sm11: SM/MM 1.10-dev sources (1.ep1 + 2.ep1); spcomp and includes from the fork's
#         line-sm11-oldstable package (SM 1.11.0.6970).
#   sm12, sm13: whatever fmu1337/sourcemod-css34 line-sm12-latest / line-sm13-latest point at:
#         its SourceMod / Metamod commits and its SourceMod package (2.ep1 only); see css34_line.py.
set -euo pipefail

DEPS_DIR="${DEPS_DIR:-${HOME}}"
CSSDM_SM_LINE="${CSSDM_SM_LINE:-sm11}"

fetch_commit() {
  local url="$1" dir="$2" commit="$3"
  git init -q "${dir}"
  git -C "${dir}" remote add origin "${url}"
  git -C "${dir}" fetch -q --depth 1 origin "${commit}"
  git -C "${dir}" checkout -q FETCH_HEAD
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

git clone --depth 1 -b episode1 https://github.com/alliedmodders/hl2sdk "${DEPS_DIR}/hl2sdk-episode1"

case "${CSSDM_SM_LINE}" in
  sm11)
    git clone --depth 1 -b 1.10-dev https://github.com/alliedmodders/metamod-source "${DEPS_DIR}/mmsource"
    git clone --depth 1 -b 1.10-dev --recursive https://github.com/alliedmodders/sourcemod "${DEPS_DIR}/sourcemod"
    eval "$(python3 "$(dirname "$0")/css34_line.py" sm11 "${TMP}/css34" sourcemod)"
    mv "${CSS34_SOURCEMOD}" "${TMP}/sm-bin.tgz"
    ;;
  sm12|sm13)
    eval "$(python3 "$(dirname "$0")/css34_line.py" "${CSSDM_SM_LINE}" "${TMP}/css34" sourcemod)"
    fetch_commit https://github.com/alliedmodders/metamod-source "${DEPS_DIR}/mmsource" "${CSS34_MM_COMMIT}"
    fetch_commit https://github.com/alliedmodders/sourcemod "${DEPS_DIR}/sourcemod" "${CSS34_SM_COMMIT}"
    git -C "${DEPS_DIR}/sourcemod" submodule update --init --recursive --depth 1
    cp "${TMP}/css34/lines.json" "${DEPS_DIR}/css34-lines.json"
    mv "${CSS34_SOURCEMOD}" "${TMP}/sm-bin.tgz"
    ;;
  *)
    echo "Unknown CSSDM_SM_LINE=${CSSDM_SM_LINE} (use sm11, sm12 or sm13)" >&2
    exit 1
    ;;
esac

mkdir -p "${DEPS_DIR}/sourcemod-bin"
tar -xzf "${TMP}/sm-bin.tgz" -C "${DEPS_DIR}/sourcemod-bin"
git -C "${DEPS_DIR}/mmsource" log -1 --format='mmsource %H %s'
git -C "${DEPS_DIR}/sourcemod" log -1 --format='sourcemod %H %s'
