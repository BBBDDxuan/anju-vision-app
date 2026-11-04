# 安居视界共享后端

网页和手机共用这个服务项目。现阶段在本机运行；之后可以部署到独立服务器，客户端改连接地址即可。检测需要合适的算力，云端迁移也需带上模型和媒体工具。

## 日常启动

双击 `start-phone.bat`。手机统一访问 8000；8010 是仅监听 `127.0.0.1` 的内部安全服务。地址和统一令牌保存到 `runtime/手机连接参数.txt`，请勿上传或转发。电脑网页：`http://127.0.0.1:8000/`。旧版 App 的两组服务配置都填写同一个 8000 地址和统一令牌。

手机与电脑需网络互通。电脑可以连接手机热点；启动脚本使用电脑当前的局域网 IPv4，换网络后重启服务并更新 App 地址。联调时电脑必须保持运行。此启动方式不是开机自启服务。

## 目录职责

| 目录 | 用途 |
| --- | --- |
| `backend/` | 统一手机入口、持久化告警中心，以及原有录像、任务、播放和网页 API |
| `safety/` | 设备、联系人、告警及通知 API；独立私有配置 `safety/.env` |
| `detector/` | 本地小模型推理、摄像头 worker、检测测试和 GPU 环境 |
| `models/` | 权重及来源、许可信息 |
| `tools/ffmpeg/` | 已验过哈希的兼容媒体工具 |
| `web-dist/` | 从网页仓库发布的构建产物 |
| `data/` | 私有录像、数据库；来源库在 `data/safety/`，统一告警与快照在 `data/alert-center/` |
| `runtime/` | 本机生成配置、日志、连接参数和缓存 |
| `scripts/` | 配置、自检、回归辅助工具 |
| `docs/legacy-monolith/` | 原单体项目文档，历史路径以新架构文档为准 |

## 配置与检查

现有模型接口和密钥设置保存在根 `.env`；沿用原提供商，不会因迁移自动更换。大模型密钥仍需在本机填写，当前网络调用开关保持原值。安全服务的 `mock` 模式仅用于模拟，不能当作真实推送验收。

统一入口提供 `/api/connection`、`/api/alerts`、详情、增量同步、证据及幂等确认。实摄和上传录像只在已有视觉复核确认后纳入正式告警。新启动器关闭旧安全 worker，避免候选或 mock 通知绕过统一确认流程；旧 `/api/v1/events` 仅保留兼容用途。C 的独立异步推送模块通过 `APP_ALERT_PUSH_HANDLER=模块:函数` 接入，未配置时不发送推送。

手机接入步骤见 [PHONE_LOCAL_SETUP.md](docs/PHONE_LOCAL_SETUP.md)，B/C 接口契约见 [PHONE_API_CONTRACT.md](docs/PHONE_API_CONTRACT.md)，A 的验证与待验收项见 [ROLE_A_HANDOFF_20261104.md](docs/ROLE_A_HANDOFF_20261104.md)。

当前机器的 Python 环境随项目迁移。新机器用 `setup.bat` 创建环境，GPU 依赖较大。`scripts/configure_phone.py` 生成缺失的本地令牌，保留已有值。执行 `.venv\Scripts\python.exe scripts\doctor_team.py` 可检查媒体工具、页面和 GPU 模型（合成图像，无摄像头或付费调用）。

完整后端与检测测试：运行 `powershell -ExecutionPolicy Bypass -File .\test.ps1`，脚本会设置兼容媒体工具路径，并分进程运行三个测试集。前端修改后，在网页仓库运行 `publish-web.ps1`。

根 `.env`、`.env.phone`、`safety/.env`、全部运行数据和虚拟环境均忽略提交。本后端发布于 App 仓库的 `server/`，版本通过 `git rev-parse HEAD` 记录。整体结构见 [ARCHITECTURE.md](../docs/ARCHITECTURE.md)。
