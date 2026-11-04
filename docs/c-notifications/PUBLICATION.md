# C GitHub 源码交付基线（2026-11-04）

- App 基线：e85049da4ec702c74d84d2a46473dcf813985b78，尊重 A 撤回误放后端的提交。
- B 来源：796c7658b228aa1b650f23140b622dca52f8d857；从已发布 overlay 按 change-manifest.json 导入全部 25 个文件，逐字节核验 SHA-256；未手工修改 B 拥有的文件。补丁文本与清单保留在 upstream-b/ 供复查。Windows 原始 CRLF 使直接 git apply 检查失败，因此使用 B 同次发布的 overlay 精确字节；ZIP 仅在内存读取，没有新增提交。
- website C 提交：3fde57e33ffcfca5ca9c19bd27c7e0a8c4888719。
- website 后端基线：d272b8737ddd59a33e66b79ef120e60bf6d2be6b；C 插件仅在 website 的 backend/push_notifications/，测试在 tests/push_notifications/。App 不恢复 server/ 副本。
- 两仓库 C 分支均为 codex/c-notifications-release；以实际 Git 提交和远端引用为准。
- 本次新增提交不含源码 ZIP、APK、SDK、缓存、签名或真实 Firebase 凭据。历史发布附件保留。

## 构建前仍须联调

B 发布说明明确将通知装配留给 B/C：App 公共入口当前未订阅 C 的通知模块，FCM 的 currentScope、原生 scoped 点击和 snapshot 转发尚未装配。B 的 25 个文件保持发布哈希，C 不越界修改入口。接口见 B_INTEGRATION.md。编译成功也不能代表统一通知已接通。

B 还报告 FFmpeg 9 的非 H.264 转码存在 -vsync 兼容问题（upstream-b/交给A的问题.md），当前 A 基线尚未修复；由 A 处理。

Android SDK/JDK、Firebase 测试配置、原正式签名和两部真机验收仍需准备。本次上传任务不启动 APK 编译。
