# Gofile 原生文件查看器

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
- 列表包含名称、大小、文件夹、缩略图、分页和当前页本地搜索。按可见行加载缩略图，最多并行 4 个、限制 160 px 解码大小、24 MiB / 100 项内存缓存。
- 使用独立、持久化的 WKWebsiteDataStore；不与 South、Simp 或 Safari 共享 Cookie。浏览器中的现有登录不会自动迁移，首次可使用网站正常创建的 guest 会话，需要密码/登录/验证时在 App 内网站视图完成。
- WKWebView 负责网站原有初始化和访问验证；原生端只接收经过字段白名单筛选的目录/文件元数据。没有写死 Website Token，没有复制签名算法，没有访问或修改账号接口，没有跳过权限、密码或 Premium 限制。
- 列表取得后停止继续加载网页；日常文件滚动和行布局由 SwiftUI 完成。隐藏的 WebKit 仍有启动开销，不能宣称完全没有 WebView、已量化提升性能，或与网站将来改版永久兼容。
- 图片、PDF 和其他可支持文件在完整下载校验后使用 Quick Look 预览；视频/音频使用 AVKit 和当前 Gofile Cookie 流式播放，格式兼容性由系统决定。
- 单文件下载走独立 URLSessionDownloadTask，带当前 Gofile 范围内的 Cookie 和 User-Agent，写入磁盘，不把整个文件放入内存。
- 显示下载进度和取消；完成后用系统文档选择器“存储到文件”。临时文件在页面会话结束时清理，已导出副本保留。离开整个查看器会取消尚未完成的传输；未实现跨 App 终止的后台下载队列。
- 同时最多下载 2 个文件；单文件上限 8 GiB，并检查剩余磁盘空间。原站文件夹 ZIP / 批量下载是 Premium 能力，本版仅提供单文件操作。

## 下载校验

- 仅允许 HTTPS Gofile 存储子域 `/download/web/` 文件请求；每次重定向重新筛选 Cookie，保留相同文件 ID。
- 跳回 `gofile.io/d/...` 时直接报会话/访问错误，不保存该网页。
- 要求 HTTP 200，拒绝意外的 206 部分文件；比较实际字节数与目录提供的大小。
- 检查 MIME 与响应开头，拒绝伪装成媒体/其他文件的 HTML、JSON 响应。
- 合法的小文本、空文件、原本就是 HTML/JSON 的文件不按“体积小”误杀。
- 保存使用独立临时目录并清理文件名中的路径分隔符；取消和失败不会出现成功导出。

## 验证状态

- 已完成：Chrome 测试目录读取、测试 PNG 实际下载、无 Cookie 请求的 302 → HTML 复现。
- 已完成：Node 数据桥测试；覆盖字段白名单、请求保持不变、账号/外站/非 GET 请求排除、访问门槛、单文件目录。
- 已完成：本地 Swift tree-sitter 语法解析、仓库语言/凭据扫描、diff 检查。这不是 Swift 编译或类型检查。
- 已补充 Swift Core 测试源码：链接路由、HTML 错误下载、文件大小、合法小文件、路径安全、目录解析、过期页、访问限制、重复条目与跨域链接。当前环境没有执行这些 Swift tests。
- **未执行：iPhoneOS 编译、模拟器、真机查看器验收、打包或上传。** 用户仍处于需求批次暂停打包阶段。
- 后续真机重点：Gofile 首次 guest 初始化、带密码目录、翻页/子目录、横竖屏和返回、超过一个下载并行、Photos 以外的 Files 导出、视频播放、Safari 3 KB 复现场景。

## 一手资料

- [Gofile API](https://gofile.io/api)：官方 API 的认证、目录与访问限制。
- [Gofile accountService.js](https://gofile.io/js/accounts/accountService.js)：账号初始化与父域 Cookie 同步。
- [Gofile contents.js](https://gofile.io/js/services/contents.js)：目录字段、分页与网站请求流程。
- [Gofile manager.js](https://gofile.io/js/files/manager.js)：单文件下载、访问门槛与 Premium ZIP 行为。
- [Gofile preview.js](https://gofile.io/js/files/preview.js)：当前媒体链接与缩略图字段。
- [Apple URLSessionDownloadTask](https://developer.apple.com/documentation/foundation/urlsessiondownloadtask)：磁盘下载及进度回调。

原始测试网页和下载产物未加入仓库，仓库测试使用合成数据。
