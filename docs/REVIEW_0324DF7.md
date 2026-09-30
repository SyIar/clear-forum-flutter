# Review：0324df7

日期：2026-09-30。分支：`fix/forumlite-eighteen-issues`。范围：相对 `f1316ed` 的全部 42 个文件，以及本次替换的 AppIcon 资源。

后续交付已完成：修复合入 `main`，build 1032 的 234 个 Swift 测试、device Release 编译和 IPA 校验通过，安装包已下载。源码提交为 `f32d6eb6986ba0f4c1d1ce6da76acdf2b8cb68bf`，详见 [构建交付记录](BUILD_1032.md)。

## 结论

初次源码审查发现 2 个 P2 问题，并完成 icon 替换。用户随后要求修复、合入和打包，下面两项均已修复，保留原审查说明作为记录。未发现可确认的 P0/P1 问题；初审时的验证范围记录在文末，后续构建结果单独记录。

修复说明：

- 浏览器通过 `browserRedirectDestination` 仅处理本站 `/redirect/` wrapper；普通 unread、post 和带 fragment 的链接保留原 request。阅读器自身的 URL 规范化不变。
- `SavedPage.titleIsCustom` 随书签持久化。新建书签有手填标题时不再自动覆盖，自动标题和 recent reading 仍跟随站点更新。旧数据无法区分手填和自动标题，因此保留已有非占位名称，仅空名称、路径和完整 URL 占位符继续自动更新。
- 增加 Swift 回归用例，覆盖普通 unread 导航、Gofile wrapper、两个论坛的标题持久化/刷新和旧数据迁移。
- `ios-validate.yml` 改用 `iphoneos` device SDK；打包走 `ios-native.yml`，不运行模拟器。

### P2：Site browser 会把普通 unread 链接改成帖子首页

位置：`native/App/ForumBrowser.swift:122-126`，以及同文件 `createWebViewWith` 中的相同处理。

新增分支对所有 `.linkActivated` 调用 `SimpSitePolicy.linkDestination`，只要返回 URL 不同就取消原导航。该函数内部调用已有的 `resolve`；`resolve` 会将普通 `/threads/example.123/unread`（也包含 `?new=1` 形式）规范化为 `/threads/example.123/`。因此，在 Site browser 中点击网站正常的“未读”入口，也会被直接送回第一页，网站原本定位第一个未读楼层的机会被取消。旧版本直接加载原始 navigation request，没有这次改写。

建议：浏览器只对实际识别到的 `/redirect/` Base64 wrapper 执行解包；普通站内链接保留原始 request。阅读器的 URL 规范化与网站浏览器导航应区分用途。验证普通 unread 链接仍交给网站，同时 wrapper 链接仍能直接打开 Gofile。

### P2：手填书签标题保存后会被覆盖

位置：`native/App/ForumLiteApp.swift` 的 `BookmarkEditor` 保存动作与 `resolveBookmarkTitle`；`native/Core/ReadingLibrary.swift` 的 `synchronizeTitle`。

`BookmarkEditor` 仍提供 `Title (optional)`，先按用户输入保存，随后无条件启动 `resolveBookmarkTitle`。页面请求成功后，`synchronizeTitle` 将所有匹配书签的标题直接覆盖成站点标题；后续 `capturePresentation` 同样没有区分自定义标题与自动标题。因此，填写自定义名称、点击 Save、等待请求结束，就会丢失刚才输入的名称。分支甚至把原有 `My title` 保留断言改为了站点标题，这证明覆盖是实现行为，但界面仍承诺用户可以输入标题。

建议：若保留自定义标题能力，应区分自定义标题与自动标题，仅同步后者；若本次产品规则改为始终使用站点标题，应同时移除这个输入框，避免让用户填写注定被覆盖的内容。

## 已完成的 icon 修改

- master：`assets/branding/app-icon.png`，与用户提供的 `forumlite-twelve-point-icon-1024.png` 文件字节完全一致。
- SHA-256：`48e32605159a6f4e4840e350d9feb5369c9209ee2fe42523ae857cb1c4fce0f7`。
- master 为 1024 × 1024 RGB，无透明通道；未重绘、未裁切、未添加圆角。
- 运行仓库已有 `scripts/generate_icons.py`，更新 19 个 iOS catalog slots 对应的 15 个 PNG，以及 5 个现有 web PNG。逐项校验了像素尺寸、RGB 模式和与 master 缩放结果的一致性；1024 marketing icon 像素与源图完全一致。
- 修正 `docs/BRANDING.md` 的来源说明。原提交虽然声明已换十二角星，但实际 master 仍是 1254 × 1254 的旧图，原提交也没有包含图标文件变更。
- display name、bundle identifier 和论坛首页 logo 均未因本次 icon 导入改变。

## 初审时的验证范围

已执行并通过：

- `scripts/check_swift_syntax.py`：解析 91 个 Swift 文件；仅语法检查，不是编译或类型检查。
- `scripts/check_media_probe.mjs`：媒体候选观察、Cyberdrop 有界自动播放、手动暂停和 native handoff 检查。
- `scripts/gofile_bridge.test.mjs`：9 个用例全部通过。
- `scripts/check_repository.py`：仓库语言和凭据模式检查。
- icon 文件一致性、尺寸、RGB 和像素校验，以及 `git diff --check`。

未执行：Swift XCTest、Xcode 编译、模拟器、真机 UI/手势验收和 IPA 打包。查询该分支的 GitHub Actions 未返回运行记录。本机没有可用 Swift/Xcode toolchain。

新增的 `ios-validate.yml` 包含 simulator 编译，与用户“不做模拟器校验”的要求不一致，本次没有触发。需要 CI 验证时应使用 device SDK 的编译流程。图片 drawer、Quick Look 返回手势、连续翻页锚点和 Cyberdrop 首播仍需真机确认，不能用 JS/语法检查代替。
