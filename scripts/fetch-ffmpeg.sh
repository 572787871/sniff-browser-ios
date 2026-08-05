#!/usr/bin/env bash
# 正式版 FFmpeg 集成（GitHub Actions）：
# 应下载/构建 iOS 版 FFmpeg XCFramework，链接进工程，并让
# FFmpegProcessorProvider 返回基于 XCFramework 的实现（无需改下载模块与管线）。
#
# 下面的可执行文件方式仅用于开发期验证；当前环境没有产物时构建仍可进行，
# 运行时会使用 StubFFmpegProcessor 保证项目可编译。
set -euo pipefail

TARGET_DIR="SniffBrowser/Resources"
TARGET="${TARGET_DIR}/ffmpeg"

if [[ -f "${TARGET}" ]]; then
  echo "ffmpeg 已存在：${TARGET}"
  chmod +x "${TARGET}"
  exit 0
fi

mkdir -p "${TARGET_DIR}"

# 候选源（按顺序尝试）。生产环境请替换为固定的 iOS arm64 ffmpeg 产物地址。
CANDIDATES=(
  "https://example.invalid/ffmpeg-ios-arm64"
)

for url in "${CANDIDATES[@]}"; do
  if curl -fsSL --max-time 300 -o "${TARGET}" "${url}"; then
    chmod +x "${TARGET}"
    echo "ffmpeg 已下载并捆绑：${url}"
    exit 0
  fi
  echo "尝试失败：${url}"
done

echo "::warning::未能下载 ffmpeg，本次构建将使用 StubFFmpegProcessor（生产版本必须捆绑 ffmpeg）"
exit 0
