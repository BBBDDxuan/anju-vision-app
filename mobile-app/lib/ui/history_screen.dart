import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../models/models.dart';
import 'widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.controller,
    required this.openEvent,
  });
  final SafetyController controller;
  final void Function(String) openEvent;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _tab = 0;
  String _query = '';
  String? _type;
  String? _source;
  DateTimeRange? _range;
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final filtered =
        EventFilter(
              from: _range?.start,
              to: _range == null
                  ? null
                  : DateTime(
                      _range!.end.year,
                      _range!.end.month,
                      _range!.end.day + 1,
                    ),
            )
            .apply(c.events)
            .where(
              (e) =>
                  (_tab == 0 ||
                      (_tab == 1
                          ? !e.acknowledged && !e.resolved
                          : _tab == 2
                          ? e.acknowledged && !e.resolved
                          : e.resolved)) &&
                  (_type == null || e.eventType == _type) &&
                  (_source == null || e.details['source'] == _source) &&
                  ('${eventTypeLabel(e.eventType)} ${eventSourceLabel(e, c.nameForDevice(e.deviceId))} ${e.id} ${e.eventType}')
                      .toLowerCase()
                      .contains(_query.toLowerCase().trim()),
            )
            .toList();
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView(
        key: const PageStorageKey('history'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Text(
            '守护消息',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _search,
            onChanged: (s) => setState(() => _query = s),
            decoration: InputDecoration(
              hintText: '搜索事件或设备',
              prefixIcon: const Icon(Icons.search_rounded),
              fillColor: Colors.white,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(['全部消息', '待回应', '已确认', '已解决'][i]),
                      selected: _tab == i,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _tab = i),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final entry in const <String?, String>{
                null: '全部来源',
                'live_camera': '实时摄像头',
                'uploaded_recording': '上传录像',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _source == entry.key,
                  onSelected: (_) => setState(() => _source = entry.key),
                  showCheckmark: false,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                avatar: const Icon(Icons.tune_rounded, size: 15),
                label: Text(_type == null ? '事件类型' : eventTypeLabel(_type!)),
                onPressed: () => _chooseType(context),
              ),
              ActionChip(
                avatar: const Icon(Icons.calendar_today_outlined, size: 14),
                label: Text(
                  _range == null
                      ? '全部日期'
                      : '${_range!.start.month}/${_range!.start.day}—${_range!.end.month}/${_range!.end.day}',
                ),
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: _range,
                    helpText: '选择事件日期',
                    saveText: '确定',
                  );
                  if (mounted && range != null) setState(() => _range = range);
                },
              ),
              if (_type != null || _range != null)
                TextButton(
                  onPressed: () => setState(() {
                    _type = null;
                    _range = null;
                  }),
                  child: const Text('重置筛选'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '共 ${filtered.length} 条匹配记录',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '已加载 ${c.events.length} 条',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (c.videoError != null)
            InfoBanner('录像服务：${c.videoError}', error: true),
          if (c.error != null) InfoBanner('实时摄像头服务：${c.error}', error: true),
          if (filtered.isEmpty)
            const Surface(
              child: EmptyState(
                title: '这里还没有消息',
                message: '试试其他筛选条件，或下拉刷新最新事件。',
                icon: Icons.notifications_none_rounded,
              ),
            ),
          for (final e in filtered)
            EventTile(
              event: e,
              deviceLabel: c.nameForDevice(e.deviceId),
              personLabel: c.personLabelFor(e),
              onTap: () => widget.openEvent(e.id),
            ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '搜索与筛选仅覆盖当前已加载的最近记录。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Anju.muted),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseType(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              '筛选事件类型',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          for (final type in <String?>[
            null,
            'suspected_fall',
            'help_requested',
            'fire_detected',
            'sparks_detected',
            'device_offline',
          ])
            ListTile(
              leading: Icon(
                type == null ? Icons.grid_view_rounded : eventIcon(type),
                color: Anju.green,
              ),
              title: Text(type == null ? '全部类型' : eventTypeLabel(type)),
              trailing: _type == type
                  ? const Icon(Icons.check_rounded, color: Anju.green)
                  : null,
              onTap: () {
                setState(() => _type = type);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
