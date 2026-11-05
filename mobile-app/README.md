# 安居视界当前 App 源码

当前维护 `main`，版本以 `pubspec.yaml` 为准。本目录 `lib/`、`android/`、`assets/`、`test/` 是当前唯一构建源码。

从仓库根目录运行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1`，完成锁定依赖恢复、源码检查、Dart 分析、Flutter 测试、APK 构建及原签名验证。详见 [仓库入口](../README.md) 与 [开发说明](../docs/DEVELOPMENT.md)。

原 `tool/build-c.ps1`、`tool/check-c-scope.mjs` 及其他 ABC 范围检查保留供历史交接审计使用，检查的是当时的文件边界，不是当前主线通用发布条件。当前入口不再运行旧文件哈希冻结规则，但仍运行功能测试、配置检查和正式签名验证。

手机使用同一个后端根地址和访问令牌。成员监护、家中风险、物品寻找均依赖配套后端，模型不内置在 APK 中。实时监护接口与软件更新接口分别参见 `../docs/PHONE_CAMERA_MONITORING.md` 和 `../docs/LOCAL_APP_UPDATES.md`。

旧 v1.2.1 双服务配置及早期“公共入口尚待装配”的说明已过期，历史材料保留在仓库文档中用于追溯。普通构建默认不启用 Firebase，不能据此承诺后台/锁屏推送。
