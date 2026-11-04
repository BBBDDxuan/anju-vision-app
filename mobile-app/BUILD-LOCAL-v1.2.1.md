# 本机构建

源码：`AnjuVision_Android_v1_2_1_20261103/mobile-app`。本机英文路径联接：`D:/AndroidDev/app-v1.2.1`。

环境位于 `D:/AndroidDev`，运行 `. D:/AndroidDev/env.ps1` 后使用 Flutter。JDK 17、Android SDK 36，依赖版本锁定于 pubspec.lock。安装包已使用本机原发布密钥签名，密钥不随源码分发。

```powershell
Set-Location D:\AndroidDev\app-v1.2.1
. D:\AndroidDev\env.ps1
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release --split-per-abi
```

原网页只作为 API 与功能参考，不需要修改或重新打包到 App。完整工作台从所配置的原后端加载，后端须提供现有 `/workspace` 和静态资源。
