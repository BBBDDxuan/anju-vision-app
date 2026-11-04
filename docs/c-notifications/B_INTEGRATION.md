# 给 B：唯一告警流、范围化通知与详情接线

B 继续独占 main.dart、app.dart、app_controller.dart、API/设置服务、models 和 UI。本文件是接线要求；C 没有修改这些文件。当前已按 B 发布清单导入其统一后端入口，但尚未按下面内容装配 C 的独立通知模块，不能把独立模块测试通过当成 App 联调完成。

## 单一数据流

B 从 A 的 /api/alerts 全部历史页建立初始基线，以 /api/alerts/changes 的游标持续同步。历史分页、重连时补读历史、初始化缓存均传 historical: true；确认基线后的真正新变化传 false。只交付完整 snapshot，包含 id、revision、source、review_status、handling_status、notification_status。revision 必须为整数且单调；每告警持久化最大 revision 防止旧状态回放。

~~~dart
final scope = notificationScope(settings.baseUrl);
final gate = AlertNotificationGate(
  store: SecureNoticeStateStore(), scope: scope,
);
final notifications = UnifiedNotificationService(gate: gate, android: android);
final notices = await notifications.synchronize(
  snapshots, historical: isHistory,
  notificationsEnabled: preferences.notificationsEnabled,
);
// notices 返回本次新通知，供 B 更新应用内提示。
~~~

一个当前后端只保留一个 gate/service，禁止每次刷新新建。切换后端前停止/等待旧数据流，重新创建对应 scope 的 gate，不混用响应或导航。C 不负责 cursor 的事务，持久化/展示失败时 B 应处理错误并重试，不应跳过未消费变化。C 持久化失败不会发声；权限被拒绝仍返回应用内提示。待复核可转 confirmed 后提醒；已消费、ack/resolved、withdrawn、历史/开关关闭/取消不重放。

停用原版控制器中的重复提醒路径。FCM 前台 onForeground 只提示 B 刷新同一条权威流，由 gate 决定本地通知；不得按 FCM 再直接 show 一次，也不得把 provider accepted_by_provider 当作设备已响铃。后台通知由 SDK 显示，C 后台回调/点击记录独立 receipt；回前台 gate 查询它以减少补响，最终行为见真机验收限制。

## 冷/热启动点击

~~~dart
final pending = PendingAlertOpen();
await android.initialize(
  (_) { /* 旧原始 event_id 路由；不可混入统一告警 */ },
  onOpenScoped: (sourceScope, id) {
    pending.add(scope: sourceScope, id: id);
    // 仅在鉴权、当前 scope 和导航就绪后消费。
  },
);
final id = pending.take(notificationScope(settings.baseUrl));
if (id != null) {
  // B 通过 /api/alerts/{id} 加 bearer 拉取详情并导航。
}
~~~

统一 ID 不可传旧 /api/v1/events/{id} 路由，不信任 source event_id、外部 deep_link 或任意 URL。B 负责通知点击后读最新状态和鉴权证据；已处理/撤销仍显示真实状态，不因旧推送重新变成待处理。

## FCM 网关和 token 生命周期

~~~dart
final gateway = useFirebase
  ? FirebasePushGateway(
      currentScope: () => authenticatedSettings == null ? null
        : notificationScope(authenticatedSettings!.baseUrl),
    )
  : null;
~~~

B 把它交给现有 PushCoordinator，onOpen 加入当前 scope 的 pending 队列，onForeground 刷新唯一权威流。currentScope 在连接切换时立即更新；默认构造无回调会拒绝统一推送路由。C 要求推送 payload 的 scope 精确匹配 server APP_FCM_ORIGIN + |default。不要通过回调放宽为任意后端。

configure 需要实际 bearer。默认构建 USE_FIREBASE=false 不会得到后台推送；只有成功注册 token 才显示已登记。token 轮换先保存新登记，再删除本安装旧 token；中途失败保留清理任务重试。关闭通知/退出登录在旧 repository/settings 仍可用时先 await coordinator.detach()/unregister()，再清空凭据。切换后端前先注销旧后端；失败应保留旧连接以重试。C 不会拿新后端凭据删除旧后端的登记，也不会删除另一台手机。

## 已导入 B 的发布版本

B 的 796c7658b228aa1b650f23140b622dca52f8d857 已完整导入 25 文件，哈希见 upstream-b/change-manifest.json。默认地址已统一到 8000。C 检查同时固定原始未改文件和 B 已发布文件的哈希。

B 在 controller.initialize() 之前订阅 controller.alertSnapshots.stream，串行转发 snapshot.events.map((event) => event.details)，historical 使用 snapshot.initial，开关使用 snapshot.notificationsEnabled；先检查 snapshot.complete 和 scope。必须使用 events 的最终状态，不能逐条转发 changed 中的中间态。切换 scope 时按上述要求换 gate，等待上一同步完成。

B 的默认 AndroidNotices.initialize 只传旧 String 回调。装配时同一实例增加 onOpenScoped，由当前 scope 和统一 ID 取得最新 /api/alerts/{id} 后，用真实 source 构造 AlertLocation 并交给 controller.openAlert。不能猜来源、丢弃 scope，或再注册第二个原生 handler。FCM currentScope 和前台刷新亦须按上面约定装配。

这些入口装配尚未实施；本次仅按发布哈希导入 B 文件，未越界修改。
