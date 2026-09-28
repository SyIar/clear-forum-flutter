# 嵌入媒体兼容性调研

日期：2026-09-28。范围：用户已打开页面的 DOM 只读检查、用户脚本源码和公开问题记录。没有播放、下载媒体，没有修改浏览器拦截设置，也没有保存完整媒体地址、签名参数值、Cookie 或账号信息。

## 修复前客户端的缺口

- `ForumParser._unwanted` 和 `parseBody` 都删除或跳过 iframe。
- iOS `ForumBrowserController.readPage` 导出的 HTML 同样删除 iframe。
- `BlockKind` 及 `RichBody` 尚无嵌入播放器模型和渲染分支。
- iOS 内置浏览器有针对 `clickadu.net` 的 block 规则，但本次没有实测该规则对手机播放器初始化的影响。

因此播放器在原生阅读界面中消失，首先是客户端未保留嵌入内容；不能直接归因于媒体 CDN 或广告脚本。

## 本次浏览器证据

用户提供页面的主要内容区域包含 10 个 iframe：9 个来自 `turbo.cr` 的 embed 路径，另 1 个来自其他媒体域名。仅检查其中一个已加载的 turbo iframe：

| 字段 | 观察结果 |
|---|---|
| 元素 | `video#main-video` 存在 |
| `src` / `currentSrc` | 都已设置为 HTTPS `.mp4` 地址 |
| 地址参数名 | `exp`、`token`、`fn`；未保存参数值 |
| `readyState` | `0`，没有以此证明媒体已加载 |
| `paused` | `true` |
| `error` | 当次读取为 `null`，不能替代播放验证 |

这只证明当前桌面浏览器、当前 iframe 的初始化已经提供一个媒体地址。未验证 CDN 响应、Range、独立播放器、Cookie/Referer 依赖、链接过期恢复或 iOS WKWebView 兼容性。其他 iframe 不因单个样本而视为通过。

## 用户提供方案的核对

[Turbo.cr Video URL Overlay 源码](https://greasyfork.org/en/scripts/569537-turbo-cr-video-url-overlay/code)在页面 load 后延迟一秒，查找 `#main-video` 并显示其 `src`，点击时复制该字段。代码没有生成签名、修复播放器初始化或处理广告脚本依赖。如果视频元素或地址尚未就绪，脚本无法提供可用地址；复制已有地址也不等于无需网页初始化。

[Brave #56163](https://github.com/brave/brave-browser/issues/56163)是用户提交的故障报告，描述屏蔽广告脚本后发生 ReferenceError 和媒体加载失败。本次打开时 issue 显示 Closed；读取到的页面没有提供足以将其结论升级为 Brave 官方确认、所有扩展均无解或当前版本必现的证据。

[MDN currentSrc](https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/currentSrc)说明该字段是播放器所选择的资源 URL，未选择资源时可以为空。论坛主文档不能通过普通页面 JavaScript 任意读取跨源 iframe 的 DOM，见 [MDN 同源策略](https://developer.mozilla.org/en-US/docs/Web/Security/Defenses/Same-origin_policy)；开发工具可检查子 frame 不代表 App 中的主 frame 脚本具有相同访问能力。

## 实现取舍

可以先为通用嵌入内容保留清晰的占位和原页面入口，避免静默丢失内容。若继续验证原生播放器接管，应以用户按需打开、媒体页面正常初始化、获取已提供的资源、原生播放验证为独立阶段，分别记录成功或失败。

不能把一次拿到带签名参数的地址当成永久直链，也不能承诺这条路线会消除初始化过程中的广告网络请求。需要登录、验证、访问权限或媒体不可用时，应如实提示，不伪造成功或无限重试。本次调研没有实现播放器接管。

## 当前 HTML 的本地解析验证

用户授权后，将当前页面主要内容区保存为仅本地调试快照，排除脚本、表单输入和事件属性，没有导出 Cookie。快照在被 Git 忽略的 `artifacts/local-dom/` 下，不进入公开仓库或 CI。

使用 `tool/inspect_html.dart` 对该快照实际运行同一 `ForumParser`，输出仅包含结构计数：18 个原始楼层解析为 18 个楼层，10 个正文 iframe 转为 10 个 `embeddedMedia` 占位，73 个图片块，0 个空楼层，页码 5。没有下载或播放媒体。

`Read page` 导出和 Dart parser 不再一律丢弃 iframe。渲染仅显示来源 host 及未支持播放的提示，不加载 iframe 或执行脚本，已知广告容器仍剔除。完整签名媒体地址不会保存在模型或收藏夹。这修复了内容静默消失，但不代表原生视频播放已完成。
