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

## 2026-09-28：build 6 真机反馈后的广告与封面调研

本节是后续改造方案，尚未实现在 build 6。依据为用户截图、当前仓库源码和公开原作者代码；没有播放、下载用户媒体，没有抓取封面图片，没有调用用户视频对应的签名接口。

### 当前证据和可确认的问题

用户报告非 turbo 视频能正常打开；turbo 能先显示封面，点击网页播放按钮会出现广告。截图同时显示 App 的 `Opening system player...` 和网页的 `Ad` / `Close Ad` / `OK`。

1. `MediaPlayerController.startPlayer` 设置 `Opening system player...`，说明已经收到并接受一个候选媒体 URL，不能再把本例一概归为“没有解析出地址”。也不能因此认定该 URL 是正确、未过期且可由 AVKit 播放的正片。
2. `reload()` 对 iframe 保持 `webView.isHidden = false`；直到 `AVPlayerItem.status == .readyToPlay` 才隐藏它。因此系统播放器准备期间，用户仍能点击原网页里的控件，从而触发网页广告。这是可从本地代码确认的交互缺口。
3. `createWebViewWith` 拒绝新窗口、`decidePolicyFor` 限制跨站主页面导航，只能覆盖相应的导航行为；无法据此阻止同一个文档里的广告覆盖层。当前 CSS 只匹配少数通用 class，不能从截图反推出此广告层的 DOM selector。
4. `MediaProbe.js` 优先 `main-video`，但仍扫描其他 `video/audio`；Swift 设置 `attempted = true` 后会忽略后续候选。若先读到预览、过期或错误 URL，后来出现的有效 URL 不会自动接替。这是应在测试中覆盖的风险，尚未证明是截图中无法接管的原因。
5. 目前没有 iPhone 上 AVPlayerItem 的错误码、HTTP 状态、响应 MIME 或 Cookie/Referer 对照结果。不能把接管未完成直接诊断为某一种鉴权、解码或广告脚本依赖问题。

### 公开方案核对

