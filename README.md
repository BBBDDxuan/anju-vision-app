# 安居视界 Android App

当前维护主线：`main`。本次本机构建版本：`1.5.4+4021`（家庭账号、扫码证书配对与前台系统通知版）。实际版本始终以 [pubspec.yaml](mobile-app/pubspec.yaml) 为准。

本仓库只有一套当前 App 源码：`mobile-app/`。后端属于独立的 `anju-vision-website` 仓库。历史源码包、手册和 ABC 交接材料不作为当前构建入口。

## 当前能力

- 首页入口：成员监护、家中风险、物品寻找；底栏：首页、设备、消息、我的。
- 统一后端连接、成员档案与绑定、按成员查看事件、联系人与告警处理。
- 摄像头 RTSP 预览，并通过配套新后端配置、启动和停止持续监护；离开预览页不停止后端。
- MP4 分片上传、录像库、安全分析、物品寻迹、问答、事件证据和原片回看。
- 局域网后端的软件更新检查、下载和用户确认安装。
- 成员列表进入详情，电脑共享档案、人脸照片录入/试识别、告警身份候选与人工纠正。
- 家庭账号登录、扫码邀请和注册家庭成员列表。所有有效账号共享告警，App 前台按账号提醒，不分主备。
- 扫码连接并登录当前电脑，下载公开 CA 并核对二维码中的证书指纹，不需要重新打包含部署证书的 APK。
- Android 13+ 首次登录家庭账号后申请通知权限，前台同步到新复核确认告警时发送系统通知；“我的”与关于页面显示实际安装版本。

识别模型运行在电脑后端。账号版仅提供前台告警提示，未启用后台或锁屏云推送。App 新接口需要与配套后端版本一起部署；仅更新 APK 不会自动更新后端。

## 目录

| 路径 | 用途 |
|---|---|
| `mobile-app/lib/` | 当前 Flutter 源码 |
| `mobile-app/android/` | 原生 Android、RTSP、通知及更新安装逻辑 |
| `mobile-app/test/` | 当前自动化测试 |
| `mobile-app/assets/` | 插画、离线手册和许可 |
| `build.ps1` | 当前仓库的统一验证、正式构建和签名检查入口 |
| `docs/DEVELOPMENT.md` | 分支、合并、上传、构建及历史资料说明 |
| `docs/MEMBER_MONITORING.md` | 共享成员、人脸录入与联系人提醒 |
| `docs/PHONE_CAMERA_MONITORING.md` | 手机控制后端监护及后端配套要求 |
| `docs/LOCAL_APP_UPDATES.md` | 局域网更新功能及后端发布契约 |
| `docs/UPLOAD-FIX-v1.2.3.zh-CN.md` | 上传误报修复的起始版本记录 |
| `docs/b-app/`、`docs/c-notifications/`、`docs/b-c-integration/` | ABC 历史交接与验证记录，保留追溯 |
| 根目录 `v1.2.1` 手册、校验文件、历史安装包 | 历史发布资料，不能代表当前版本 |

## 本机开始

```powershell
Set-Location -LiteralPath 'D:\大学文件\比赛\天猫\anju-vision-app'
git status -sb
git pull --ff-only origin main
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

默认使用已安装在 `D:\AndroidDev` 的工具，构建 ARM64 正式包。源码、Gradle 构建和最终输出均位于本仓库，工具及缓存继续留在外部工具目录。

局域网证书通过扫码配对下载并验证，构建脚本不再接收 `-LanTlsProfile`，也不将某台电脑的 CA 或 IP 封装进 APK。配套 Web 仓库的 `start-phone.bat` 自动维护本机 HTTPS 配置；在电脑头像 → 家庭管理生成“手机连接并登录二维码”，App 在登录页选择“扫码连接或登录”。首次下载仅获取公开 CA，核对指纹并完成证书链及地址校验后才发送登录码。私钥留在电脑，信任按后端地址保存在手机安全存储中。

同一地址、同一 CA 下续期无需重新打包。IP 或 CA 变化后重新扫码；正式账号登录优先使用 HTTPS。注册密码至少 8 个字符，注册界面使用“昵称”。

首次需要本机私有的 `mobile-app/android/key.properties` 与原签名文件；这些文件不得提交。其他电脑可用 `-ToolsRoot` 指定自己的 Flutter/JDK/SDK 根目录。参见开发说明。

输出：`mobile-app/build/app/outputs/flutter-apk/`；签名及哈希报告：`mobile-app/build/BUILD-RESULTS.json`。APK 和本地配置由 Git 忽略。
