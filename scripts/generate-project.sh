#!/usr/bin/env bash
# 根据是否已集成 FFmpeg XCFramework 选择对应 XcodeGen spec：
#   vendor/libavformat.xcframework 存在 -> project.yml（正式，含 FFmpeg 链接与嵌入）
#   否则                              -> project.nofmpeg.yml（本地开发，Stub）
set -euo pipefail

if [[ -d "vendor/libavformat.xcframework" && -d "vendor/libavcodec.xcframework" ]]; then
  echo "检测到 FFmpeg XCFrameworks，使用正式 spec（含 FFmpeg 链接与嵌入）"
  xcodegen generate --spec project.yml
else
  echo "未检测到 FFmpeg XCFramework，使用本地开发 spec（StubFFmpegProcessor）"
  xcodegen generate --spec project.nofmpeg.yml
fi
