# 开源项目说明

SniffBrowser 当前 App Target 没有引入第三方运行时软件包，主要依赖 Apple 系统框架。以下项目仅在架构研究阶段被阅读；其源码和资源未复制或编译进本应用。

| 项目 | 许可证 | 使用方式 |
| --- | --- | --- |
| [cat-catch](https://github.com/xifangczy/cat-catch) | GPL-3.0 | 仅研究资源过滤与交互流程，不使用源码 |
| [VBrowser-Android](https://github.com/xm0625/VBrowser-Android) | GPL-2.0 | 仅研究队列、状态与缓存思路，不使用源码 |
| [m3u8-dl](https://github.com/lzwme/m3u8-dl) | MIT | 研究 HLS 解析和调度思路，本项目使用 Swift/Apple API 独立实现 |
| [Kingfisher](https://github.com/onevcat/Kingfisher) | MIT | 研究图片缓存架构；当前未添加该依赖，使用系统 API 独立实现 |

如果未来实际引入第三方源代码或二进制依赖，本文件必须同步加入对应版权声明和完整许可证文本，并在发布前重新审计兼容性。详细取舍见 [REFERENCE_IMPLEMENTATION_NOTES.md](REFERENCE_IMPLEMENTATION_NOTES.md)。
