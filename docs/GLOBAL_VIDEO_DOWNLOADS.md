# 全局视频下载管理器

最新交付：[build 1028](BUILD_1028.md) 已完成 179 项 Swift 测试、iPhoneOS 编译和打包，包含下述统一下载弹窗与说明精简改动。未安装，真机验收待用户测试；下文“待打包”为开发时记录。

后续交付：用户解除打包暂停后，本功能已包含在 [build 1027](BUILD_1027.md)，云端检查与 iPhoneOS 编译通过；实际下载、续传和后台生命周期仍待真机验收。

## 本次范围

2026-09-29：用户要求退出视频播放页后继续下载，右侧中部提供液态玻璃入口、弹窗管理多个下载，并支持断点续传。源码已实现；沿用用户暂停打包要求，不上传、不构建 IPA、不跑模拟器。本文不代表真机验收结果。

原来的 `VideoDownload.active` 已经让最多两个视频下载在返回时继续，但没有全局入口、排队、暂停/续传和跨启动任务记录。现在由 `VideoDownloadManager` 持有任务，播放器只观察任务，不拥有其生命周期。

## 交互

- 有下载记录时，主 NavigationStack 右侧中部出现原生 SwiftUI `.buttonStyle(.glass)` 圆形按钮。所有主导航页面（含视频/图片 push 页面）共享同一个入口。系统弹窗和其他 modal 出现在它上方，不额外创建抢占焦点的 UIWindow。
- 圆环显示当前实际传输任务的字节加权进度，数字平滑变化；未知长度/准备阶段显示 spinner，不制造百分比。角标展示未完成数量，遵守 Reduce Motion。加入/结束任务后，参与统计的任务集合会改变，圆环不是固定批次的总进度。
- 点击弹出原生 sheet，逐项显示 Video、开始时间、状态、已下载/总字节数和百分比，支持暂停、继续、失败重试、取消、清理已结束记录；导入失败的本地文件可通过 Save to Files 导出。
- 默认同时处理两个视频；更多任务等待，不再因为已有两个任务直接拒绝新下载。保存到 Photos 也占用一个任务位置，限制同时导入的压力。
- 播放页顶部下载按钮在有任务时可打开管理器；失败后重新打开视频取得新地址，再次点击下载会使用新的来源。非 Turbo 网页播放回退不受该队列接管。
- 视频和 Gofile 共用一个下载弹窗和浮动入口，各自保留原有下载引擎与并发策略。详情见下方同日追加说明。

## 统一下载弹窗（2026-09-29，待打包）

- `DownloadsView` 同时观察视频与 Gofile 管理器，展示 Videos / Gofile 两组任务，支持统一暂停、继续及清理已结束记录。两类任务都有运行状态与进度变化通知。
- 移除“Up to two videos…”等常驻说明，必要的生命周期与保存位置说明改为工具栏 ⓘ 弹层。暂停视频的长篇断点说明收进该行 ⓘ，失败原因仍直接显示。
- 悬浮入口合并两类任务的活动数和未完成数；有 Gofile 目录批次正在运行时显示活动指示，避免展示不完整的汇总百分比。没有活动 Gofile 批次时仍显示视频原有字节加权进度。
- App 前后台、视频断点保存、Photos 导入和 Gofile Files 保存逻辑保持各自原有行为。手动暂停的视频不会因为本次 UI 合并而自动恢复。
- 本次只做源码和静态检查，未构建、打包或安装。混合队列展示、批量控制、原生弹层和导航仍需后续真机验收。

## 断点与完整性

- 暂停调用 `URLSessionDownloadTask.cancel(byProducingResumeData:)`；网络失败从 `NSURLSessionDownloadTaskResumeData` 读取系统提供的数据；继续使用 `downloadTask(withResumeData:)`。不自行修改 opaque resumeData，也不把新签名 URL 拼进旧断点。
- `resumeData` 是否可用取决于服务器 Range、ETag/Last-Modified、资源是否变化，以及系统是否保留临时文件。无断点时明确提示继续将从头下载当前文件；Apple 也可能根据资源变化自动重新开始。不能承诺每个 provider 都能续传。
- 已暂停/失败任务及断点写入私有 Application Support/VideoDownloads，启用 iOS Data Protection、原子写入并排除备份。Cookie、签名地址和 resumeData 不暴露到 Files 目录、日志或仓库。
- App 再次启动时恢复任务列表为暂停态，由用户继续；照片导入中断而本地文件仍存在时，允许继续导入，不自动重下文件。
- 原有 4 GiB 视频限制、独立 Cookie、重定向重新筛选 Cookie、HTTPS 校验、本地视频轨道检查和 Photos 完成回调保留。视频请求不新增原先没有的论坛 Referer。
- HTTP 206 只有在续传上下文中、Content-Range 合法且覆盖到文件末尾、最终落盘字节数等于完整总长度时接受。普通下载意外收到 206 仍拒绝。HTTP 200 重新开始的响应也必须满足完整长度要求。
- Turbo 下载签名失效后可重新解析，但新地址会重新下载该文件；非 Turbo 地址失效时提示重新打开播放器取得来源。已完成的其他任务不受影响。
- 成功仅指 Photos 明确返回导入成功；导入失败的文件保留供 Files 导出。清理下载记录不删除相册中的视频。
- HLS 离线封装、DRM 和只有 WebView 能播放但无可用 HTTPS 文件来源的情况仍未新增支持。

## 生命周期

- **退出播放器、返回论坛或切换论坛页面：继续下载。**
- **进入后台/锁屏：申请有限的系统时间保存断点并暂停，回到前台继续此前自动暂停的任务。** 手动暂停的任务不会自动继续。
- **强制结束/系统终止后：下次启动恢复已持久化的任务和断点；未产生断点或被清理的临时文件只能重新下载。**
- 本次没有切换成 background URLSession。Apple 的后台 session 自动跟随重定向，不调用目前用于逐跳筛选 Cookie 的 delegate；后台持续下载是另外的生命周期与请求策略改造，不能把当前前台队列宣称为杀进程后继续传输。

## 验证

- Swift tree-sitter 语法解析、仓库语言/凭据检查、diff 检查。语法解析不是 Swift 编译或类型检查。
- 增补 Swift Core 回归用例：完整续传 206、只有剩余片段、未发生续传的 206、伪造 Content-Range、HTML 响应、服务器返回 200 重新开始时的长度校验。Windows 环境未执行这些 Swift tests，待用户允许构建后由既有 CI 执行。
- 尚未完成：iPhoneOS 编译、实际暂停/恢复请求、跨 App 启动恢复、后台保存断点时限、Photos、多任务及液态玻璃真机效果验收。
- 真机重点：同时发起三个视频并返回论坛；暂停其中一个让后续排队任务开始；续传观察已下载量；断网再重试；锁屏/回前台；手动暂停后切前后台；恢复下载失败/过期地址；导入失败转 Files；清理记录后照片保留。

## 官方依据

- [Apple: Pausing and resuming downloads](https://developer.apple.com/documentation/foundation/pausing-and-resuming-downloads)：暂停、网络失败、resumeData 与继续请求。
- [Apple: cancel(byProducingResumeData:)](https://developer.apple.com/documentation/foundation/urlsessiondownloadtask/cancel(byproducingresumedata:))：Range、资源校验及临时文件前提。
- [Apple: Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)：后台生命周期和自动跟随重定向的限制。
- [Apple: GlassButtonStyle](https://developer.apple.com/documentation/swiftui/glassbuttonstyle)：原生 Liquid Glass 按钮样式。
