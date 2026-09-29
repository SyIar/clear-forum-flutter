# Gofile 原生文件查看器

后续交付：查看器和递归串行下载已包含在 [build 1027](BUILD_1027.md)，云端检查与 iPhoneOS 编译通过，实际真机效果待验收。

## 调研结果（2026-09-29）

用户明确授权检查提供的 Gofile 测试目录。Chrome 实际读取到 6 个图片条目；下载首个 PNG 得到 **70,932 bytes**，文件头为有效 PNG。没有读取或导出浏览器 Cookie、账号 token 或 localStorage。

对该文件地址执行不带 Cookie 的请求，复现以下结果：

1. 存储节点的 `/download/web/{fileId}/{filename}` 返回 **HTTP 302**。
2. 跳转到 `https://gofile.io/d/{fileId}`。
3. 最终返回 **HTTP 200 / text/html / 3,358 bytes**，内容是 Gofile 网页入口。

因此，“约 3 KB 的下载文件”可以由下载会话不完整、文件请求被重定向到网页后，调用方仍保存响应造成。**未拿到用户 iPhone Safari 那次下载的原始文件或网络记录，不能宣称已证明 Safari 丢 Cookie，或已排除其他原因。** 本次证明的是与症状一致的可复现机制，不能根据扩展名或 HTTP 200 判定下载成功。

官方前端 `files/manager.js` 中的 `downloadItem` 使用 `item.link` 创建普通链接；`accounts/accountService.js` 将当前账号同步为父域 `accountToken` Cookie，供存储子域使用。目录列表也承担访问验证。直接复制地址并换一个缺少会话的下载环境不可靠。

## 实现

- South 和 Simp 正文中的 Gofile `/d/{id}` 分享链接进入原生 SwiftUI 文件列表。`/download/web/{id}/...` 文件链接先回到对应文件页面，重新取得当前会话的元数据。Gofile 帮助、API、账号等非文件页面继续使用普通内置浏览器。
- 阅读页面使用 NavigationStack push，保留论坛阅读位置和系统侧滑返回。论坛网站视图中的外链也接入 Gofile 入口。
- 列表包含名称、大小、文件夹、缩略图、分页和当前页本地搜索。按可见行加载缩略图，限制 160 px 解码大小、24 MiB / 100 项内存缓存。原生文件传输和缩略图共用串行调度器；批量期间暂停当前列表的缩略图请求。
- 使用独立、持久化的 WKWebsiteDataStore；不与 South、Simp 或 Safari 共享 Cookie。浏览器中的现有登录不会自动迁移，首次可使用网站正常创建的 guest 会话。密码使用原生 SecureField，登录和站点验证仍可在 App 内网站视图完成。
- WKWebView 负责网站原有初始化和访问验证；原生端只接收经过字段白名单筛选的目录/文件元数据。没有写死 Website Token，没有复制签名算法，没有访问或修改账号接口，没有跳过权限、密码或 Premium 限制。
- 列表取得后停止继续加载网页；日常文件滚动和行布局由 SwiftUI 完成。隐藏的 WebKit 仍有启动开销，不能宣称完全没有 WebView、已量化提升性能，或与网站将来改版永久兼容。
- 图片、PDF 和其他可支持文件在完整下载校验后使用 Quick Look 预览；视频/音频使用 AVKit 和当前 Gofile Cookie 流式播放，格式兼容性由系统决定。
- 单文件下载走独立 URLSessionDownloadTask，带当前 Gofile 范围内的 Cookie 和 User-Agent，写入磁盘，不把整个文件放入内存。
- 显示下载进度和取消；完成后用系统文档选择器“存储到文件”。临时文件在页面会话结束时清理，已导出副本保留。离开整个查看器会取消尚未完成的传输；未实现跨 App 终止的后台下载队列。
- 单文件上限 8 GiB，并检查剩余磁盘空间。原站 ZIP 接口仍是 Premium 能力，不调用该接口。新增的 Download all 使用普通可访问文件地址，在客户端逐个传输和保存目录。

## 串行批量下载（同日追加，尚未打包）

