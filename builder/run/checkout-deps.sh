#!/usr/bin/env bash
# Fetch hl2sdk-episode1, Metamod:Source, SourceMod sources and a SourceMod package
# (for spcomp) into DEPS_DIR for the CSSDM_SM_LINE build.
#   sm11: SM/MM 1.10-dev sources, rom4s SM 1.11.0.6572 package (1.ep1 + 2.ep1).
#   sm12: fmu1337/sourcemod-css34 sm12-latest pins (builder/lines.json SM_LATEST / MM_112)
#         and the matching release package (2.ep1 only).
#   sm13: fmu1337/sourcemod-css34 sm13-latest pins (builder/lines.json SM_LATEST_13 / MM_112)
#         and the matching release package (2.ep1 only).
set -euo pipefail

DEPS_DIR="${DEPS_DIR:-${HOME}}"
CSSDM_SM_LINE="${CSSDM_SM_LINE:-sm11}"
SM12_SM_COMMIT="${SM12_SM_COMMIT:-e68dada2979eb3093d81d2e3766f741e7d431e4a}"
SM12_MM_COMMIT="${SM12_MM_COMMIT:-cb47755826fad1483291e5dc00222aa64303d12f}"
SM12_RELEASE_TAG="${SM12_RELEASE_TAG:-1.12.0.7257-mm1.12.0-r2}"
SM12_SM_PACKAGE="${SM12_SM_PACKAGE:-sourcemod-1.12.0-git7257-css34-linux.tar.gz}"
SM13_SM_COMMIT="${SM13_SM_COMMIT:-b34de51b8c7f92fc2a7242fc0195e2d64a69cefd}"
SM13_MM_COMMIT="${SM13_MM_COMMIT:-cb47755826fad1483291e5dc00222aa64303d12f}"
SM13_RELEASE_TAG="${SM13_RELEASE_TAG:-1.13.0.7478-mm1.12.0-r3}"
SM13_SM_PACKAGE="${SM13_SM_PACKAGE:-sourcemod-1.13.0-git7478-css34-linux.tar.gz}"

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
    curl -fL --retry 5 -o "${TMP}/sm-bin.tgz" \
      https://github.com/rom4s/sourcemod-css34/releases/download/v1.11.0.6572/sourcemod-1.11.0-git6572-css34-linux.tar.gz
    ;;
  sm12|sm13)
    pfx="${CSSDM_SM_LINE^^}"
    sm_commit_var="${pfx}_SM_COMMIT" mm_commit_var="${pfx}_MM_COMMIT"
    tag_var="${pfx}_RELEASE_TAG" pkg_var="${pfx}_SM_PACKAGE"
    sm_pkg="${!pkg_var}"
    fetch_commit https://github.com/alliedmodders/metamod-source "${DEPS_DIR}/mmsource" "${!mm_commit_var}"
    fetch_commit https://github.com/alliedmodders/sourcemod "${DEPS_DIR}/sourcemod" "${!sm_commit_var}"
    git -C "${DEPS_DIR}/sourcemod" submodule update --init --recursive --depth 1
    rel="https://github.com/fmu1337/sourcemod-css34/releases/download/${!tag_var}"
    curl -fL --retry 5 -o "${TMP}/${sm_pkg}" "${rel}/${sm_pkg}"
    curl -fL --retry 5 -o "${TMP}/SHA256SUMS.linux" "${rel}/SHA256SUMS.linux"
    (cd "${TMP}" && grep -F "  ${sm_pkg}" SHA256SUMS.linux | sha256sum -c -)
    mv "${TMP}/${sm_pkg}" "${TMP}/sm-bin.tgz"
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
