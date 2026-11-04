import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'widgets.dart';

Map<String, dynamic>? _cachedManual;

Future<Map<String, dynamic>> loadManual() {
  final cached = _cachedManual;
  if (cached != null) return SynchronousFuture(cached);
  return rootBundle.loadString('assets/manual.json').then((text) {
    final data = jsonDecode(text) as Map<String, dynamic>;
    _cachedManual = data;
    return data;
  });
}

/// The same offline content is exported as the delivered HTML/Markdown manual.
class ManualScreen extends StatefulWidget {
  const ManualScreen({super.key});
  @override
  State<ManualScreen> createState() => _ManualScreenState();
}

class _ManualScreenState extends State<ManualScreen> {
  late final Future<Map<String, dynamic>> _manual;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _manual = loadManual();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('完整使用手册')),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _manual,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const EmptyState(
                  title: '手册暂时无法读取',
                  message: '请重新打开本页面。',
                );
              }
              final data = snapshot.data;
              if (data == null)
                return const Center(child: CircularProgressIndicator());
              final chapters = (data['chapters'] as List)
                  .cast<Map<String, dynamic>>();
              final matches = chapters
                  .where(
                    (chapter) => jsonEncode(
                      chapter,
                    ).toLowerCase().contains(_query.trim().toLowerCase()),
                  )
                  .toList();
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        hintText: '搜索功能、摄像头或连接问题',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      children: [
                        const InfoBanner(
                          '安居视界 v1.2.2 · 全部章节离线可读。点击章节展开；搜索可筛选相关章节。',
                        ),
                        const SizedBox(height: 12),
                        if (matches.isEmpty)
                          const EmptyState(
                            title: '没有匹配章节',
                            message: '试试“视频”“绑定”“地址”或“通知”。',
                          ),
                        for (final chapter in matches)
                          Card(
                            child: ExpansionTile(
                              key: ValueKey(
                                '${chapter['id']}|${_query.trim()}',
                              ),
                              initiallyExpanded: _query.trim().isNotEmpty,
                              title: Text(
                                '${chapter['id']}  ${chapter['title']}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                18,
                                0,
                                18,
                                18,
                              ),
                              expandedCrossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                for (final raw
                                    in chapter['sections'] as List) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    raw['title'] as String,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Anju.green,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  for (final paragraph
                                      in raw['paragraphs'] as List)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: SelectableText(
                                        paragraph as String,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          height: 1.75,
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