- 顶部 `arrow.down.document` 按钮启动 Download all；范围是**当前页全部条目**，不受本地搜索筛选影响。遇到子文件夹后深度优先读取，其中所有分页都会继续遍历；不会额外下载当前根目录未显示的其他分页。
- 同一时刻最多一个原生 Gofile 文件/缩略图传输任务。当前项目处理完毕后间隔 700 ms 再处理下一项。WebKit 的正常初始化仍可能发出多个资源请求，因此不能把这解释成整个 App 永远只有一个 TCP 连接，也不能承诺不会被服务端限流。
- 每个文件完整校验后移动到 `Documents/Gofile Downloads/<folder>-<batch-id>/...`，保留子目录、避开同名覆盖，批次目录不进入 iCloud 备份。Export folder 导出副本正常。1027 安装包缺少文件共享开关，Files 目录可见性修复见下文，尚未打包交付。
- 显示当前路径、单文件百分比、完成数量、跳过数量和已发现的待处理项目数。嵌套目录尚未展开时总量未知，不显示虚假的整批完成百分比。
- 暂停/继续保留已完成结果；暂停中的当前文件未实现 HTTP Range 续传，继续时会重新传输该文件。已完成文件不会重下。Stop batch 不删除已保存文件。
- 密码门槛暂停队列，输入后继续；失效、私有、Premium 限制或已标记不可用的项目跳过并记录原因。网络、磁盘或校验错误暂停在当前项目，用户可重试或跳过。
- HTTP 429、API `error-rateLimit`，以及存储节点 HTTP 503 暂停并尊重 Retry-After；缺少该字段时至少等待 60 秒。原生传输调度器也遵守这个冷却时间，避免后台排队的缩略图继续发请求。没有自动密集重试。
- 按 ID 去重并阻止文件夹循环引用；最多 10,000 个条目、32 层目录，超过后暂停并提示拆分目录。
- **队列由 App 级管理器持有**：关闭批量下载页、返回帖子、关闭整个 Gofile 查看器时继续下载；右侧统一下载悬浮按钮可重新查看视频和 Gofile 队列。切换 App 或锁屏暂停，回到 App 后点击 Continue。终止 App 后不恢复待下载队列，已落盘文件保留。未实现跨重启队列持久化或后台 URLSession 下载。

## Gofile Helper 页面调整（2026-09-29，待打包）

- 批量下载页标题改为 `Gofile Helper`，移除 `Includes every item on this page and all pages inside its subfolders.` 说明。下载范围保持不变。
- 下载器从独立 sheet 改为文件列表中的 NavigationStack 推入页面，移除下载器自建导航栈和左上角关闭按钮，使用系统返回按钮及左边缘侧滑返回。
- 返回文件列表时恢复列表缩略图，批量任务继续下载。网站验证和文件导出仍使用原有弹窗。
- 本次只修改源码并做静态检查，未构建、打包或安装。侧滑完成/取消、关闭页面后继续下载、重新打开管理页等待真机验收。

## 关闭页面继续下载与 Files 目录修复（2026-09-29，待打包）

