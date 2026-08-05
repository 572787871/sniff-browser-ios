# 开源项目说明

SniffBrowser 当前 App Target 没有引入第三方运行时软件包，主要依赖 Apple 系统框架。以下项目仅在架构研究阶段被阅读；其源码和资源未复制或编译进本应用。

| 项目 | 许可证 | 使用方式 |
| --- | --- | --- |
| [cat-catch](https://github.com/xifangczy/cat-catch) | GPL-3.0 | 仅研究资源过滤与交互流程，不使用源码 |
| [VBrowser-Android](https://github.com/xm0625/VBrowser-Android) | GPL-2.0 | 仅研究队列、状态与缓存思路，不使用源码 |
| [m3u8-dl](https://github.com/lzwme/m3u8-dl) | MIT | 研究 HLS 解析和调度思路，本项目使用 Swift/Apple API 独立实现 |
| [Kingfisher](https://github.com/onevcat/Kingfisher) | MIT | 研究图片缓存架构；当前未添加该依赖，使用系统 API 独立实现 |

## 内置数据

以下数据随 App 一起分发，必须保留相应版权声明。

### EasyList 广告过滤规则

- 来源：[easylist/easylist](https://github.com/easylist/easylist)（当前快照，由 [scripts/build-content-blocker.py](scripts/build-content-blocker.py) 生成）
- 许可证：[GPL-3.0-or-later](https://www.gnu.org/licenses/gpl-3.0.html) 或 [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)，二选一
- 署名要求：The EasyList authors (https://easylist.to/)
- 使用方式：内置为 `SniffBrowser/Resources/content-blocker-rules.json`，通过 `WKContentRuleList` 在浏览器内执行广告请求过滤。仅保留整域拦截规则（`||domain^`），未做其他修改。

> EasyList 官方许可说明：除特别注明外，EasyList 仓库内容按 GPL-3.0（或更新版本）与 CC BY-SA 3.0（或更新版本）双许可发布；按任一许可使用均需保留上述署名。本应用按 CC BY-SA 3.0 使用其中的过滤规则数据。

如果未来实际引入第三方源代码或二进制依赖，本文件必须同步加入对应版权声明和完整许可证文本，并在发布前重新审计兼容性。详细取舍见 [REFERENCE_IMPLEMENTATION_NOTES.md](REFERENCE_IMPLEMENTATION_NOTES.md)。