| 来源 | 查证结果 | 对本项目的意义和局限 |
|---|---|---|
| [gallery-dl turbo.py](https://github.com/mikf/gallery-dl/blob/master/gallery_dl/extractor/turbo.py) | `TurboMediaExtractor` 先请求媒体页面，再在同一请求环境中调用站点的 `/api/sign`，从 JSON 读取 `url`，并保留媒体页 Referer 信息。2026-09-28 查询该文件最近提交为 `a2ac90ae36d6793309ab73fbf1e03da6f7820848`，日期 2026-01-19。 | 有比通用网页监听更明确的 provider resolver 参考。它是下载工具的代码，不能据此宣布今天的 iOS AVKit 一定兼容，也不是站点官方稳定 API 承诺。只借鉴协议流程，不复制 GPL 源码。 |
| [HeapLeach 原作者 README](https://github.com/JohanLindvall/HeapLeach) | 记录 turbo 使用签名接口发放短期地址，并在实际使用时才解析。 | 支持“封面先显示，点击时才取得播放地址”的时机选择；不把签名 URL 存入收藏或当永久直链。 |
| [FreeInternet-Media 原作者脚本](https://sleazyfork.org/it/scripts/580775-freeinternet-media-simpcity-goonbox-bunkr-downloader/code) | 代码独立构造 turbo CDN 的缩略图路径，点击后再解析媒体地址；有加载失败处理。 | 证明社区已有“缩略图与媒体解析分离”的实现。路径规则只作为待验证候选，不能承诺所有资源都有封面，或封面必定是第 0 帧。无需安装、执行或整体移植这个脚本。 |
| [Brave #56163](https://github.com/brave/brave-browser/issues/56163) / [uAssets #33212](https://github.com/uBlockOrigin/uAssets/issues/33212) | 描述广告脚本被阻断后的报错，但属于用户报告。uAssets issue 标为 `unable to reproduce`、`geo specific`、`account required`，关闭为 not planned；评论要求新浏览器配置仅使用默认 uBO 重试。 | 不能升级为“官方证明所有拦截器都无解”。可作为避免盲目阻断全部初始化脚本的线索，不能替代本机媒体错误诊断。 |
| [Webcompat #223961](https://github.com/webcompat/web-bugs/issues/223961) | 同一报告者提出 Cookie partitioning 假说，该 issue 位于 `invalid` milestone。 | 不把相似报告当作多个独立确认，也不据此关闭全局隐私保护或修改用户 VPN。 |

结论：值得优先验证 provider resolver 加系统播放器，而非围绕网页播放按钮堆积广告规则。此结论是结合源码和用户目标的工程取舍，不是已验证的 turbo 无广告播放结果。

### 建议的最小改造

1. 修正播放器等待态：点击 App 的播放入口后显示原生封面和 loading；AVKit 正常播放后显示播放器。失败则显示错误、Retry 和显式的 Web player 按钮，避免自动将带广告网页放回可点击区域。确实需要网页验证时由用户打开可见页面处理。
2. 为 turbo 增加小型 provider resolver：只针对明确识别的 provider/媒体链接，按照正常媒体页面及签名请求流程取得本次播放 URL；响应校验 HTTPS、类型和必要字段。不要移植整套下载器、增加远程中转或依赖全局广告拦截器。
3. 使用同一媒体请求会话处理该 provider 的 Cookie，仅对匹配域名/路径使用；论坛 Cookie 继续隔离。请求需要验证时回到可见验证流程，不伪造验证码结果或循环请求。
4. 有效地址交给现有 AVKit。若媒体响应依赖不能直接移交的 Referer、UA、Cookie 或其他请求上下文，需要先定位真实原因；JSON 返回 `url` 并不是播放验收。不要使用未公开的 AVURLAsset header key，先验证支持的 Cookie 路线；不能接管时明确报告，保留手动网页播放。
5. 补充本地且脱敏的诊断状态：解析阶段、耗时、AVPlayerItem status、错误 domain/code、媒体响应状态和 MIME。不给日志写完整 URL、query、Cookie、页面正文或图片；第一条候选失败后只对不同的新候选做有界重试。

如果仍需 WebKit 初始化，脚本正常运行与广告可见性应分别处理：可以用原生等待界面阻止用户误点网页广告，但这不代表广告网络请求为零。隐藏页面也不能修复不可播放的媒体响应。

### 封面图卡片方案

可以实现用户要求的“帖子里先看封面，点击图片或链接后进入播放器”。封面字段和媒体 URL 分开：

- `BodyBlock` 增加可空的 `posterUrl`；`url` 保持媒体页面或直接媒体地址，`directMedia` 保持现有分流含义。
- 优先解析 `<video poster>`，必要时在已初始化媒体页读取 `video.poster`。MDN 明确该字段表示尚无视频数据时展示的图片 URL，并不保证是视频第 0 帧：[HTMLVideoElement.poster](https://developer.mozilla.org/en-US/docs/Web/API/HTMLVideoElement/poster)。
- 对 turbo 使用经验证的 provider 缩略图规则或实际元数据。论坛外层 HTML 的 iframe 不会自动附带子页面的 poster；不能只修改 Flutter 图片 widget 就宣称解决所有来源。
- 卡片进入可视区域时懒加载图片，显示原生播放按钮和来源；点击图片与链接执行同一播放动作。图片失败、未知 provider 或无封面时保留占位和播放入口，不影响现有可播来源。
- 不在列表中启动每个 iframe、不提前请求整页视频的签名地址，也不为了生成封面预下载全部视频。封面可由平台图片缓存复用，首期不增加数据库或后台任务。
- 竖屏封面限制高度并保持比例，避免单张封面占满多屏。进入播放器后按视频本身的比例显示。

严格截取“第 0 帧”需要先有可读的媒体资源，再通过 [AVAssetImageGenerator](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator) 获取图像；这会增加媒体请求与解码开销，而且第 0 帧可能为黑屏。因此本需求优先实现 poster/thumbnail，不默认给每个帖子做远程视频抽帧。

### 改造后的验收标准

- 非 turbo 的已可播放来源不回归；帖子加载期间不开始播放任何视频。
- 有封面时在帖子内显示，点击进入独立播放器；封面失败仍能点播放。
- 加载和失败阶段不会自动露出可点击广告网页；网页模式由用户明确选择。
- 签名 URL 新鲜有效且真正开始播放、可暂停/拖动、Done 返回，才算该来源接管成功。不能以“封面显示”“有 URL”“readyToPlay”单独判定完成。
- 验证 Cookie/Referer 依赖、过期重试、慢网、403/验证页、错误 MIME、重复点击、返回后再次打开等行为。诊断不包含用户会话或完整媒体地址。

当前状态：已完成源码审查、公开方案查证和上述改造设计；尚未执行目标媒体签名/CDN 实测、未改动播放器代码、未生成新 IPA。手机仍运行 build 6。

## 2026-09-28：视频卡片和图片智能排版实现

用户进一步明确：缩略图上不放按钮，左图右侧独立播放框；普通图片自动展示，加载时有动画，“图片只能排版”指“图片智能排版”。本节覆盖前述卡片交互建议：只有右侧播放区触发播放器，缩略图自身不触发播放。

- `BodyBlock.posterUrl` 与播放 `url` 分离。优先使用 HTML 的 `poster` / `data-poster`；对精确匹配的 turbo HTTPS 链接，采用上文原作者脚本提供的 CDN thumbnail 路径候选。没有实际请求用户视频封面验证，也不保证该路径对全部视频可用。
- `MediaCard` 左侧为 96 高的缩略图区，图片保持比例，右侧为独立边框的 `Tap to play`。封面失败只显示占位图标，不阻止播放入口；没有 poster 的未知 provider 也保留入口，不为每张卡片创建 WebView。
- 图片与封面在对应楼层 widget 构建时自动请求，不要求点击；加载首帧期间显示 CircularProgressIndicator，系统减少动画时使用静态占位。普通图片失败显示 Retry image，点击后驱逐失败缓存并重新请求。Spoiler 展开前不请求其内部图片。
- 连续图片分组，遇到文字、引用、视频或 Spoiler 就结束当前组，不调换正文顺序。按可用宽度使用 1/2/3 列；超宽或很长的图片单独成行。优先采用有效 width/height，解码后按实际比例调整，BoxFit.contain 不拉伸、不裁切。
- 单行预览最高 420 logical pixels，多图行最高 260；点击普通图片进入独立 InteractiveViewer，支持缩放和平移。大图解码有尺寸上限，使用 Flutter 图片缓存，不新增数据库、图片代理或整页视频预下载。
- 示例资源均为本地生成的抽象图形，不含用户媒体。视频示例的封面明确标为 sample cover art，不冒充视频首帧。

本次没有修改原生 MediaPlayerController 或签名解析链路，因此 turbo 的网页广告与 AVKit 接管问题仍待后续实现与真机验证；不能用封面显示成功代替播放成功。需要 Cookie、Referer 或其他站点限制的图片仍可能失败，不会将论坛 Cookie 转发给外部图片 host。

验证：53 项 Flutter tests、Dart analyze、仓库语言检查和 Web release build 通过。新增测试覆盖自动请求/loading、失败重试、缩放跳转、连续图片与文字顺序、长图高度、Spoiler 按需加载、无效封面 URL、窄屏大字体和缩略图不触发播放。

实现参考：[Flutter frameBuilder](https://api.flutter.dev/flutter/widgets/Image/frameBuilder.html)、[InteractiveViewer](https://api.flutter.dev/flutter/widgets/InteractiveViewer-class.html)、[ImageProvider.evict](https://api.flutter.dev/flutter/painting/ImageProvider/evict.html)。
