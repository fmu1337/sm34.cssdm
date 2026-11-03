#!/usr/bin/env bash
# Fetch hl2sdk-episode1, Metamod:Source, SourceMod sources and a SourceMod package
# (for spcomp) into DEPS_DIR for the CSSDM_SM_LINE build.
#   sm11: SM/MM 1.10-dev sources, rom4s SM 1.11.0.6572 package (1.ep1 + 2.ep1).
#   sm13: fmu1337/sourcemod-css34 sm13-latest pins (builder/lines.json SM_LATEST_13 / MM_112)
#         and the matching release package (2.ep1 only).
set -euo pipefail

DEPS_DIR="${DEPS_DIR:-${HOME}}"
CSSDM_SM_LINE="${CSSDM_SM_LINE:-sm11}"
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
  sm13)
    fetch_commit https://github.com/alliedmodders/metamod-source "${DEPS_DIR}/mmsource" "${SM13_MM_COMMIT}"
    fetch_commit https://github.com/alliedmodders/sourcemod "${DEPS_DIR}/sourcemod" "${SM13_SM_COMMIT}"
    git -C "${DEPS_DIR}/sourcemod" submodule update --init --recursive --depth 1
    rel="https://github.com/fmu1337/sourcemod-css34/releases/download/${SM13_RELEASE_TAG}"
    curl -fL --retry 5 -o "${TMP}/${SM13_SM_PACKAGE}" "${rel}/${SM13_SM_PACKAGE}"
    curl -fL --retry 5 -o "${TMP}/SHA256SUMS.linux" "${rel}/SHA256SUMS.linux"
    (cd "${TMP}" && grep -F "  ${SM13_SM_PACKAGE}" SHA256SUMS.linux | sha256sum -c -)
    mv "${TMP}/${SM13_SM_PACKAGE}" "${TMP}/sm-bin.tgz"
    ;;
  *)
    echo "Unknown CSSDM_SM_LINE=${CSSDM_SM_LINE} (use sm11 or sm13)" >&2
    exit 1
    ;;
esac

mkdir -p "${DEPS_DIR}/sourcemod-bin"
tar -xzf "${TMP}/sm-bin.tgz" -C "${DEPS_DIR}/sourcemod-bin"
git -C "${DEPS_DIR}/mmsource" log -1 --format='mmsource %H %s'
git -C "${DEPS_DIR}/sourcemod" log -1 --format='sourcemod %H %s'
