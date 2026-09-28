# 实现与验收

## 当前实现

首期为纯净阅读器，采用 Cookie 会话、页面 HTML 解析、Flutter 原生阅读界面。登录和网页验证使用可见的 WKWebView。浏览器正常显示目标页面后，用户可以点击 Read page 将当前页面转成原生阅读界面。

Cookie 留在 App 的 WKWebsiteDataStore，原生 URLSession 仅向固定站点的读取路径发送匹配的 Cookie。重定向逐跳验证，未知路径和跨域重定向不会继续携带会话请求。HTML 不落盘、不上传，Flutter 不获得 Cookie 值。外部图片点击后才请求，不附带论坛 Cookie。

HTTP 与 WebView 是不同的请求环境，HTTP 读取可能遇到独立验证。Read page 是可见网页的手动阅读模式，不绕过验证，也不代表随后所有 HTTP 分页请求都会成功。

## 功能边界

- 原生支持分类、主题列表、单行置顶、帖子楼层、分页、引用、Spoiler 和基本文本格式。
- 不原生实现写操作、私信、搜索表单、后台推送和批量下载。视频入口与 iOS 播放器的本次新增实现见下文。
- App 使用英文控件文案和系统字体；来源内容按原文呈现。
- 去广告采用内容区域提取和已知广告容器过滤，不能保证识别正文中的所有推广。
- WebView 基础过滤仅覆盖已核实的广告来源与容器；正常登录与验证码仍由用户操作。
- 示例数据明确标为 SAMPLE CONTENT，不代表真实登录成功。

## 验证状态

初始版本已通过本地 Dart analyze、23 项 Flutter tests 和 Web release build。Chrome 390 x 844 预览检查了分类、单行置顶和紧凑楼层。后续补充了分页失败重试及示例菜单的回归检查，并补齐 iOS 导航图标字体。

