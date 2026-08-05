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

### Ka-Block 广告过滤规则

- 来源：[dgraham/Ka-Block](https://github.com/dgraham/Ka-Block) `Extension/blockerList.json`
- 许可证：MIT License
- 版权：Copyright (c) 2015-2019 David Graham & Josh Peek
- 使用方式：内置为 `SniffBrowser/Resources/content-blocker-rules.json`，通过 `WKContentRuleList` 在浏览器内执行广告请求过滤，未做修改。

```
MIT License

Copyright (c) 2015-2019 David Graham & Josh Peek

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

如果未来实际引入第三方源代码或二进制依赖，本文件必须同步加入对应版权声明和完整许可证文本，并在发布前重新审计兼容性。详细取舍见 [REFERENCE_IMPLEMENTATION_NOTES.md](REFERENCE_IMPLEMENTATION_NOTES.md)。
