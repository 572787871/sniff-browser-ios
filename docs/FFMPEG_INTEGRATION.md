# FFmpeg 正式集成方案（GitHub Actions 全自动）

目标：**GitHub 每次构建产出的 IPA 都自带 FFmpeg**，不需要手工集成，也不需要配置
任何 Secrets/Variables。本地开发没有 FFmpeg 时仍可编译（使用 Stub），但**正式 CI
构建必须包含真正的 FFmpeg，缺失或校验失败立即中止，不允许生成“无 FFmpeg”的 IPA**。

## 1. 总体架构（保持不变）

```
下载模块（MediaDownloadManager / DownloadCenter）
        │  不直接依赖 FFmpeg
        ▼
Media Pipeline（MediaPostProcessor 等，保持不变）
        │
        ▼
FFmpegProcessor（唯一媒体处理入口）
   ├── FFmpegProcessorProvider（选择实现）
   │     ├── 真实现：FFmpegLibraryProcessor（libav* API，正式构建）
   │     └── StubFFmpegProcessor（仅本地无 FFmpeg 时编译用）
        │
        ▼
最终视频文件 → 更新数据库 → 自动清理缓存
```

下载模块与 Media Pipeline 永远不感知 FFmpeg 的集成方式；将来切换实现只改
`FFmpegProcessorProvider.current` 一行，其余代码零改动。

### FFmpegProcessor 职责（完整 Media Engine）

FFmpegProcessor 统一负责（新增格式时只扩展它，不改下载模块）：

- HLS（m3u8）→ MP4（本地分片目录或远程清单）
- TS → MP4
- DASH（MPD）音视频流下载并合并 → MP4
- FLV 容器 → MP4
- MKV 容器 → MP4（编码兼容时无损封装）
- WebM 容器 → MP4（编码兼容时无损封装）
- Metadata 提取（时长、码率、分辨率、大小）
- Thumbnail 封面提取
- 预留：视频裁剪、转码等后续能力（libavfilter 已随包提供）

除未来明确要求转码的功能外，全部 `-c copy` 无损处理，禁止不必要的重新编码。

## 2. FFmpeg XCFramework 获取方式（已落地）

**不使用 FFmpegKit，不使用 mobile-ffmpeg。** 正式版采用官方 FFmpeg 编译的
iOS XCFramework（固定版本 + SHA-256 校验）。

当前来源：`tylerjonesio/ffmpeg-libav-spm` 的 Release `min.v7.1.3.0`
（FFmpeg 7.1.3 编译的**纯 libav 库**，仅含 libavcodec / libavformat / libavutil /
libswresample / libswscale / libavfilter，不含任何 FFmpegKit wrapper；产物为
动态 XCFramework，覆盖 `ios-arm64_arm64e`（真机）与 `ios-arm64_x86_64-simulator`
（模拟器）切片）。

`scripts/fetch-ffmpeg-xcframework.sh` 行为：

1. 固定 Release tag `min.v7.1.3.0`，下载 6 个 `libav*.xcframework.zip`；
2. 逐个用内置 SHA-256 校验（值与仓库该 tag 的 `Package.swift` 一致）；
3. 解压到 `vendor/`，并把各库 Headers 按 `libavformat/`、`libavcodec/` 等子目录
   装配到 `vendor/FFmpegHeaders/`（头文件内部使用 `"libavutil/xxx.h"` 相对包含，
   必须保留子目录结构）；
4. 写入 `vendor/FFmpeg.version` 清单（版本、来源、校验和）；
5. **任何一步失败 → `exit 1`，构建立即失败**，不允许回退到 Stub。

已内置的固定版本校验和：

| 库 | SHA-256 |
| --- | --- |
| libavcodec | `03426fcda41ec61b925afbb6cf0c5e8796c569443ef53f32bbb74191f0b4386c` |
| libavformat | `e5e4e7ef94a275529c0852f2865e0dc6f3965c1ee991e281ecaa525529ab8e2c` |
| libavutil | `b87310b863224f7bf7095c1aae8835d173335bd945714776d9e9d6e2fa6eded7` |
| libswresample | `46bbe79946676a0293ae8f60ef27980a2bee93abf1b8fa3b43466ddc985e5df4` |
| libswscale | `1497cee3d8fd96fef8dc1480b20aacaa5717c875fb9c80ec698a34552372e5d1` |
| libavfilter | `c4fa55e438cc1638357f48c07716e2712b0f78b7e83f7824ff3b07fc4d4ed9c7` |

升级 FFmpeg 版本时：更新 tag、替换校验和、确认头文件 API 兼容即可，其余链路不变。

## 3. Xcode 工程自动集成

采用 **XcodeGen** 双 spec 方案：

### 3.1 文件

| 文件 | 作用 |
| --- | --- |
| `project.base.yml` | 全部业务 target/scheme/settings + 桥接头 + 系统库（单一事实来源） |
| `project.yml` | `include: project.base.yml` + 6 个 libav XCFramework 依赖与嵌入（正式构建用） |
| `project.nofmpeg.yml` | `include: project.base.yml`，无 FFmpeg（本地无 FFmpeg 时用） |
| `scripts/generate-project.sh` | 检测 `vendor/libavformat.xcframework` 等存在与否，选择对应 spec 生成工程 |