首次交付 [Actions 36379932292](https://github.com/SyIar/clear-forum-flutter/actions/runs/36379932292) 已成功：Dart analyze、25 项 Flutter tests、Web release build、原生 URL/Cookie policy 检查、Xcode unsigned iOS build 和 IPA 校验全部通过。

| 项目 | 结果 |
|---|---|
| App | Clear Forum 0.1.0 (3) |
| Bundle ID | `dev.sylar.clearforum` |
| 构建源码 | `cb57b8976a21bd91411499057091776e81ca8c86` |
| Xcode | 26.3，Build 17C529 |
| 签名状态 | unsigned，需要在本地签名后安装 |
| 本地安装包 | `D:\workspace\sideloadly-setup\ClearForum-unsigned.ipa` |
| SHA-256 | `96d867830442521eca9e11290f13998b11d6ab4fef09d5a794377a9aa929bb06` |

下载后已再次验证 ZIP 完整性、App 必要文件、Bundle ID、版本与校验值。CI 额外确认 device 平台和 arm64。

2026-09-28，用户授权后通过 Sideloadly USB 安装 `0.1.0 (3)`，主窗口显示 `Done. / 100%`。13:12:58 daemon 设备扫描确认 Clear Forum build `3`，自动刷新记录与 IPA 缓存均已生成，缓存大小为 `7,446,442` bytes。用户确认可以正常打开 App。本次没有验证无线安装、接近到期时的后台刷新或开机自启动。

真实 iPhone 登录、Cookie 持久化、站点分页和外部图片加载尚未验收。当前未把桌面浏览器 Cookie 导入 App，也没有修改现有 Tieba Lite。

## 2026-09-28：论坛列表缺少主题的修复

用户报告 `/forums/instagram.12/` 在客户端没有正常显示列表。通过桌面浏览器只读检查 DOM，页面具有 21 个 `.structItem--thread`：1 条置顶使用标准帖子链接，20 条普通主题使用 `/threads/<slug>.<id>/unread?new=1`。原 `ForumSite.readable` 拒绝后者，`ForumParser` 因而漏掉普通主题。没有导出 Cookie、token 或账号数据。

`ForumSite.resolve` 现在将本站已核实的 unread 链接转为标准帖子地址，进入帖子第一页。实际 HTTP 请求仍使用原有的读取路径约束，没有开放互动接口或跨站会话请求。页面存在主题行却全部解析失败时，改为明确提示无法解析，不再冒充空论坛。示例列表也包含 unread 链接，避免桌面预览再次遗漏这一场景。

本地 Dart analyze、29 项 Flutter tests 和仓库语言检查已通过。回归覆盖 1 条置顶加 20 条 unread 主题、分页、Unicode slug、非法链接和原生阅读导航。电脑调试入口为 `http://127.0.0.1:8879/`，使用同一 Flutter 界面及解析器，但展示明确标记的示例数据。此修复尚未构建新 IPA，也未更新手机上的 build 3。

## 2026-09-28：本地收藏与最近阅读

- App display name 改为 `simpcity ultimate`，使用青色、黑色、白色的方形生成图标。保持 `dev.sylar.clearforum`，便于覆盖升级；图标生成记录在 `BRANDING.md`。
- 首页增加 Bookmarks 和 Recent reading。首页右上角 Add bookmark 可填写本站 URL 和可选标题；阅读页右上角可以收藏/取消收藏当前页面，Home 按钮直接返回首页。
- 收藏保存完整 URL（包含页码和 `#post-...`）。最近阅读仅在页面加载成功后记录，最近在前、最多 10 项；同一帖子各分页去重，保存最近打开的页码。暂不恢复精确滚动位置。
- 使用 Flutter 官方 `shared_preferences` 的 Async API 保存本地 JSON，iOS 使用 NSUserDefaults，Web 示例使用浏览器存储。写入串行化并在成功后更新可见状态；写失败提示，不伪装已保存。真实库与示例库使用不同 key。
- 仅保存标题和本站读取 URL，不同步到云端，不存 HTML、Cookie 或媒体签名。Clear recent reading 不删除收藏；Clear session 仅清理登录会话，收藏和历史仍保留。App 卸载会丢失本地库。
- 真实 HTML 结构检查：18 个楼层、10 个嵌入占位、0 个空楼层，详见 `EMBEDDED_MEDIA.md`。原生视频播放仍未实现。

本地 `flutter analyze`、41 项 Flutter tests 和 `flutter build web --release --no-pub` 已通过。新增回归覆盖存储重启、最近 10 项、跨分页去重、并发保存、失败重试、URL 校验、首页收藏重开、示例数据隔离和窄屏大字体。

资料：[Flutter shared_preferences](https://pub.dev/packages/shared_preferences)。这里只保存少量个人阅读偏好，无需增加数据库或服务器同步。

## 已验收安装包：simpcity ultimate 0.1.0 (5)

[Actions 36383244723](https://github.com/SyIar/clear-forum-flutter/actions/runs/36383244723) 全部成功：仓库检查、Dart analyze、42 项 Flutter tests、Web release build、原生 URL/Cookie policy 检查、Xcode unsigned iOS build 与 IPA 校验。构建源码为 `ff0d15ff3d6cbbf18ad3195c45d4eea9b7c13d9b`。其中新增的最后一项回归确保不含锚点的 URL 不会多出空 `#`，避免首页手动收藏与阅读页收藏状态不一致。

- Display name：`simpcity ultimate`。
- Bundle ID：`dev.sylar.clearforum`，保持原有 App 身份。
- Xcode：26.3 / 17C529。
- 安装包：`D:\workspace\sideloadly-setup\SimpcityUltimate-0.1.0-5-unsigned.ipa`。
- SHA-256：`2102e5f25de4db7d07b49c55307fb6d47134f4f8e802ceca4f5914aa6c7c9dde`。
- 已在下载后校验 ZIP 完整性、device 平台、Bundle ID、display name、版本、构建源码和 SHA-256。
- 浏览器实际验证收藏完成态、回首页显示、刷新后持久化；截图只含示例内容，保存在本地 `artifacts/simpcity-ultimate-home.png`。

下载制品为 unsigned。2026-09-28，用户授权后通过 Sideloadly 对该制品签名并通过 `@Wi-Fi` 安装，主窗口显示 `Done. / 100%`。用户确认 `simpcity ultimate` 能正常打开，新图标和首页 Bookmarks、Recent reading 显示正常。手机已验收版本更新为 build 5。

新增收藏的 iPhone 冷启动持久化、真实账户阅读、嵌入视频播放和本次安装后的自动续签尚未单独验收；桌面浏览器登录 Cookie 未改动。

## 2026-09-28：视频入口修复

build 5 的视频卡片只有占位提示，确实不能播放。本次将其改为可点击入口，增加原生 `AVPlayerViewController` 和独立 WKWebView 媒体页。网页正常初始化后，观察已提供的 HTTPS 媒体地址并尝试系统播放；失败时保留 `Web player`，`Reload` 可以重新初始化。细节、Cookie 隔离及兼容性边界见 [EMBEDDED_MEDIA.md](EMBEDDED_MEDIA.md)。

本地 `flutter analyze`、46 项 Flutter tests、Node 媒体 observer 检查、仓库语言检查和 Web release build 已通过。电脑浏览器已检查示例帖新增卡片显示，桌面预览不运行 iOS 播放器。Demo 的第二楼提供 Apple 官方 BipBop 测试流，便于手机端先验证系统播放器。

## 最新安装包：simpcity ultimate 0.1.0 (6)

[Actions 36386143295](https://github.com/SyIar/clear-forum-flutter/actions/runs/36386143295) 全部成功：Dart analyze、46 项 Flutter tests、Node observer 检查、Web release build、原生 URL/Cookie policy 检查、Xcode unsigned iOS build 和 IPA 校验。

- 构建源码：`20795bc6d77b70b1c0e542ec6ef29838ab4b4dcb`。
- Xcode：26.3 / 17C529。
- 安装包：`D:\workspace\sideloadly-setup\SimpcityUltimate-0.1.0-6-unsigned.ipa`。
- 大小：9,628,187 bytes。
- SHA-256：`e59c467f08fd3dc8fa5a6cdfa092653f9d284ebc0693c326adcc56cf89df9dfd`。
- 下载后再次核对 ZIP、Bundle ID、display name、device 平台、版本、构建源码、SHA-256 与 `MediaProbe.js` 资源存在；复制到安装目录后再次核对文件 hash。

2026-09-28，用户连接 USB 并授权安装。安装前重新核对 build 6 IPA 的 SHA-256；Sideloadly 文件选择框确认 `SimpcityUltimate-0.1.0-6-unsigned.ipa`，使用原签名账户及 `@USB` 设备开始安装，从 0% 进入 `Done. / 100%`。build 6 已完成签名和 USB 安装。

build 6 的 App 启动、Apple 示例流和实际媒体站真机播放等待用户验证。安装成功不代表外部媒体站已能播放，也不代表已完全去除媒体页广告；本次未单独验收自动续签。

## iPhone 验收

1. 安装后选择 Open forum；可阅读公开页面，受限页面提示登录或打开浏览器。
2. Sign in 打开网站，由用户本人完成登录和任何验证码。
3. 登录后点击 Done，检查原生列表；若 HTTP 仍提示验证，在浏览器打开目标页面后点击 Read page。
4. 检查普通帖子分页、引用、Spoiler 和单行置顶；验证广告容器不出现在原生界面。
5. 冷启动后验证会话恢复。点击 Clear session 后应移除 App 自己的浏览器数据并关闭已打开阅读页面。
6. 记录哪些路径只支持浏览器手动读取，以及哪些外部资源无法直接加载。
7. 从首页进入示例帖子，在第二楼点击 Apple HLS 卡片；确认出现系统播放器、播放/暂停可用，Done 返回原阅读页。
8. 对合法可访问的嵌入测试页检查初始化、系统播放、Web player 切换、Reload 和 Done。网络或媒体源失败应显示原因，不能卡在占位或无限重试。

## 资料

- [Flutter iOS deployment](https://docs.flutter.dev/deployment/ios)
- [WKHTTPCookieStore](https://developer.apple.com/documentation/webkit/wkhttpcookiestore)
- [WKContentRuleList](https://developer.apple.com/documentation/webkit/wkcontentrulelist)
- [Cloudflare supported browsers](https://developers.cloudflare.com/cloudflare-challenges/reference/supported-browsers/)

更完整的前期调研保存在工作区独立的 simpcity-client-research/RESEARCH.md，不包含用户会话和个人浏览内容。
