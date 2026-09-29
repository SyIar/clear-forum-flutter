# forum lite：合并交付记录

后续版本 `0.3.0 (1015)` 已将分段选择器换成独立论坛入口，并修复浏览器/阅读器的 User-Agent 衔接；详见 [新首页与登录修复交付](ENTRY_AND_LOGIN_HANDOFF.md)。以下保留初次合并记录。

## 目标与安装身份

- 一个原生 SwiftUI/UIKit App，首页通过 `SimpCity / South Plus` 分段选择器切换论坛。
- display name：`forum lite`，target/scheme：`ForumLite`，version：`0.3.0`。
- bundle identifier 保留 `dev.sylar.clearforum`，将其作为 simp lite 升级版。不要另建第三个安装身份。
- 签名安装时沿用原 simp lite 的 Apple 账号、team 与 bundle 设置，才能覆盖同一安装身份并保留沙箱；不能只凭显示名称判断覆盖成功。不要先卸载 simp lite。
- 新图标为原创蓝色渐变白色 F，源码在 `scripts/render_forum_icon.py`。SimpCity 站点 banner 仍保留在其首页卡片内。

合并不自动删除独立 south lite，不会自行改动 Sideloadly 的续签队列，也不能直接读取另一个 App 的沙箱。South 首次进入可能需要重新登录，原独立 South 收藏需重新添加。合并解决后续一个 App 访问两个论坛的需求，不承诺即时重置 Apple 已分配的 App ID 配额。

## 实现

- `ForumSite` 描述两个固定 HTTPS origin、起始页、登录页与读取白名单。
- `SimpForumParser` 保留原 XenForo 解析逻辑；`SouthForumParser` 与 `SouthBodyParser` 处理旧版论坛 HTML 和 GBK/GB18030 编码；`ForumParser` 根据 URL origin 分发。
- `ForumSession` 每个站点一个实例，Simp 继续使用原 `WKWebsiteDataStore.default()`，South 使用固定 UUID 的持久化 WebKit profile。读取、重定向、Cookie 过滤和站内导航都受当前 session 的 origin 限制。
- `LibraryDocument` 分别保存。Simp 继续使用 `reading_library_v1`，兼容没有 `site` 字段的旧 JSON 与 `flutter.reading_library_v1`；South 使用 `south_reading_library_v1`。相同数字 thread ID 不共享读到楼层、Updated 状态、缩略图或 tag。
- 每个站点各自拥有页面缓存、图片缓存和请求生命周期；首页切换不会清除它们。保留现有的缓存容量限制和内存警告释放逻辑。清理登录状态只影响当前站点。
- 共用已验收的图片查看、交互式返回、原生分页栏、视频控制器及 provider 流程。外部媒体使用隔离的临时 WebKit/URLSession，论坛 Cookie 不交给媒体；初始 Referer 根据当前论坛传入。
- 首页记住最近选择的论坛，各自展示 Bookmarks、Recent reading 和刷新状态。

## 参考与取舍

Apple 的 [WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore) 支持默认、临时与带 identifier 的持久化存储。这里为 South 使用独立 profile，同时保留 Simp 默认 profile；这是兼顾隔离与旧登录迁移的实现选择。

[Sideloadly 官方说明](https://sideloadly.io/) 提供 bundle ID 修改与自动续签能力。此项目保留旧 bundle 的目的是让合并版成为现有 App 的更新；最终安装身份仍由实际签名选项决定。CI 仅生成 unsigned IPA，不使用 Apple 凭据。

## 验证范围

本地执行仓库语言与凭据扫描、Swift tree-sitter 语法解析、媒体 JavaScript 检查和差异检查。语法解析不是 Swift 编译。真正的 Swift tests、媒体 URLProtocol 检查和 arm64 iPhoneOS Release 编译交给 GitHub Actions macOS runner；不运行模拟器或 Gradle。

回归覆盖旧 Simp JSON/Flutter key 迁移、同 thread ID 的两个独立 library、Cookie/URL origin 隔离、跨论坛链接拒绝、分页 cache key、South 编码及已有 Simp/South 解析 fixtures。媒体检查仅使用合成响应，不访问真实 provider。

**South 真实页面兼容性仍待真机验证。** 之前工具的站点安全策略阻止了 South 页面访问，未通过其他浏览器、HTTP、代理或 CI 绕行；South 解析器依据兼容性实现和合成 fixtures，不能把构建通过写成真实论坛验收通过。

## 真机验收

1. 使用原 simp lite 签名身份覆盖安装，确认名称为 forum lite，旧 Simp 收藏、最近阅读、已读楼层与登录仍在。
2. 首页切换 South Plus，登录后验证论坛列表、帖子、分页、图片与视频；再切回 Simp，确认各自记录独立。
3. 进入视频/图片并侧滑返回，确认阅读位置和已加载图片保持；手动刷新只刷新当前论坛。
4. 只有确认合并版正常后，才考虑处理旧 South App 与其续签登记；本次不自动卸载或改续签配置。

## 构建状态

- 已完成 `forum lite 0.3.0 (1013)`，source commit：`8b9ee598a21325cd436bccecc34472e19eb720a9`。
- [GitHub Actions run 36526054353](https://github.com/SyIar/clear-forum-flutter/actions/runs/36526054353) 成功：45 个 Swift tests、媒体 JavaScript 检查、合成 URLProtocol 检查和 arm64 iPhoneOS Release 编译均通过。
- unsigned IPA：`D:\workspace\sideloadly-setup\ForumLite-0.3.0-1013-unsigned.ipa`，2,379,936 bytes。
- SHA-256：`ea4020707c79ef49c970f970d489da3410ebd6fdb89b1698827581065d3e957b`。
- 下载后已校验 ZIP CRC、CI/source commit、Info.plist 的 display name/version/build/bundle ID、arm64 Mach-O、图标、媒体脚本和依赖许可资源，以及 SHA-256；制品无 Flutter runtime。
- 本轮完成上传、构建与制品交付，尚未签名安装，未运行模拟器。真机切换、登录和覆盖保留数据仍需验收；South 的真实 DOM 兼容性限制保持不变。
