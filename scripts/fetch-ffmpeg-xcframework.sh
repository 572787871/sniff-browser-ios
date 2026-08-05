#!/usr/bin/env bash
# 正式构建：获取固定版本 FFmpeg libav XCFrameworks 并做 SHA-256 校验。
#
# 产物来源：tylerjonesio/ffmpeg-libav-spm @ min.v7.1.3.0
#   （官方 FFmpeg 7.1.3 编译的纯 libav 库，不含 FFmpegKit / mobile-ffmpeg wrapper）
# 校验和与该仓库该 tag 的 Package.swift 完全一致，构建失败立即中止，
# 不允许生成“无 FFmpeg”的正式 IPA。
#
# 产物布局：
#   vendor/libavcodec.xcframework   vendor/libavformat.xcframework
#   vendor/libavutil.xcframework   vendor/libswresample.xcframework
#   vendor/libswscale.xcframework  vendor/libavfilter.xcframework
#   vendor/FFmpegHeaders/          （按 libavformat/、libavcodec/ 等子目录装配的头文件）
#   vendor/FFmpeg.version          （版本与校验和清单）
set -euo pipefail

RELEASE_TAG="min.v7.1.3.0"
BASE_URL="https://github.com/tylerjonesio/ffmpeg-libav-spm/releases/download/${RELEASE_TAG}"
TARGET_DIR="vendor"
HEADERS_DIR="${TARGET_DIR}/FFmpegHeaders"
VERSION_FILE="${TARGET_DIR}/FFmpeg.version"

LIBS=(libavcodec libavformat libavutil libswresample libswscale libavfilter)

# 与仓库 Package.swift @ ${RELEASE_TAG} 一致的 SHA-256（固定版本、可复现）。
# 注意：macOS 自带 bash 3.2 不支持关联数组，这里用 case 保证可移植。
sha256_for() {
  case "$1" in
    libavcodec)     echo "03426fcda41ec61b925afbb6cf0c5e8796c569443ef53f32bbb74191f0b4386c" ;;
    libavformat)    echo "e5e4e7ef94a275529c0852f2865e0dc6f3965c1ee991e281ecaa525529ab8e2c" ;;
    libavutil)      echo "b87310b863224f7bf7095c1aae8835d173335bd945714776d9e9d6e2fa6eded7" ;;
    libswresample)  echo "46bbe79946676a0293ae8f60ef27980a2bee93abf1b8fa3b43466ddc985e5df4" ;;
    libswscale)     echo "1497cee3d8fd96fef8dc1480b20aacaa5717c875fb9c80ec698a34552372e5d1" ;;
    libavfilter)    echo "c4fa55e438cc1638357f48c07716e2712b0f78b7e83f7824ff3b07fc4d4ed9c7" ;;
    *)              echo "" ;;
  esac
}

log() { echo "[fetch-ffmpeg] $*"; }
fail() {
  echo "::error::$*"
  exit 1
}

all_present() {
  [[ -f "${VERSION_FILE}" ]] || return 1
  for lib in "${LIBS[@]}"; do
    [[ -d "${TARGET_DIR}/${lib}.xcframework" ]] || return 1
    [[ -d "${HEADERS_DIR}/${lib}" ]] || return 1
  done
  return 0
}

extract_zip() { # zip_file dest_dir
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$1" -d "$2"
  else
    python3 - "$1" "$2" <<'PY'
import sys
import zipfile

zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
  fi
}

if all_present; then
  log "FFmpeg XCFrameworks 已存在：${TARGET_DIR}（${RELEASE_TAG}）"
  exit 0
fi

log "获取固定版本 FFmpeg libav XCFrameworks：${RELEASE_TAG}"
mkdir -p "${TARGET_DIR}"

# 产物不完整或版本不符：仅清理 vendor 下的 FFmpeg 相关目录后重新获取。
for lib in "${LIBS[@]}"; do
  rm -rf "${TARGET_DIR}/${lib}.xcframework"
done
rm -rf "${HEADERS_DIR}"
rm -f "${VERSION_FILE}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

for lib in "${LIBS[@]}"; do
  archive="${TMP_DIR}/${lib}.xcframework.zip"
  log "下载 ${lib}..."
  curl -fsSL --max-time 900 -o "${archive}" "${BASE_URL}/${lib}.xcframework.zip"

  expected="$(sha256_for "${lib}")"
  if [[ -z "${expected}" ]]; then
    fail "未知库：${lib}"
  fi
  actual="$(shasum -a 256 "${archive}" | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    fail "${lib}.xcframework.zip SHA-256 校验失败：期望 ${expected}，实际 ${actual}"
  fi
  log "${lib} SHA-256 校验通过"

  extract_zip "${archive}" "${TARGET_DIR}"
  if [[ ! -d "${TARGET_DIR}/${lib}.xcframework" ]]; then
    fail "解压后未找到 ${TARGET_DIR}/${lib}.xcframework"
  fi
done

# 装配头文件：保留 libavformat/、libavcodec/ 等子目录结构（头文件内部使用
# "libavutil/xxx.h" 相对包含），供 Swift 桥接头使用。
mkdir -p "${HEADERS_DIR}"
for lib in "${LIBS[@]}"; do
  src_headers="${TARGET_DIR}/${lib}.xcframework/ios-arm64_arm64e/${lib}.framework/Headers"
  [[ -d "${src_headers}" ]] || fail "缺少头文件目录：${src_headers}"
  mkdir -p "${HEADERS_DIR}/${lib}"
  cp -R "${src_headers}/." "${HEADERS_DIR}/${lib}/"
done

cat > "${VERSION_FILE}" <<EOF
FFmpeg libav XCFrameworks
Release: ${RELEASE_TAG}
Source: ${BASE_URL}
Built: $(date -u +%Y-%m-%dT%H:%M:%SZ)
SHA-256:
$(for lib in "${LIBS[@]}"; do printf '  %s %s\n' "${lib}" "$(sha256_for "${lib}")"; done)
EOF

log "FFmpeg XCFrameworks 就绪：${TARGET_DIR}（${RELEASE_TAG}）"
