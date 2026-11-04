# 手机连接本机后端

## 日常启动

在项目根目录双击 `start-phone.bat`。同一终端管理录像服务 8000 和可选安全服务 8010；保持终端运行，按 Ctrl+C 停止。

电脑网页：<http://127.0.0.1:8000/>。本机网页保留原有用法。

启动器根据当前网卡生成 `runtime/手机连接参数.txt`。手机 App 的“我的 → 连接服务”分别填入该文件中的录像服务地址/令牌、安全后端地址/用户令牌，联系人角色选 primary。两组令牌不同，不要交换。原 v1.2.1 APK 可以填写这些设置，无需为了改变服务器地址重新打包。

手机与电脑需要网络互通。真机使用电脑当前的局域网地址；`127.0.0.1` 指向手机自身。模拟器一般使用 `10.0.2.2`，在 App 中替换参数文件地址的 IP 部分即可。

有多个活动网卡时明确指定地址：

```powershell
.\start-phone.ps1 -Address '电脑当前局域网IPv4'
```

原 `start.bat` 仍是仅供电脑使用的本机入口；不要同时启动两个占用 8000 的入口。

## 访问令牌和网络

录像访问令牌保存在被 Git 忽略的 `.env.phone`，安全服务令牌保存在 `elder-safety/.env`；连接参数文件也位于忽略目录。没有令牌的局域网录像请求返回 401；录像、API 和高级工作台都受保护。本机 loopback 页面继续可用。启动器禁止代理头改写客户端 IP，不能通过伪造 X-Forwarded-For 绕过令牌。

主机白名单每次启动自动加入当前局域网 IP，不使用通配符。现有实时摄像头控制接口的本机限制保留，手机能预览 RTSP 不代表能远程控制电脑实时 AI。

当前方式用于局域网联调，令牌通过 HTTP 传输；不要将此入口做公网端口映射。离家访问应改用受控 VPN 或 HTTPS 入口。

如果电脑访问正常、手机连接失败：核对地址、Wi-Fi/热点互通、Windows 对所用 Python 的入站规则，以及校园网/访客网络是否隔离终端。启动成功和电脑自测不能证明手机已穿过这些网络限制。

## 模型服务：沿用项目现有接口

根 `.env` 保留原有模型接口 `VLM_BASE_URL`、模型名和额度设置。请在本机填写：

```dotenv
VLM_API_KEY=你的现有服务密钥
VLM_ENABLE_NETWORK=true
```

不要把密钥发到聊天或提交到 Git。填写后重启手机后端入口。仅填写 Key 而不启用网络时，后端会继续明确提示网络调用未启用。没有有效密钥时，连接、录像管理和播放可独立使用，真实模型分析不可用。

费用与模型名以该服务提供方为准。本次安装与验证不调用付费模型，不自动分析私人视频或连接真实摄像头。

## 本地检测与媒体工具

检测环境为 `elder-safety/.venv-gpu`，使用本机 NVIDIA GPU；本机模型配置为 `runtime/team-camera.json`。可重新自检：

```powershell
.\.venv\Scripts\python.exe scripts\doctor_team.py
```

本次 `runtime/team-doctor.json` 已通过，姿态与明火模型均在 RTX 4060 的 `cuda:0` 完成合成图像前向推理。本机旧备用 `config.camera-gpu.json` 的失效路径也已修复，原文件备份在 `runtime/phone-legacy-camera-config-before.json`，检测阈值保留原值。

当前后端转码参数需要兼容 `-vsync` 的 FFmpeg。本机 `.env` 已选择仓库自带的 `elder-safety/tools/ffmpeg/ffmpeg.exe` 和 `ffprobe.exe`；原 `tools/ffmpeg/` 的 9.0.2 工具保留，但不再供当前后端转码使用。

`elder-safety/.env` 中复核和推送默认仍为 mock；这不表示真实视觉复核或 Firebase 推送已经送达。8000 的视频安全分析使用根配置的独立混合识别链路。8010 启动后不会自动从手机 RTSP 预览注册设备，也不会自动接入所有实时告警。

## 配置备份与验证记录

修改前 `.env`、可选安全配置及原手机令牌配置备份在 `runtime/phone-setup-backup-*/`。本次验证记录保存在 `review/phone-*.log`、`review/phone-live-check.json` 等文件中。模型密钥、网络开关和预算没有被静默替换。
