# FFmpeg 正式集成方案（GitHub Actions 全自动）

目标：**GitHub 每次构建产出的 IPA 都自带 FFmpeg**，不需要手工集成，也不需要修改任何业务代码。本地开发没有 FFmpeg 时仍可编译（使用 Stub），但**正式 CI 构建必须包含真正的 FFmpeg**。

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
   │     ├── 真实现：BundledFFmpegProcessor / FFmpegLibraryProcessor（XCFramework）
   │     └── StubFFmpegProcessor（仅本地无 FFmpeg 时编译用）
        │
        ▼
最终视频文件 → 更新数据库 → 自动清理缓存
```

下载模块与 Media Pipeline 永远不感知 FFmpeg 的集成方式；将来切换实现只改
`FFmpegProcessorProvider.current` 一行，其余代码零改动。

## 2. FFmpeg XCFramework 获取方式

正式版只使用**官方 FFmpeg 编译的 iOS XCFramework（或可信的预编译 FFmpeg XCFramework）**，不使用 FFmpegKit / mobile-ffmpeg。

推荐两种途径（二选一）：

### 2.1 可信预编译 XCFramework（快，推荐先落地）
- 选用固定版本、带校验的预编译产物（例如社区维护的官方 FFmpeg iOS 静态 XCFramework 发布版）。
- 把下载地址固定到 `scripts/fetch-ffmpeg-xcframework.sh` 顶部的
  `FFMPEG_XCFRAMEWORK_URL`（或 GitHub Actions 变量），下载后校验 SHA-256 再落盘到 `vendor/FFmpeg.xcframework`。

### 2.2 CI 内从官方源码编译（慢但可复现）
- macOS Runner 上拉取官方 FFmpeg 源码 + iOS 交叉编译脚本，产出静态 XCFramework。
- 优点：完全可控、可复现；缺点：单次构建增加约 30–60 分钟。
- 建议把编译产物缓存到 GitHub Actions 的 actions/cache，避免每次全量编译。

无论哪种方式，**CI 中拉取失败或校验失败都必须让构建失败**（不允许回退到 Stub）。

## 3. Xcode 工程自动集成

采用 **XcodeGen** 双 spec 方案：

### 3.1 文件

| 文件 | 作用 |
| --- | --- |
| `project.base.yml` | 全部业务 target/scheme/settings（单一事实来源） |
| `project.yml` | `include: project.base.yml` + FFmpeg 依赖与链接设置（正式构建用） |
| `project.nofmpeg.yml` | `include: project.base.yml`，无 FFmpeg（本地无 FFmpeg 时用） |
| `scripts/generate-project.sh` | 检测 `vendor/FFmpeg.xcframework` 存在与否，选择对应 spec 生成工程 |

### 3.2 Link Binary With Libraries（XcodeGen `dependencies`）

`project.yml` 中 SniffBrowser target 增加：

```yaml
    dependencies:
      - framework: vendor/FFmpeg.xcframework
        embed: false          # 静态 XCFramework 不需要 Embed；动态才需要 true
```

XcodeGen 会为 `.xcframework` 生成 PBXFileReference 并加入 **Link Binary With Libraries**。

### 3.3 Build Settings

`project.base.yml` 的 `settings.base` 统一加入（对有无 FFmpeg 都无害）：

```yaml
FRAMEWORK_SEARCH_PATHS: "$(inherited) $(SRCROOT)/vendor"
OTHER_LDFLAGS: "$(inherited) -lz -liconv -lbz2 -lc++"
```

`project.yml`（正式版）在 `OTHER_LDFLAGS` 上追加 `-framework FFmpeg`：

```yaml
OTHER_LDFLAGS: "$(inherited) -framework FFmpeg -lz -liconv -lbz2 -lc++"
```

> 静态 FFmpeg 依赖 `libz / libiconv / libbz2 / libc++`，这些是 iOS 系统库；
> 若预编译产物需要其他依赖（如 libxml2），在 `OTHER_LDFLAGS` 追加即可。

### 3.4 Embed Frameworks

- 静态 XCFramework：无需 Embed（链接进可执行文件）。
- 动态 XCFramework：`embed: true`，XcodeGen 会把它加入 **Embed Frameworks** build phase，
  并配合 `LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/Frameworks"`。

### 3.5 Info.plist / 编译条件

不需要改 Info.plist。实现切换用 Swift 编译条件：

```swift
enum FFmpegProcessorProvider {
    static var current: FFmpegProcessor {
        #if FFMPEG_ENABLED
        return FFmpegLibraryProcessor()   // XCFramework 实现
        #else
        return StubFFmpegProcessor()      // 本地无 FFmpeg 编译用
        #endif
    }
}
```

`FFMPEG_ENABLED` 由 `project.yml` 的 Swift 编译条件注入：

```yaml
SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) FFMPEG_ENABLED"
```

> 当前代码库中的 `BundledFFmpegProcessor`（posix_spawn 调用捆绑可执行文件）保留为
> 开发期真实现；接入 XCFramework 后新增 `FFmpegLibraryProcessor`（调用 libav* API），
> 只需替换 `FFmpegProcessorProvider.current`，下载模块与 Media Pipeline 零改动。

## 4. GitHub Actions 自动构建 IPA

`build-ios.yml` 的步骤顺序（已配置）：

```yaml
- name: Fetch FFmpeg XCFramework
  run: bash scripts/fetch-ffmpeg-xcframework.sh

- name: Generate Xcode project
  run: bash scripts/generate-project.sh
```

`fetch-ffmpeg-xcframework.sh` 的行为：

1. 若 `vendor/FFmpeg.xcframework` 已存在且校验通过 → 直接使用；
2. 否则从 `FFMPEG_XCFRAMEWORK_URL`（GitHub Actions 变量）下载，校验 SHA-256；
3. **任何一步失败 → 构建失败**（正式版不允许无 FFmpeg 出包）。

本地开发（无 FFmpeg）：

```bash
bash scripts/generate-project.sh   # 自动选择 project.nofmpeg.yml，使用 Stub 编译
```

## 5. 一次“正式构建”的完整链路

1. `git push` 触发 workflow；
2. macOS Runner：`Fetch FFmpeg XCFramework`（下载/校验，失败即红）；
3. `xcodegen generate`（spec 含 FFmpeg 依赖 → Link Binary With Libraries；
   静态则无需 Embed）；
4. 模拟器编译 + 单测（含 Media Pipeline 测试）；
5. Release 设备编译（链接 FFmpeg 静态库，`OTHER_LDFLAGS` 带系统依赖）；
6. 打包未签名 IPA（包含 FFmpeg）；
7. 上传 artifact。

产出：**IPA 自带 FFmpeg**；运行时 `FFmpegProcessorProvider` 走 `FFMPEG_ENABLED`
真实现，HLS/TS/DASH/FLV/MKV/WebM 全部在本地完成媒体后处理，最终只保留单一视频文件。

## 6. 接入清单（执行顺序）

- [ ] 选定 FFmpeg XCFramework 产物（官方编译或可信预编译），固定版本与 SHA-256；
- [ ] 在 GitHub 仓库 Secrets/Variables 配置 `FFMPEG_XCFRAMEWORK_URL`（与 SHA）；
- [ ] 实现 `FFmpegLibraryProcessor`（`#if FFMPEG_ENABLED` 分支），替换 provider；
- [ ] 推一个提交触发 CI，确认构建日志出现 FFmpeg 链接、IPA 内含 FFmpeg；
- [ ] 真机验证各格式下载后均产出单一 MP4，且无任何中间文件残留。
