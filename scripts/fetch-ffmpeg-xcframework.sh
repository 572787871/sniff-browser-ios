#!/usr/bin/env bash
# 正式构建：获取并校验 FFmpeg XCFramework，失败则构建失败（不允许回退到 Stub）。
#
# 依赖 GitHub Actions 变量：
#   FFMPEG_XCFRAMEWORK_URL    预编译 FFmpeg XCFramework 的 zip 下载地址
#   FFMPEG_XCFRAMEWORK_SHA256 该产物的 SHA-256（固定版本、可复现）
#
# 产物要求：解压后为 vendor/FFmpeg.xcframework（内含 FFmpeg.framework，
# 覆盖 ios-arm64 与 ios-arm64_x86_64-simulator 切片，静态库即可）。
set -euo pipefail

TARGET_DIR="vendor"
TARGET="${TARGET_DIR}/FFmpeg.xcframework"
URL="${FFMPEG_XCFRAMEWORK_URL:-}"
SHA256_EXPECTED="${FFMPEG_XCFRAMEWORK_SHA256:-}"

if [[ -d "${TARGET}" ]]; then
  echo "FFmpeg XCFramework 已存在：${TARGET}"
  exit 0
fi

if [[ -z "${URL}" ]]; then
  echo "::error::缺少 FFMPEG_XCFRAMEWORK_URL（请在仓库 Variables 配置预编译 FFmpeg XCFramework 地址）"
  exit 1
fi
if [[ -z "${SHA256_EXPECTED}" ]]; then
  echo "::error::缺少 FFMPEG_XCFRAMEWORK_SHA256（固定产物版本校验）"
  exit 1
fi

mkdir -p "${TARGET_DIR}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "下载 FFmpeg XCFramework：${URL}"
curl -fsSL --max-time 900 -o "${TMP_DIR}/ffmpeg.xcframework.zip" "${URL}"

echo "${SHA256_EXPECTED}  ${TMP_DIR}/ffmpeg.xcframework.zip" | shasum -a 256 -c - || {
  echo "::error::FFmpeg XCFramework SHA-256 校验失败，请核对版本与 FFMPEG_XCFRAMEWORK_SHA256"
  exit 1
}

unzip -q "${TMP_DIR}/ffmpeg.xcframework.zip" -d "${TARGET_DIR}"

if [[ ! -d "${TARGET}" ]]; then
  echo "::error::解压后未找到 vendor/FFmpeg.xcframework（请检查 zip 结构）"
  exit 1
fi

echo "FFmpeg XCFramework 就绪：${TARGET}"
