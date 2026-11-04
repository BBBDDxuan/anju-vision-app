# C 历史验证记录：导入 B 前（2026-11-04）

当前上传基线请看 PUBLICATION_RESULTS.md；以下记录保留当时验证范围，不代表 B 合并后的结果。

基线：A 32d4c60e41e1da6853a6328484cbb88c1375b16a；分支 codex/c-notifications-release；候选 1.2.2+7。

| 检查 | 本机实际结果 | 证据/界限 |
|---|---|---|
| A/C 后端离线回归 | 59 passed，1 个 Starlette 弃用警告 | backend-junit.xml；包含真实 A 路由/outbox、双合成安装、ack、部分失败重试及 OAuth 离线签名；不是设备送达 |
| 纯 Dart 通知核心 | 37 场景通过 | dart-core.txt；含历史/重复/重启/权限关闭/后台回执/错误 scope/ID/取消/存储失败 |
| 纯 Dart 核心分析 | No issues found | dart-core-analysis.txt |
| 锁定 Flutter 依赖恢复 | 成功 | flutter-pub.txt；没有升级依赖 |
| 完整 Flutter 分析 | 退出码 0，2 条 info | flutter-analysis-final.txt；现有 onTokenRefresh/getToken 弃用提示，无 error/warning |
| Flutter 全量测试 | 66 passed，2 skipped，退出码 0 | flutter-tests-final.txt；2 项旧版在线夹具测试未启动，按原条件跳过；含 9 项 C Flutter 测试 |
| ABC 修改边界 | 47 个非 C 原始文件逐字节保留 | check-c-scope.mjs；导入来源 ZIP 哈希见 baseline.json |
| 原 RTSP 播放器 | RtspView.kt 与原包哈希相同 | 未改 VideoLAN 实现，原生通知注册中保留 RtspViewFactory |
| Android 通知配置 | 静态检查通过，未编译 Kotlin | check-c-config.mjs；权限/渠道/图标/冷热启动协议 |
| PowerShell 脚本 | 13 个脚本语法通过；英文路径脚本实际复用映射成功 | powershell-syntax.txt；语法检查不等于 APK 构建 |
| 新 APK/原签名升级 | 构建预检实际停止，尚无 APK | apk-preflight.txt：缺 Android SDK build-tools；JDK/原签名也未准备，旧 APK 未覆盖 |
| Firebase 真实服务 | 未配置/未发送 | 客户端 JSON、真实服务账号缺失；google-auth 已在 G 盘安装，仅临时合成密钥验证 |
| B 公共入口接线 | 未做，属于 B 文件 | B_INTEGRATION.md；不把独立组件冒充已集成 App |
| 两部手机、后台、锁屏 | 全部未执行 | DEVICE_ACCEPTANCE.md |

## 已定位的环境问题

- 初次 A 回归在中文临时目录因 OpenCV imwrite 失败，10 项夹具失败；使用英文临时路径复跑通过，没有改 A 文件。
- 沙箱的 Windows TLS 凭据错误影响依赖下载；获准在沙箱外恢复成功，缓存/依赖在 G 盘。
- 中文路径 Flutter analyze 的 LSP 初始化 JSON 截断；同 SDK dart analyze 可执行，英文 X/Y 路径 Flutter analyze 也成功。
- 中文路径 impellerc 找不到 include；英文工具/源码路径避免该编译错误。清理本 App 生成缓存并在英文映射下重建后，shader 资源恢复，全量测试通过。
- Flutter 源码 SDK 的 Unblock-File 对 Zone.Identifier 输出警告；它未阻止已成功的分析/依赖恢复，不能据此忽略其他错误。

X: 映射 C 工具目录，Y: 映射 App 仓库根目录。tool/ascii-env.ps1 可验证/重建临时映射；映射不会把文件搬到其他盘。

本次不使用真实摄像头/视频、计费模型、真实推送或生产后端，不公开凭据，不推送 GitHub/发布 Release。Provider 接受、Android 显示、用户 ack 是不同状态。

全量测试期间发现并修复 C 测试的 package/relative 混用导致 Dart 库类型重复；只统一 C 测试导入，没有修改 B 源码。最终复跑 66 通过。分析中两条弃用 info 保留兼容旧 FCM token 路径；新版 FID API 不能未经提供商目标契约验证直接替换为 HTTP v1 token。
