#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-${RELEASE_VERSION:-$(date +%Y%m%d%H%M%S)}}"
TARGET_OS="${TARGET_OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"
PACKAGE_NAME="gatewayvpn-${VERSION}-${TARGET_OS}-${TARGET_ARCH}"
DIST_DIR="${ROOT_DIR}/dist"
WORK_DIR="$(mktemp -d)"
APP_BIN="${ROOT_DIR}/bin/gatewayvpn-manager"
APP_BUILD_STAMP="${ROOT_DIR}/bin/gatewayvpn-manager.build-id"

compute_expected_build_id() {
    (
        cd "${ROOT_DIR}"
        shasum app_runtime.py vpngate_manager.py vpn_utils.py proxy_server.py scripts/build-binary.sh
    ) | shasum | awk '{print $1}'
}

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

mkdir -p "${DIST_DIR}"

EXPECTED_BUILD_ID="$(compute_expected_build_id)"
CURRENT_BUILD_ID=""
if [ -f "${APP_BUILD_STAMP}" ]; then
    CURRENT_BUILD_ID="$(tr -d '[:space:]' < "${APP_BUILD_STAMP}")"
fi
if [ ! -x "${APP_BIN}" ] || [ "${CURRENT_BUILD_ID}" != "${EXPECTED_BUILD_ID}" ]; then
    bash "${ROOT_DIR}/scripts/build-binary.sh"
fi

if command -v rsync >/dev/null 2>&1; then
    rsync -a \
        --exclude ".git" \
        --exclude ".local_dev" \
        --exclude ".DS_Store" \
        --exclude ".playwright-mcp" \
        --exclude "build" \
        --exclude "dist" \
        --exclude "vpngate_data" \
        --exclude "__pycache__" \
        --exclude "*.pyc" \
        "${ROOT_DIR}/" "${WORK_DIR}/${PACKAGE_NAME}/"
else
    mkdir -p "${WORK_DIR}/${PACKAGE_NAME}"
    (cd "${ROOT_DIR}" && tar \
        --exclude ".git" \
        --exclude ".local_dev" \
        --exclude ".DS_Store" \
        --exclude ".playwright-mcp" \
        --exclude "build" \
        --exclude "dist" \
        --exclude "vpngate_data" \
        --exclude "__pycache__" \
        --exclude "*.pyc" \
        -cf - .) | (cd "${WORK_DIR}/${PACKAGE_NAME}" && tar -xf -)
fi

tar -czf "${DIST_DIR}/${PACKAGE_NAME}.tar.gz" -C "${WORK_DIR}" "${PACKAGE_NAME}"

echo "已生成部署包: ${DIST_DIR}/${PACKAGE_NAME}.tar.gz"
