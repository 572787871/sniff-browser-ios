#!/usr/bin/env bash
# 下载静态 iOS arm64 ffmpeg 可执行文件并放入资源目录，随 IPA 捆绑。
#
# 生产构建（GitHub Actions）应把下面的候选源替换为固定的、可验证的
# iOS arm64 ffmpeg 产物地址，并去掉失败时“降级”的分支，保证必带 FFmpeg。
# 当前开发环境没有该产物时，构建仍可进行，运行时会使用 StubFFmpegProcessor。
set -euo pipefail

TARGET_DIR="SniffBrowser/Resources"
TARGET="${TARGET_DIR}/ffmpeg"

if [[ -f "${TARGET}" ]]; then
  echo "ffmpeg 已存在：${TARGET}"
  chmod +x "${TARGET}"
  exit 0
fi

mkdir -p "${TARGET_DIR}"

# 候选源（按顺序尝试）。生产环境请替换为固定版本地址。
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
