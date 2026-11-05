# 主线开发与本机构建

## 唯一工作目录

`D:\大学文件\比赛\天猫\anju-vision-app`

App 源码在下面的 `mobile-app/`。同级其他带日期的源码目录和 `D:\AndroidDev\app-*` 是历史构建副本；今后不在那里继续开发。本仓库不会复制源码到这些副本进行构建。

## 本次合并

- 原本地分支：`codex/b-c-integration-build`，原提交 `ab29d4f`。
- 本地上传误报修正先独立提交，保留在 `backup/upload-fix-before-main-20261105` 与原分支。
- 合并起点：远端 `main` 的 `22c7a8c`，已有证据阶段选择、手机控制持续监护、局域网软件更新功能。
- 将本地修正合并进当前 `main`，保留所有双方提交历史。
- 唯一冲突是 `pubspec.yaml` 的版本号，统一升到 `1.2.5+4010`。
- 未采用文件夹覆盖或强制推送。实际远端提交以 `git log` 为准。

## 今后直接维护 main

开始前先确认文件状态，干净工作区再更新：

```powershell
git switch main
git status -sb
git pull --ff-only origin main
```

改动完成后，先验证构建，再明确添加本次文件、提交并上传：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
git add <本次修改的文件或目录>
git commit -m "说明具体改动"
git fetch origin
git log --oneline --left-right main...origin/main
# 若远端这段时间有新提交：
git merge origin/main
# 合并改动后重新进行必要验证；全部通过再推送：
git push origin main
```

已有未提交改动时先提交到本地再合并；不使用 `reset --hard` 或 `push --force` 覆盖他人的更新。直接使用 main 不会消除冲突，仍需在 push 前同步。保留备份分支，其他人也可继续各自分支开发后合并。

## 构建

```powershell
# 本机默认，ARM64 正式包
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
# 另一工具安装位置
.\build.ps1 -ToolsRoot 'E:\AndroidDev'
# 三种架构
.\build.ps1 -TargetPlatform android-arm,android-arm64,android-x64
# 调试包（应用 ID 带 .test，不能覆盖正式版）
.\build.ps1 -Configuration debug
```

使用现有 Flutter、JDK、Android SDK 和 Node。默认工具根目录为 `ANJU_ANDROID_TOOLS_ROOT` 或 `D:\AndroidDev`。配置只作用于当前构建进程。

签名只读取本机忽略文件 `mobile-app/android/key.properties` 指向的原私钥。不要在仓库或聊天中粘贴密码。正式构建必须核验原证书，不能换签名覆盖安装。Firebase 仅在显式指定 `-WithFirebase` 且配置有效时启用。

脚本运行 `tool/verify.ps1` 和当前通知配置检查，恢复锁文件依赖、Dart 分析、Flutter 测试。当前中文路径使用 SDK Dart analyzer，避免旧 Flutter analyzer 的 Unicode LSP 问题。

产物：`mobile-app/build/app/outputs/flutter-apk/`。报告：`mobile-app/build/BUILD-RESULTS.json`。正式分架构包带 Android ABI 版本号偏移，本版 ARM64 实际版本号为 `6010`。

本机 AOT 编译器已实际复现中文路径读取失败。构建入口会在检测到中文路径时调用既有 `tool/ascii-env.ps1`，选择两个未占用的盘符，为同一物理仓库和工具建立临时 ASCII 别名，构建结束自动移除。源码和产物仍在本仓库，不创建另一份源码；已占用盘符不会被覆盖。Kotlin 增量缓存在依赖缓存和源码位于不同盘符时也已复现失败，因此构建进程临时设置 `kotlin.incremental=false`，结束后恢复环境。代价是 Kotlin 重编译可能变慢。

## 结构与资料分层

源码已有清晰的 UI / models / services 和 Android 原生层。主要维护问题是历史版本说明和 ABC 交接资料与当前资料并列，以及入口脚本仍使用 C 阶段的范围冻结检查。

本次保留历史文件以便审计，增加根 README 和统一构建入口。旧范围脚本只用于原任务的历史验证；当前发布使用本入口运行实际分析、测试、编译和签名检查。根目录旧 v1.2.1 SHA/手册不能用于验证当前 APK。

旧 APK/源码 ZIP 在 Git 历史中仍被跟踪；增加 `.gitignore` 不会移除这些历史文件。本机 sparse checkout 只省略四个旧发布附件，App 源码完整。这不是分支缺失或源码缺失。

## 后端配套

本次只上传 App 仓库。电脑端另有本地诊断日志、主机白名单启动参数修改，属于 `anju-vision-website` 仓库，不会随 App 推送。本机当前 `/api/monitoring/camera` 与 `/api/app/version` 实测均返回 404，需要另行同步配套后端；不要将 APK 更新等同于后端更新。

上传误报修正用于显示真实错误，不能代替处理视频旋转、格式或 FFprobe 的实际问题。尚需用之前失败的视频进行手机真机入库验收。