- 用户确认仅要求 App 保持前台时继续下载，不扩展为锁屏或切换其他 App 后持续下载。
- `GofileDownloadManager.shared` 持有批次；递归目录读取的隐藏 WebView 挂在 App 根视图，不依赖下载页面存活。暂停、继续、停止和导出继续使用同一批次状态。
- 同一目录同一页再次点击 Download all 会打开已有批次，避免重复启动。下载列表可移除已完成或已停止的批次，移除只清理列表，不删除文件；移除后可重新启动这一页的下载。
- 只在 App 进入 background 时统一暂停批次；关闭页面、系统侧滑、打开导出面板不再触发暂停。暂停中的当前文件仍需重新传输，已保存文件不重下。
- 已直接读取 `ForumLite-0.3.0-1027-unsigned.ipa` 内的 Info.plist：`LSSupportsOpeningDocumentsInPlace=true`，但没有 `UIFileSharingEnabled`。这解释了 Export folder 可用，但“我的 iPhone”下没有 forum lite 文件夹。
- 增加 `native/Info.plist` 显式声明两个布尔开关，由 `native/project.yml` 指定并合并现有自动生成配置。`scripts/package_native.py` 要求最终 app 的两个开关均为 true，缺少任何一个就拒绝交付。
- 修复版本预期目录为“文件 → 浏览 → 我的 iPhone → forum lite → Gofile Downloads”。页面也读取实际包配置：没有两个开关时只提示使用 Export folder，不展示不可访问的固定路径。正常覆盖安装并保留 App 数据时，原有批次文件无需移动。
- 本轮通过 Swift 语法解析、仓库语言/凭据扫描、YAML/Plist/Python 语法检查及 diff 检查；没有执行 Swift 编译、真机测试、打包或安装。需在后续交付时验证最终 IPA 开关，并验收退出多层页面后子目录继续下载、重新打开后的状态与导出、锁屏暂停及 Files 中已有文件可见性。
- 配置依据：[Apple Files 文档访问条件](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html)；[Apple Info.plist 合并规则](https://developer.apple.com/documentation/bundleresources/managing-your-app-s-information-property-list)。

## 统一下载弹窗与说明精简（2026-09-29，待打包）

- 视频和 Gofile 使用同一个浮动入口、同一个 Downloads 弹窗，分别展示在 Videos 和 Gofile 分组；暂停全部、继续全部、清理已完成均覆盖两类任务。需要密码的 Gofile 批次仍从详情解锁；冷却中的批次不可被继续全部提前启动。
- Gofile 行显示名称、保存/跳过/待处理数量及当前文件进度，点击仍进入 Gofile Helper。任务完成只改变状态，不移动所属分组，避免详情导航因源行移除而中断。清理批次记录不删除已保存文件。
- 删除常驻的下载数量限制和操作说明；后台暂停、恢复与保存路径改在 ⓘ 弹层查看。全局悬浮入口在有运行中的 Gofile 批次时显示活动指示，不把视频的字节比例当作整批目录下载进度。
- 同步精简首页空状态、关注作者、视频播放按钮、投票卡片说明。必要的帮助统一使用 `InfoButton`（系统 `info.circle` 与 SwiftUI popover）；较长说明可滚动，错误、密码输入、限流倒计时及实际状态仍直接可见。
- Swift 语法解析、仓库检查和 diff 检查已通过；未构建、打包或安装。真机待验证混合队列、批量操作、下载完成时的详情停留、窄屏和大字体下的 ⓘ 弹层。
- 交互依据：[Apple popover](https://developer.apple.com/documentation/swiftui/view/popover(ispresented:attachmentanchor:arrowedge:content:)) 与 [紧凑布局适配](https://developer.apple.com/documentation/swiftui/view/presentationcompactadaptation(horizontal:vertical:))。

## 原生访问状态

- 已根据官方 `files/manager.js`、`files/templates.js`、`services/api.js` 区分：密码需要/密码错误、内容不存在、链接过期、非公开内容、Premium、限流和普通加载失败。
- 密码由原生 SecureField 输入，通过 `callAsyncJavaScript` 的 arguments 传给网站原有 `form[data-fm="password"]` 并调用 `requestSubmit()`。仍由网站执行 SHA-256、sessionStorage 和服务端校验；提交后清空 DOM 输入值，不把明文写入原生存储或日志。
- 数据桥只增加布尔状态、白名单错误码、HTTP 状态和 Retry-After，不转发密码值、哈希、账号 token、原始服务端错误消息或受限文件列表。
- 正常门槛直接在原生界面显示；站点改版、额外验证或账号登录仍保留 Open website 后备入口，不能宣称覆盖未来所有页面。

## 下载校验

- 仅允许 HTTPS Gofile 存储子域 `/download/web/` 文件请求；每次重定向重新筛选 Cookie，保留相同文件 ID。
- 跳回 `gofile.io/d/...` 时直接报会话/访问错误，不保存该网页。
- 要求 HTTP 200，拒绝意外的 206 部分文件；比较实际字节数与目录提供的大小。
- 检查 MIME 与响应开头，拒绝伪装成媒体/其他文件的 HTML、JSON 响应。
- 合法的小文本、空文件、原本就是 HTML/JSON 的文件不按“体积小”误杀。
- 保存使用独立临时目录并清理文件名中的路径分隔符；取消和失败不会出现成功导出。

## 验证状态

- 已完成：Chrome 测试目录读取、测试 PNG 实际下载、无 Cookie 请求的 302 → HTML 复现。
- 已完成：9 项 Node 数据桥/密码提交测试；覆盖字段白名单、请求保持不变、账号/外站/非 GET 请求排除、访问门槛、单文件目录、密码错误、过期/私有优先级、HTML 限流响应和密码表单调用/清空。
- 已完成：本地 Swift tree-sitter 语法解析、仓库语言/凭据扫描、diff 检查。这不是 Swift 编译或类型检查。
- 已补充 Swift Core 测试源码：链接路由、HTML 错误下载、文件大小、合法小文件、路径安全、目录解析、过期页、访问限制、重复条目与跨域链接；递归顺序、子目录分页、循环/别名去重、同名文件、下载范围、递归深度和原生错误分类。当前环境没有执行这些 Swift tests。
- **未执行：iPhoneOS 编译、模拟器、真机查看器验收、打包或上传。** 用户仍处于需求批次暂停打包阶段。
- 后续真机重点：Gofile 首次 guest 初始化、正确/错误密码、子目录超过 100 条的分页、串行任务暂停/继续/跳过、退后台、Files 可见性与目录导出、失效/私有/限流、视频播放和 Safari 3 KB 复现场景。

## 一手资料

- [Gofile API](https://gofile.io/api)：官方 API 的认证、目录与访问限制。
- [Gofile accountService.js](https://gofile.io/js/accounts/accountService.js)：账号初始化与父域 Cookie 同步。
- [Gofile contents.js](https://gofile.io/js/services/contents.js)：目录字段、分页与网站请求流程。
- [Gofile manager.js](https://gofile.io/js/files/manager.js)：单文件下载、访问门槛与 Premium ZIP 行为。
- [Gofile templates.js](https://gofile.io/js/files/templates.js)：密码表单及各类访问状态的原站界面。
- [Gofile api.js](https://gofile.io/js/services/api.js)：HTTP 429 与 `error-rateLimit` 的分类。
- [Gofile preview.js](https://gofile.io/js/files/preview.js)：当前媒体链接与缩略图字段。
- [Apple URLSessionDownloadTask](https://developer.apple.com/documentation/foundation/urlsessiondownloadtask)：磁盘下载及进度回调。
- [Apple Providing access to directories](https://developer.apple.com/documentation/uikit/providing-access-to-directories)：系统文件选择器及目录访问机制。

原始测试网页和下载产物未加入仓库，仓库测试使用合成数据。
