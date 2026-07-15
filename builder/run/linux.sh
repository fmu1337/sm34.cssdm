#!/usr/bin/env bash
set -euo pipefail

SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SELF_PATH}/../.." && pwd)"
echo "BUILDER_PATH = ${SELF_PATH}"
echo "REPO_ROOT = ${REPO_ROOT}"

DEPS_DIR="${DEPS_DIR:-${HOME}}"
MMS_PATH="${MMS_PATH:-${DEPS_DIR}/mmsource}"
SM_PATH="${SM_PATH:-${DEPS_DIR}/sourcemod}"
SM_BIN_PATH="${SM_BIN_PATH:-${DEPS_DIR}/sourcemod-bin}"
HL2SDK_EP1="${HL2SDK_EP1:-${DEPS_DIR}/hl2sdk-episode1}"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/OUT}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

# Prefer venv python if provided (CI / local tools).
if [[ -n "${VIRTUAL_ENV:-}" && -x "${VIRTUAL_ENV}/bin/python" ]]; then
  PYTHON_BIN="${VIRTUAL_ENV}/bin/python"
fi

for req in "${MMS_PATH}" "${SM_PATH}" "${SM_BIN_PATH}" "${HL2SDK_EP1}"; do
  if [[ ! -d "${req}" ]]; then
    echo "Missing dependency path: ${req}" >&2
    exit 1
  fi
done

cd "${REPO_ROOT}/cssdm"
"${PYTHON_BIN}" "${SELF_PATH}/build.py" \
  --mms-path "${MMS_PATH}" \
  --sm-path "${SM_PATH}" \
  --sm-bin-path "${SM_BIN_PATH}" \
  --hl2sdk-ep1 "${HL2SDK_EP1}" \
  -o "${OUT_DIR}" \
  ${CC:+-cc "${CC}"} \
  ${CXX:+-cxx "${CXX}"}
