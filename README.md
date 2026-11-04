# 安居视界 App 与共享后端

本仓库保留 v1.2.1 手机交付包，并新增 A 负责的完整共享后端 `server/`。后端统一接收实时摄像头与上传录像的视觉确认告警，供同一家庭的多部手机读取、查看证据和确认处理。

## 目录

| 位置 | 内容 |
| --- | --- |
| `server/` | Python 后端、检测代码和权重、FFmpeg、网页构建、安装启动脚本及测试 |
| `server/docs/PHONE_API_CONTRACT.md` | B/C 接口契约：统一地址、认证、告警、证据、增量同步及推送接点 |
| `server/docs/ROLE_A_HANDOFF_20261104.md` | A 修改说明、验证证据与真实联调待办 |
| `docs/` | 当前结构及三人联调分工 |
| 根目录 APK、源码 ZIP、截图和原手册 | 保留的 v1.2.1 历史交付物，不代表已接入本次统一告警 |

## 在电脑启动后端

安装 Python 3.12+ 后，在 Windows PowerShell 中执行：

```powershell
git clone https://github.com/BBBDDxuan/anju-vision-app.git
cd anju-vision-app/server
powershell -ExecutionPolicy Bypass -File .\setup-team.ps1
.\.venv\Scripts\python.exe scripts/configure_phone.py
powershell -ExecutionPolicy Bypass -File .\start-phone.ps1 -Address '电脑当前局域网IPv4'
```

完整检测安装默认需要兼容 NVIDIA GPU/CUDA；只安装 API 可给 setup 脚本加 `-BackendOnly`，这不等于真实检测环境可用。模型密钥与摄像头地址在本机私有配置填写，模板不包含真实值。安装不会自动授权付费模型调用。

电脑网页为 `http://127.0.0.1:8000/`。手机只使用 `http://电脑局域网IP:8000` 和一个访问令牌；启动后在服务端 `runtime/手机连接参数.txt` 读取。旧 App 两组连接字段都填同一地址、同一令牌。内部 8010 不对手机开放。

详细安装、网络和错误排查见 [手机连接说明](server/docs/PHONE_LOCAL_SETUP.md)。正式告警列表需要 B 接入 `/api/alerts`；C 需要接入独立通知/推送模块。现有 APK 不会因上传后端自动升级。

## 验证与当前范围

实现阶段完整回归 1001 项通过，最后的 run 绑定修正另通过 95 项针对性测试。证据见 [验证记录](server/docs/validation/role-a-20261104.json) 和 [A 交接说明](server/docs/ROLE_A_HANDOFF_20261104.md)。执行 `server/test.ps1` 可重跑后端、安全与检测三个测试集。

真实摄像头、真实录像、两部真机及前台/后台/锁屏送达仍须联调验收。仓库不包含真实 `.env`、录像、历史数据库、API Key、RTSP 密码、Firebase 私密凭据或签名私钥。
