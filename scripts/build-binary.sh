#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
BUILD_ROOT="${ROOT_DIR}/build/pyinstaller"
DIST_ROOT="${ROOT_DIR}/dist/pyinstaller"
TARGET_DIR="${ROOT_DIR}/bin"
TARGET_BIN="${TARGET_DIR}/gatewayvpn-manager"
BUILD_STAMP="${TARGET_DIR}/gatewayvpn-manager.build-id"
TARGET_OS="${TARGET_OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"

compute_build_id() {
    (
        cd "${ROOT_DIR}"
        shasum app_runtime.py vpngate_manager.py vpn_utils.py proxy_server.py scripts/build-binary.sh
    ) | shasum | awk '{print $1}'
}

pick_python() {
    for candidate in "${PYTHON_BIN}" python3.13 python3.12 python3.11 python3.10 python3; do
        if [ -z "${candidate}" ]; then
            continue
        fi
        if ! command -v "${candidate}" >/dev/null 2>&1; then
            continue
        fi
        if "${candidate}" -c "import pyexpat" >/dev/null 2>&1; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

if ! PYTHON_BIN="$(pick_python)"; then
    echo "错误: 未找到可用的 Python 解释器（当前环境中的 pyexpat 模块不可用）。" >&2
    exit 1
fi

mkdir -p "${BUILD_ROOT}" "${DIST_ROOT}" "${TARGET_DIR}"

"${PYTHON_BIN}" -m pip install --disable-pip-version-check --quiet pyinstaller

"${PYTHON_BIN}" -m PyInstaller \
    --noconfirm \
    --clean \
    --onefile \
    --name gatewayvpn-manager \
    --distpath "${DIST_ROOT}" \
    --workpath "${BUILD_ROOT}" \
    --specpath "${BUILD_ROOT}" \
    "${ROOT_DIR}/vpngate_manager.py"

cp "${DIST_ROOT}/gatewayvpn-manager" "${TARGET_BIN}"
chmod +x "${TARGET_BIN}"
compute_build_id > "${BUILD_STAMP}"

echo "已生成可执行应用: ${TARGET_BIN}"
echo "目标平台: ${TARGET_OS}/${TARGET_ARCH}"
