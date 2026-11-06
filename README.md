# 安居视界 Android App

当前维护主线：`main`。本次本机构建版本：`1.5.0+4017`（家庭账号与全员告警版）。实际版本始终以 [pubspec.yaml](mobile-app/pubspec.yaml) 为准。

本仓库只有一套当前 App 源码：`mobile-app/`。后端属于独立的 `anju-vision-website` 仓库。历史源码包、手册和 ABC 交接材料不作为当前构建入口。

## 当前能力

- 首页入口：成员监护、家中风险、物品寻找；底栏：首页、设备、消息、我的。
- 统一后端连接、成员档案与绑定、按成员查看事件、联系人与告警处理。
- 摄像头 RTSP 预览，并通过配套新后端配置、启动和停止持续监护；离开预览页不停止后端。
- MP4 分片上传、录像库、安全分析、物品寻迹、问答、事件证据和原片回看。
- 局域网后端的软件更新检查、下载和用户确认安装。
- 成员列表进入详情，电脑共享档案、人脸照片录入/试识别、告警身份候选与人工纠正。
- 家庭账号登录、扫码邀请和注册家庭成员列表。所有有效账号共享告警，App 前台按账号提醒，不分主备。

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

自建局域网 CA 可通过 -LanTlsProfile 读取部署机器上的 ca.pem（公开 CA）和 address.txt（每行一个私有 IPv4）。默认读取 Windows 用户本地数据目录下的 AnjuVision/lan-tls；本机地址和证书不提交 Git。未配置专用 CA 时使用系统信任。

首次需要本机私有的 `mobile-app/android/key.properties` 与原签名文件；这些文件不得提交。其他电脑可用 `-ToolsRoot` 指定自己的 Flutter/JDK/SDK 根目录。参见开发说明。

输出：`mobile-app/build/app/outputs/flutter-apk/`；签名及哈希报告：`mobile-app/build/BUILD-RESULTS.json`。APK 和本地配置由 Git 忽略。
