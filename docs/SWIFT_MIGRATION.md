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

`simp lite` 的首个纯原生 Swift IPA 已完成。旧 Flutter 源码暂留作功能对照和回退依据；原生构建不引用旧界面或启动 Flutter engine。

显示名称改为 `simp lite`，图标沿用上半部分 SIMP，下半部分改为 LITE。

## Verified build

- Version: `0.2.0 (1003)`.
- Source: `a76f80b75f36c796b80c4fb16e5e11a0a0507f2b`.
- [macOS CI](https://github.com/SyIar/clear-forum-flutter/actions/runs/36425771541): success.
- 7 Swift core tests, media probe checks, media support checks and iPhone arm64 compilation passed.
- Downloaded IPA SHA-256: `1635a00f7b8d2b15bb5c2e9620b52a3089d74a4a99e7e2e9b61164cd68bc441c`.
- Local package: `D:\workspace\sideloadly-setup\SimpLite-0.2.0-1003-unsigned.ipa`.
- Package verified: `CFBundleDisplayName=simp lite`, original bundle identifier, compiled AppIcon assets, MediaProbe.js present, no Flutter.framework/App.framework/flutter_assets, intact ZIP.
- 尚未安装这版原生 IPA；保留的数据、登录会话、滚动和两类播放器需要真机升级验收。之前 Flutter 版本的验收不等同于此版本验收。
