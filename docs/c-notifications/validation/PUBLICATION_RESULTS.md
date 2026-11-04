# C 上传前验证（2026-11-04）

App 基线 e85049da4ec702c74d84d2a46473dcf813985b78；B 文件来源 796c7658b228aa1b650f23140b622dca52f8d857；website 基线 d272b8737ddd59a33e66b79ef120e60bf6d2be6b。候选版本 1.2.2+7。

| 检查 | 实际结果 | 证据和边界 |
| --- | --- | --- |
| Flutter 全量测试（导入 B 后） | 82 passed，4 skipped，退出码 0 | flutter-tests-publication.txt；4 项需隔离 HTTP/合成视频夹具，未启用 |
| Flutter analyze --no-fatal-infos | 退出码 0；2 条弃用 info | flutter-analysis-publication.txt；Firebase onTokenRefresh/getToken，未盲目更换 token 协议 |
| 纯 Dart 通知核心 | 37 场景通过 | dart-core-publication.txt |
| ABC 范围与来源哈希 | 52 个非 C 文件通过，其中 B 25 文件均与其发布 SHA256 一致 | node mobile-app/tool/check-c-scope.mjs |
| 源码与 Android 配置静态检查 | 均通过 | source_check.mjs / check-c-config.mjs；不等于 Kotlin 编译 |
| PowerShell 脚本语法 | 均通过 | PowerShell Parser::ParseFile |
| website A/C 后端 | 59 passed，1 Starlette 弃用警告 | website docs/c-notifications/validation/backend-junit.xml，已在新布局复跑 |
| 当前构建条件 | Flutter 可用，Android SDK/JDK、Firebase 配置、正式签名缺失 | preflight-publication.json |
| APK、两手机前后台/锁屏 | 未执行 | 见 DEVICE_ACCEPTANCE.md |

4 个跳过项目：旧录像 API 测试、原安全后端证据/确认测试，以及 B 的统一手机 API 和合成视频上传测试。它们只允许访问隔离夹具；本次未启动这些服务，不能称其通过。B 自己的独立验证见其发布分支。

B 的业务入口虽已导入，但 C 通知 snapshot、currentScope 和 scoped 点击尚需 B 在其独占入口装配；禁止把本次独立组件测试视作已接通通知。FFmpeg 9 非 H.264 转码兼容问题仍由 A 处理。

暂存区检查确认 25 个 B 文件与发布清单原始字节完全相同；新增文件不含 ZIP/APK/敏感配置。原始工具日志和 B 补丁保留空白，不为格式检查篡改证据；源码差异检查将 CR 识别为行尾并排除这两类原始材料。

本次仅上传源码和必要验证材料，不新增源码 ZIP、不启动 APK 构建、不修改已有 APK。