### 3.2 Link Binary With Libraries / Embed Frameworks

`project.yml` 中 SniffBrowser target 的 dependencies（libav 为动态框架，
`embed: true` 加入 Embed Frameworks；另链接其依赖的系统框架）：

```yaml
    dependencies:
      - framework: AudioToolbox
      - framework: CoreMedia
      - framework: CoreVideo
      - framework: VideoToolbox
      - framework: vendor/libavcodec.xcframework
        embed: true
      - framework: vendor/libavformat.xcframework
        embed: true
      - framework: vendor/libavutil.xcframework
        embed: true
      - framework: vendor/libswresample.xcframework
        embed: true
      - framework: vendor/libswscale.xcframework
        embed: true
      - framework: vendor/libavfilter.xcframework
        embed: true
```

libav 动态库的 install name 为 `@rpath/libav*.framework/libav*`，App 默认的
`LD_RUNPATH_SEARCH_PATHS`（`@executable_path/Frameworks`）即可在运行时找到它们。

### 3.3 Build Settings

`project.base.yml`（有无 FFmpeg 都无害）：

```yaml
FRAMEWORK_SEARCH_PATHS: "$(inherited) $(SRCROOT)/vendor"
OTHER_LDFLAGS: "$(inherited) -lz -liconv -lbz2 -lc++"
SWIFT_OBJC_BRIDGING_HEADER: SniffBrowser/SupportingFiles/SniffBrowser-Bridging-Header.h
```

`project.yml`（正式版）追加：

```yaml
HEADER_SEARCH_PATHS: "$(inherited) $(SRCROOT)/vendor/FFmpegHeaders"
SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) FFMPEG_ENABLED"
```

### 3.4 Swift 桥接（libav C API）

`SniffBrowser/SupportingFiles/SniffBrowser-Bridging-Header.h` 用
`__has_include` 守卫导入 libav 头文件：正式构建装配了 `vendor/FFmpegHeaders` 时
自动启用，本地无 FFmpeg 时自动跳过，保证两种环境都编译通过。

### 3.5 实现切换

```swift
enum FFmpegProcessorProvider {
    static var current: FFmpegProcessor {
        #if FFMPEG_ENABLED
        return FFmpegLibraryProcessor()   // libav* API 实现（正式构建）
        #else
        return StubFFmpegProcessor()      // 本地无 FFmpeg 编译用
        #endif
    }
}
```

## 4. GitHub Actions 自动构建 IPA

`build-ios.yml` 关键步骤（已配置）：

```yaml
- name: Fetch FFmpeg XCFramework
  run: bash scripts/fetch-ffmpeg-xcframework.sh   # 下载 + SHA-256 校验，失败即红

- name: Generate Xcode project
  run: bash scripts/generate-project.sh

- name: Verify FFmpeg is embedded in the app      # Release 构建后硬验证
  run: |
    # 1) 6 个 libav*.framework 必须出现在 App 的 Frameworks/ 中
    # 2) 禁止 FFmpegKit.framework / mobile-ffmpeg wrapper
    # 3) 主二进制必须通过 @rpath 链接 libavcodec
    # 任一不满足 → exit 1，不打包
```

本地开发（无 FFmpeg）：

```bash
bash scripts/generate-project.sh   # 自动选择 project.nofmpeg.yml，使用 Stub 编译
```

## 5. 一次“正式构建”的完整链路

1. `git push` 触发 workflow；
2. macOS Runner：`Fetch FFmpeg XCFramework`（固定版本下载 + SHA-256 校验，失败即红）；
3. `xcodegen generate`（spec 含 6 个 libav 依赖 → Link + Embed Frameworks）；
4. 模拟器编译 + 单测；
5. Release 设备编译（链接并嵌入全部 libav 动态库）；
6. `Verify FFmpeg is embedded in the app`（硬验证，失败不打包）；
7. 打包未签名 IPA（自带 FFmpeg），上传 artifact。

产出：**IPA 自带 FFmpeg**；运行时 `FFmpegProcessorProvider` 走 `FFMPEG_ENABLED`
真实现，HLS/TS/DASH/FLV/MKV/WebM 全部在本地完成媒体后处理，最终只保留单一视频文件。

## 6. 接入清单（执行顺序）

- [x] 选定 FFmpeg XCFramework 产物（官方 FFmpeg 编译的纯 libav），固定版本与 SHA-256；
- [x] 下载/校验/头文件装配脚本（内置版本与校验和，无需配置仓库变量）；
- [x] XcodeGen 正式 spec：链接 + 嵌入 6 个 libav 动态框架；
- [x] Swift 桥接头（`__has_include` 守卫，双环境可编译）；
- [x] CI 产物硬验证（缺失 FFmpeg 即失败，禁止 FFmpegKit 出现）；
- [ ] 实现 `FFmpegLibraryProcessor`（`#if FFMPEG_ENABLED` 分支），替换 provider；
- [ ] 推一个提交触发 CI，确认构建日志出现 FFmpeg 链接、IPA 内含 FFmpeg；
- [ ] 真机验证各格式下载后均产出单一 MP4，且无任何中间文件残留。
