# Native Swift migration

用户已确认仅支持 iOS，将两个客户端迁移到 Swift 原生实现。

## Scope and acceptance

- 新的发布 target 不链接 Flutter.framework、App.framework 或 Dart runtime。
- SwiftUI 负责导航、首页、收藏、历史和阅读界面；UIKit / WebKit / AVKit 保留已验收的会话和播放行为。
- 保留 bundle identifier、图标、本地收藏 JSON 格式和 WKWebsiteDataStore，兼容原位升级。
- 保留分页、楼层锚点、折叠内容、图片加载/缩放、紧凑链接、视频缩略图、Turbo 与普通 embed 两条播放路径。
- Swift 单测验证解析、URL policy、历史去重和迁移；macOS CI 编译并检查 IPA 不含 Flutter。
- 真机外观、滚动和已有会话升级仍需安装验收；构建成功不等于真机验收。

## Execution

迁移中。旧 Flutter 源码暂留作功能对照和回退依据；原生构建不能引用旧界面或启动 Flutter engine。

先完成 simpcity ultimate，再完成 Tieba Lite 的协议、账户、数据及界面迁移。
