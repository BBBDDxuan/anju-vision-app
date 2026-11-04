# B/C App 装配与 APK 构建（2026-11-04）

构建版本：1.2.2+4007；本地分支 `codex/b-c-integration-build`。C 原始构建号为 7，但已发布 1.2.1 的构建号为 4006，所以本次递增到 4007，避免升级时被 Android 判定为降级。

App 基于 C 分支 `778a2b7b07907d1bafcb4162264bb41e519bd294`，该提交已经包含 B 发布文件。对应后端已拉取到独立工作区，提交 `3fde57e33ffcfca5ca9c19bd27c7e0a8c4888719`。两边 main 和旧版交付文件未改动；本次不修改网页或后端源码。

## 本次补齐的公共入口

- `mobile-app/lib/main.dart`：向 Firebase gateway 提供当前已配置连接的规范化 scope。
- `mobile-app/lib/app_controller.dart`：统一后端不再跳过 C 推送登记；切换连接先等待旧登记注销，失败保留旧设置。原生和 FCM 冷启动点击先排队，初始化后从统一告警详情读取真实 source，再进入 B 的详情路由。
- `mobile-app/lib/app.dart`：初始化唯一 Android 通知回调，订阅 B 已有的完整快照；不增加第二条轮询。接入 C 去重与通知，显示前台提示并支持点击查看。
- `mobile-app/lib/services/app_notification_binding.dart`：串行转发快照，按后端/家庭复用 C gate。C 持久化完成后、真正显示之前再次检查当前连接、前台状态与提醒开关，避免切换期间弹出原连接告警。
- `mobile-app/test/notification_integration_test.dart`：覆盖历史静默、重启去重、异步期间切换后端/关闭通知、统一后端登记及注销失败、原生/FCM 冷启动路由。
- `mobile-app/assets/manual.json`：更新内置离线手册至 1.2.2，说明已装配流程和未启用 Firebase 的边界。

C 的通知库、原生 Android/RTSP、Firebase bootstrap、依赖锁与构建脚本保持原样；pubspec 仅调整版本构建号，依赖声明不变。C 原有 `check-c-scope.mjs` 验证的是“C 不改 B 的发布文件”，不适合 B 装配阶段；因此不修改它，改用本目录的 `check-boundaries.mjs` 验证本次编辑范围、C 代码和依赖不变。

## 复现构建

在具备 Flutter 3.47.8 / Dart 3.13.7、JDK 17、Android SDK API 36 的环境中，以英文路径访问 mobile-app（本机使用 junction），配置好私有原签名 `android/key.properties`。该文件和私钥不进入 Git 或公开交付。

```powershell
flutter pub get --enforce-lockfile
node tool/source_check.mjs
node tool/check-c-config.mjs
node "完整仓库路径/docs/b-c-integration/check-boundaries.mjs"
flutter analyze --no-fatal-infos
flutter test --no-pub
./tool/build-c.ps1 -Release -SkipChecks -ExpectedSigningSha256 2472d43f63dbea0d2d3c34933114caf3dc532055c97ceaa40e96a968070b3e35
```

`-SkipChecks` 仅跳过构建脚本内针对 C 开发阶段的重复验证；上面的有效检查需先实际通过。构建脚本仍执行锁定依赖恢复、正式编译、原签名验证和产物哈希记录。

## 能力与后续配置

本次普通 Release 使用 `USE_FIREBASE=false`。本机未提供 `google-services.json`，所以不宣称具备后台/锁屏推送。前台轮询、告警列表、本地通知和点击详情可使用；系统通知需要用户授予通知权限。手机端不内置视频识别模型，分析使用已配置的统一后端，局域网摄像头 RTSP 直连预览仍由手机解码。

启用后台推送需要同一 Firebase 项目的 Android 客户端配置、服务端账号和 C 插件环境变量，然后用 `-WithFirebase` 重新构建；按后端的 `docs/c-notifications/A_INTEGRATION.md` 接入。还需两部真机测试后台、锁屏、主要/备用联系人、通知点击与升级。模拟器和单元测试不替代真机送达验收。

首次启动进入“我的 → 连接服务”，真机填写 `http://电脑局域网IP:8000` 和 `APP_LAN_TOKEN`；本机模拟器使用 `http://10.0.2.2:8000`。8010 是内部服务。录像安全分析、物品寻迹和问答需要后端模型就绪；本次未调用付费模型或真实摄像头。

已知后端限制：部分需要转码的视频在 FFmpeg 9 上可能遇到 A 原有的 `-vsync` 参数兼容问题；本次未修改后端。H.264 合成视频只用于隔离 HTTP 合约验证，不代表危险识别准确率验收。

实际测试和安装包信息见本目录最终的 `RESULTS.json`。
