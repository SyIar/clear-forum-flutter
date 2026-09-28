# 实现与验收

## 当前实现

首期为纯净阅读器，采用 Cookie 会话、页面 HTML 解析、Flutter 原生阅读界面。登录和网页验证使用可见的 WKWebView。浏览器正常显示目标页面后，用户可以点击 Read page 将当前页面转成原生阅读界面。

Cookie 留在 App 的 WKWebsiteDataStore，原生 URLSession 仅向固定站点的读取路径发送匹配的 Cookie。重定向逐跳验证，未知路径和跨域重定向不会继续携带会话请求。HTML 不落盘、不上传，Flutter 不获得 Cookie 值。外部图片点击后才请求，不附带论坛 Cookie。

HTTP 与 WebView 是不同的请求环境，HTTP 读取可能遇到独立验证。Read page 是可见网页的手动阅读模式，不绕过验证，也不代表随后所有 HTTP 分页请求都会成功。

## 功能边界

- 原生支持分类、主题列表、单行置顶、帖子楼层、分页、引用、Spoiler 和基本文本格式。
- 首期不原生实现写操作、私信、搜索表单、视频播放器、后台推送和批量下载。
- App 使用英文控件文案和系统字体；来源内容按原文呈现。
- 去广告采用内容区域提取和已知广告容器过滤，不能保证识别正文中的所有推广。
- WebView 基础过滤仅覆盖已核实的广告来源与容器；正常登录与验证码仍由用户操作。
- 示例数据明确标为 SAMPLE CONTENT，不代表真实登录成功。

## 验证状态

开发中。完成检查后记录本地与 CI 结果，不提前声称 iPhone 接入成功。

## iPhone 验收

1. 安装后选择 Open forum；可阅读公开页面，受限页面提示登录或打开浏览器。
2. Sign in 打开网站，由用户本人完成登录和任何验证码。
3. 登录后点击 Done，检查原生列表；若 HTTP 仍提示验证，在浏览器打开目标页面后点击 Read page。
4. 检查普通帖子分页、引用、Spoiler 和单行置顶；验证广告容器不出现在原生界面。
5. 冷启动后验证会话恢复。点击 Clear session 后应移除 App 自己的浏览器数据并关闭已打开阅读页面。
6. 记录哪些路径只支持浏览器手动读取，以及哪些外部资源无法直接加载。

## 资料

- [Flutter iOS deployment](https://docs.flutter.dev/deployment/ios)
- [WKHTTPCookieStore](https://developer.apple.com/documentation/webkit/wkhttpcookiestore)
- [WKContentRuleList](https://developer.apple.com/documentation/webkit/wkcontentrulelist)
- [Cloudflare supported browsers](https://developers.cloudflare.com/cloudflare-challenges/reference/supported-browsers/)

更完整的前期调研保存在工作区独立的 simpcity-client-research/RESEARCH.md，不包含用户会话和个人浏览内容。
