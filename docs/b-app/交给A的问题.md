# B 联调发现：FFmpeg 9 转码兼容

归属：A。B 未修改任何后端文件。

基于网站提交 `d272b8737ddd59a33e66b79ef120e60bf6d2be6b`，在本机 FFmpeg `9.0.2-essentials_build` 上复现。

## 表现与原因

- 创建分片会话成功、分片上传成功。
- 对需要重新编码的 MPEG-4 Part 2 MP4，`POST /api/uploads/{id}/complete` 返回 HTTP 400，错误码 `TRANSCODE_FAILED`。
- `backend/media.py` 的 `prepare_playback()` 非 H.264 分支使用 `-vsync 0`。
- 同样参数直接调用当前 FFmpeg 返回：

```text
Unrecognized option 'vsync'.
Error splitting the argument list: Option not found
```

原始诊断在 `验证记录/b-a-ffmpeg-compatibility.txt`，没有摄像头账号、用户视频或真实凭据。

## 本轮处理

- B 修改手机错误分类：明确显示“视频转码失败，请由后端检查 FFmpeg 与编码兼容性”，不再把此 400 笼统显示为白名单失败。
- HTTP 上传正向验证使用单独生成的 H.264 合成 MP4，走原后端可复制/复用的播放准备分支；分片、录像库、物体任务及结果均通过。
- 这不代表非 H.264 视频问题已解决，也不代表已完成真实识别验收。

请 A 修复媒体参数兼容或冻结匹配的媒体工具版本，并重新验收需转码的 MP4。B 不在自己的分支修改 `backend/media.py`，也不调整模型或检测阈值。
