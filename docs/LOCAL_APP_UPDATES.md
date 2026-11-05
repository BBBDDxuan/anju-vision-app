# 本机 website 提供 App 更新

本功能基于 2026-11-05 的 App 主分支 `836ea9e` 与 website 主分支 `116eeed`，源码版本为 `1.2.4+4009`。本轮授权同时覆盖 App 公共入口、Android 安装接线与 website 更新接口；原 ABC 开发阶段的冻结检查继续保留，不能拿旧基线检查代替本功能验证。

## 手机使用

1. 首次手动安装一次包含本功能、使用原正式签名的新 APK。此前的旧 APK 不会凭空获得更新能力。
2. 在“我的 → 连接服务”保存电脑的局域网地址与访问令牌。更新使用同一地址及令牌，无需域名或额外服务器。
3. App 启动、切换连接或回到前台时检查更新；持续前台时每 30 分钟检查一次。同一连接的自动检查至少间隔 30 分钟。“我的 → 软件更新”可立即手动检查。
4. 发现适合当前手机且实际 Android 版本号更高的包后自动下载。下载完显示提示；更新页有进度、更新说明、取消和重试。
5. 点击“安装新版”，按 Android 系统提示确认。首次如需允许此应用安装更新，授权后返回更新页再点击安装。取消安装后可再次点击。不要为升级先卸载旧版。

电脑、后端与网络需可达。检查失败、尚未发布新包、断网或用户取消不影响原有业务。切换后端或访问令牌会取消旧任务；后台不启动定时下载服务。

## 电脑发布

新版 APK 保存在电脑的 website 私有运行目录 `runtime/app-updates/`，不放进 Git，不上传源码 ZIP。按 website 的 `docs/LOCAL_APP_UPDATES.md` 用 `scripts/publish_app_update.py` 发布经过检查的正式安装包。首次采用本轮后端代码需启动或重启原 `start-phone.ps1`；之后发布新包无需重启。

脚本读取实际 APK 包名、版本、CPU 架构和签名，生成更新清单。不是把 `pubspec.yaml` 中的数字直接填进清单：Flutter 分架构包的实际 versionCode 带架构偏移，手机端使用 Android 返回的已安装值比较。建议一次发布所有需要的 ABI。

后端契约：

- `GET /api/app/version?version_code=<实际已安装版本号>&abi=<手机首选ABI>`
- 未发布或没有新版：`{"available": false, "update": null}`。
- 有新版：`update` 包含 `version_name`、`version_code`、`abi`、`package_name`、`size_bytes`、`sha256`、`download_path` 和 `notes`。
- `download_path` 固定为同一后端的 `/api/app/apk/<sha256>`；查询与下载均携带现有 Bearer 令牌，不接受跨站跳转。

安装包最大 256 MiB。手机先校验长度、SHA-256、实际包名和版本、架构及 Android 最低版本，再与当前已安装 App 的签名证书严格比对。安装前再检查一次；系统安装器负责最终验证与用户确认。签名私钥不发给手机或后端。调试包 `.test` 与正式包不会互相覆盖。

## 构建与验证

沿用原正式签名。普通功能不要求 Firebase，不增加 Flutter 依赖；当前应用 ID 与原有数据存储方式保持一致。安装权限 `REQUEST_INSTALL_PACKAGES` 只用于用户确认的更新，FileProvider 仅暴露更新缓存子目录。

在具备 Flutter、JDK 17、Android SDK API 36 和原私有签名配置的机器运行：

```powershell
flutter pub get --enforce-lockfile
node tool/source_check.mjs
node tool/check-c-config.mjs
node tool/check-app-update-scope.mjs
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
./tool/build-c.ps1 -Release -SkipChecks -ExpectedSigningSha256 2472d43f63dbea0d2d3c34933114caf3dc532055c97ceaa40e96a968070b3e35
```

`-SkipChecks` 用于跳过旧 C 独立开发阶段的范围检查；前面的本轮检查必须先执行，签名校验仍由构建脚本执行。构建完成后，按电脑端发布文档发布 APK。

本轮没有 SDK/JDK 构建环境，因此不把 Flutter 测试或静态检查称为 Android 编译、正式 APK 或真机升级验收。现场还需验证：旧正式版升级到新版、连接设置和成员档案保留、安装权限、取消安装后重试、错误签名拒绝、两种实际手机架构及断网恢复。
