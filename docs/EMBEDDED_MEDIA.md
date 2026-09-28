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

## build 5 的实现取舍

可以先为通用嵌入内容保留清晰的占位和原页面入口，避免静默丢失内容。若继续验证原生播放器接管，应以用户按需打开、媒体页面正常初始化、获取已提供的资源、原生播放验证为独立阶段，分别记录成功或失败。

不能把一次拿到带签名参数的地址当成永久直链，也不能承诺这条路线会消除初始化过程中的广告网络请求。需要登录、验证、访问权限或媒体不可用时，应如实提示，不伪造成功或无限重试。本次调研没有实现播放器接管。

## 当前 HTML 的本地解析验证

用户授权后，将当前页面主要内容区保存为仅本地调试快照，排除脚本、表单输入和事件属性，没有导出 Cookie。快照在被 Git 忽略的 `artifacts/local-dom/` 下，不进入公开仓库或 CI。

使用 `tool/inspect_html.dart` 对该快照实际运行同一 `ForumParser`，输出仅包含结构计数：18 个原始楼层解析为 18 个楼层，10 个正文 iframe 转为 10 个 `embeddedMedia` 占位，73 个图片块，0 个空楼层，页码 5。没有下载或播放媒体。

额外结构检查：这份外层 HTML 有 10 个 iframe，但 `video` 和 `source` 元素均为 0。子 frame 的 `currentSrc` 不会自动包含在论坛外层 `outerHTML` 中，因此仅解析当前这份 HTML 无法完成用户脚本所做的地址读取。

build 5 的 `Read page` 导出和 Dart parser 不再一律丢弃 iframe。渲染仅显示来源 host 及未支持播放的提示，不加载 iframe 或执行脚本，已知广告容器仍剔除。这修复了内容静默消失，但没有实现视频播放。

## 2026-09-28：播放入口与 iOS 播放器

用户手机截图确认 build 5 仍显示 `Playback is not supported in this reader.`。这是客户端未实现播放的明确提示，不能据此判断订阅、网络或媒体源故障。

本次实现：

- Dart 保留 iframe 的 HTTPS URL，以及 video/audio 的 `src` 或子 `source[src]`。卡片改为按需打开，进入帖子本身不会启动任何播放器。
- 直接媒体 URL 交给 `AVPlayerViewController`。嵌入页在独立可见 WKWebView 正常初始化；`MediaProbe.js` 在隔离的 content world 观察 `currentSrc`/`src`，优先 `main-video`，排除已知广告容器，只接受 HTTPS。
- Swift 再校验消息 frame 与打开的媒体页同源，再尝试 AVKit。只交接已由网页提供的地址，不生成签名、不移除验证或权限检查。`blob:`/MSE、跨域子播放器和特殊鉴权仍可能需要网页播放器。
- 同一次打开仅自动尝试一次 AVKit。发生错误或 25 秒未开始播放则返回网页；`Web player` 可手动切换，`Reload` 重新加载并重试。浏览器验证需要用户在可见页面操作。
- WKWebView 使用独立、非持久的 `WKWebsiteDataStore`，不传入论坛 Cookie。只有媒体页自身产生、且域名/路径匹配的 Cookie 通过官方 `AVURLAssetHTTPCookiesKey` 交给 AVKit。完整媒体地址只存内存，不写入日志、收藏、最近阅读或 CI。
- 媒体页只做已知广告容器的 CSS 隐藏，并限制新窗口和跨站主页面跳转；不阻断可能参与初始化的广告脚本。仍可能有广告请求或未识别的广告元素，不承诺完全去广告。
- 关闭播放器清理观察器、计时器、播放资源和消息处理器；返回 Flutter 后可以打开其他媒体。保留现有论坛会话及本地收藏。

取舍：先使用 Apple 系统播放器和 WebKit，不增加服务器代理、下载器、第三方解码库或私有 HTTP header 选项。需要特殊 Referer/UA、DRM、登录、不可用或过期的资源可能无法接管。媒体页面只发送论坛 origin 的 Referer，不发送帖子路径或论坛 Cookie；AVKit 不伪造 Referer。

验证使用合成 HTML/URL，以及 [Apple 官方 BipBop HLS 示例](https://developer.apple.com/streaming/examples/advanced-stream-hevc.html)。示例帖子第二楼增加该公开测试流卡片，仅点击后请求；自动化检查不请求用户媒体。Flutter 测试覆盖解析、按需点击、Spoiler、无效 URL 与 method channel；Node 检查异步地址、重复扫描、广告容器过滤和 observer 清理；macOS CI 检查 Swift URL/Cookie policy 并编译完整 iOS App。

通过编译和这些检查不等于目标媒体站已能播放。`turbo.cr`、`cyberdrop.cr` 的真机初始化、CDN 请求及最终播放尚未验收。先在手机用示例流确认系统播放器，再区分媒体页加载失败、未找到地址、AVKit 接管失败等状态。

Apple 依据：[AVPlayerViewController](https://developer.apple.com/documentation/avkit/avplayerviewcontroller)、[WKUserScript 的 content world](https://developer.apple.com/documentation/webkit/wkuserscript/init(source:injectiontime:formainframeonly:in:))、[WKScriptMessage.frameInfo](https://developer.apple.com/documentation/webkit/wkscriptmessage/frameinfo)、[AVURLAssetHTTPCookiesKey](https://developer.apple.com/documentation/avfoundation/avurlassethttpcookieskey)。
