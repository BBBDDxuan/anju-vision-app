# B → C 通知与详情接点（待 C 模块确认装配）

B 维护 `main.dart / app.dart / app_controller.dart` 与详情路由；C 维护自己的通知实现及 Android/Firebase。不要让 C 的模块另开告警列表轮询。

## 业务数据接点

`SafetyController.alertSnapshots.stream` 是唯一统一告警业务流，输入类型位于 `lib/models/unified_alert.dart` 的 `AlertSyncSnapshot`：

- `backend`、`household`、`scope`：无凭据的后端/家庭作用域；当前 A 契约仅支持 default 家庭。
- `cursor`：本次完整同步后确认的增量游标。
- `initial`：首次成功同步或中心重建后的重新基线，默认不批量提醒。读到缓存并不算成功基线。
- `complete`：只有全部分页与期间 changes 成功后才发送此快照，恒为 true。失败不会发送一个假的完整空列表。
- `events`：本次成功同步的最终统一告警镜像。
- `changed`：本次读取的 changes，可能包含同 ID 多次修订。
- `active`、`notificationsEnabled`：当前前台状态和已经同步的家庭提醒开关。

注册订阅必须发生在 `controller.initialize()` 之前。不要在收到第一个增量后把所有历史当作新事件。

```dart
final subscription = controller.alertSnapshots.stream.listen((snapshot) {
  // C：交给自己的通知模块处理；不是在此再请求 /api/alerts。
  // initial => 建立历史基线、不批量响铃。
  // 使用 scope + 全局 event.id 去重。
});
```

正式危险通知至少要求最终事件的 `reviewStatus == 'confirmed'`、未 acknowledged、未 resolved、未 withdrawn，且家庭提醒开启，并遵守系统权限与前后台能力。

同一 changes 批次可能先出现待处理快照、后出现已解决快照。C 必须以 `snapshot.events` 中该 ID 的最终状态判断资格，不能根据中间修订误提醒。通知级去重、持久历史基线及安装实例登记由 C 自己负责。

统一模式下 B 不向旧 `controller.notices` 添加危险通知，也不通过旧 FCM 前台回调直接鸣铃；旧路径仅保留在显式注入的旧仓库兼容测试中。C 不要把新告警再写入旧 notices 通道，否则会造成双重展示。

## 点击通知打开详情

通知载荷使用 `AlertLocation.toJson()` 的四个字段，不能携带访问令牌、RTSP 地址或电脑路径：

```json
{
  "backend": "http://电脑局域网IPv4:8000",
  "household": "default",
  "alert_id": "统一告警的全局id",
  "source": "live_camera"
}
```

```dart
final location = AlertLocation.tryParse(payload);
if (location != null) controller.openAlert(location);
```

- App 已启动时，进入公共 `/alerts/{id}` 详情路由。
- 冷启动、设置或导航尚未就绪时，先保存在 controller 的有界队列，待 App 初始化完成再消费。
- 与当前后端/家庭不匹配时提示切换，不自动打开当前服务中的同名 ID。
- 详情再向服务端按全局 ID 获取记录并核对来源；不依赖列表中恰好已有该条。
- 切换服务后，已打开的详情清空旧数据并拒绝旧连接的操作结果。

现有原生通知桥若暂时仍往返一个 String，B 的 App 入口支持把上述对象 `jsonEncode` 后作为载荷，点击后解析为 AlertLocation。统一模式下不接受无作用域的旧裸 event ID。

## 初始化所有权

当前没有 C 的新模块，因此 B 未虚构模块导入或 Firebase 配置。现有 `AndroidNotices` 的 MethodChannel 点击回调仍由 App 公共入口装配。C 不要在另一个实例重复初始化同一点击 handler；应交付独立模块及明确的初始化、snapshot、点击、dispose 方法，B 再在公共入口整合为唯一装配点。

旧 `/api/v1/push-tokens` 的安装实例归属与 token 轮换机制尚待 A/C 完成。B 没有用旧按联系人登记流程冒充新的多安装实例登记完成。

## 不代表已经完成

类型、作用域、历史基线标志和点击入口已经测试；通知实际显示、稳定去重实现、FCM、后台/锁屏送达、原生点击 Intent 以及两部真机，仍由 C 与 A/B 联调验收。
