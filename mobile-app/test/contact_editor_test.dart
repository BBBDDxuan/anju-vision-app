import 'dart:async';

import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/models/household.dart';
import 'package:elder_safety_mobile/models/models.dart';
import 'package:elder_safety_mobile/ui/settings_screen.dart';
import 'package:elder_safety_mobile/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _primary = ValueKey('primary-contact-name');
const _backup = ValueKey('backup-contact-name');
const _seconds = ValueKey('contact-reminder-seconds');

class _DelayedStore extends MemorySettingsStore {
  Completer<void>? pending;
  int saves = 0;

  @override
  Future<void> saveHousehold(HouseholdData data) async {
    saves++;
    await pending?.future;
    await super.saveHousehold(data);
  }
}

SafetyController _controller(MemorySettingsStore store, {int seconds = 60}) {
  final controller = SafetyController(
    store: store,
    videoApiFactory: emptyVideoApi,
  );
  controller.preferences = FamilyPreferences(
    escalationSeconds: seconds,
    notificationsEnabled: false,
    contacts: const [
      FamilyContact(id: 'primary', name: '李华'),
      FamilyContact(id: 'backup', name: '王芳'),
    ],
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _openEditor(
  WidgetTester tester,
  SafetyController controller, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: Anju.theme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              showDragHandle: true,
              builder: (context) => AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SafeArea(
                  top: false,
                  child: ContactsEditor(controller: controller),
                ),
              ),
            ),
            child: const Text('打开联系人'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('打开联系人'));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, Key key, String value) async {
  final field = find.byKey(key);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

ChoiceChip _chip(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

void main() {
  for (final preset in {30: '30秒', 60: '1分钟', 180: '3分钟'}.entries) {
    testWidgets(
      '${preset.value} saves integer seconds and stable contact IDs',
      (tester) async {
        final store = MemorySettingsStore();
        final controller = _controller(store);
        await _openEditor(tester, controller);
        expect(find.text('备用联系人提醒延迟'), findsOneWidget);
        expect(find.text('未回应升级等待（秒）'), findsNothing);
        expect(_chip(tester, '1分钟').selected, isTrue);
        expect(find.byKey(_seconds), findsNothing);
        expect(find.textContaining('重要提醒'), findsOneWidget);
        await _enter(tester, _primary, '  张敏  ');
        await _enter(tester, _backup, '  陈明  ');
        await _tap(tester, find.text(preset.value));
        expect(_chip(tester, preset.value).selected, isTrue);
        await _tap(tester, find.text('保存联系人'));

        final saved = store.householdData!.familyPreferences;
        expect(saved.escalationSeconds, preset.key);
        expect(saved.contacts.map((contact) => contact.id), [
          'primary',
          'backup',
        ]);
        expect(saved.contacts.map((contact) => contact.name), ['张敏', '陈明']);
        expect(saved.notificationsEnabled, isFalse);
        expect(controller.preferences.toJson(), saved.toJson());
        expect(find.byType(ContactsEditor), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'existing custom delay survives switching presets and reopening',
    (tester) async {
      final store = MemorySettingsStore();
      final controller = _controller(store, seconds: 75);
      await _openEditor(tester, controller);
      expect(_chip(tester, '自定义').selected, isTrue);
      expect(
        tester.widget<TextField>(find.byKey(_seconds)).controller!.text,
        '75',
      );
      await _enter(tester, _seconds, ' 95 ');
      await _tap(tester, find.text('30秒'));
      expect(find.byKey(_seconds), findsNothing);
      await _tap(tester, find.text('自定义'));
      expect(
        tester.widget<TextField>(find.byKey(_seconds)).controller!.text,
        ' 95 ',
      );
      await _tap(tester, find.text('保存联系人'));
      expect(store.householdData!.familyPreferences.escalationSeconds, 95);
      await _tap(tester, find.text('打开联系人'));
      expect(_chip(tester, '自定义').selected, isTrue);
      expect(
        tester.widget<TextField>(find.byKey(_seconds)).controller!.text,
        '95',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final seconds in [5, 86400]) {
    testWidgets('custom delay accepts boundary $seconds seconds', (
      tester,
    ) async {
      final store = MemorySettingsStore();
      final controller = _controller(store);
      await _openEditor(tester, controller);
      await _tap(tester, find.text('自定义'));
      await _enter(tester, _seconds, '$seconds');
      await _tap(tester, find.text('保存联系人'));
      expect(store.householdData!.familyPreferences.escalationSeconds, seconds);
      expect(find.byType(ContactsEditor), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid custom delays cannot save or dismiss the editor', (
    tester,
  ) async {
    final store = MemorySettingsStore();
    final controller = _controller(store);
    await _openEditor(tester, controller);
    await _tap(tester, find.text('自定义'));
    for (final value in ['', '4', '86401', '1.5', 'abc']) {
      await _enter(tester, _seconds, value);
      await _tap(tester, find.text('保存联系人'));
      expect(find.text('备用联系人提醒延迟需为 5–86400 整数秒'), findsOneWidget);
      expect(find.byType(ContactsEditor), findsOneWidget);
      expect(store.householdData, isNull);
      expect(controller.preferences.escalationSeconds, 60);
    }
    // A valid preset supersedes an invalid custom value.
    await _tap(tester, find.text('3分钟'));
    await _tap(tester, find.text('保存联系人'));
    expect(store.householdData!.familyPreferences.escalationSeconds, 180);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both contact names require 1 to 80 trimmed characters', (
    tester,
  ) async {
    final store = MemorySettingsStore();
    final controller = _controller(store);
    await _openEditor(tester, controller);
    for (final field in [_primary, _backup]) {
      for (final value in ['   ', List.filled(81, '李').join()]) {
        await _enter(tester, field, value);
        await _tap(tester, find.text('保存联系人'));
        expect(find.text('联系人姓名请填写 1–80 个字'), findsOneWidget);
        expect(store.householdData, isNull);
      }
      await _enter(tester, field, List.filled(80, '李').join());
    }
    await _tap(tester, find.text('保存联系人'));
    expect(
      store.householdData!.familyPreferences.contacts.first.name.length,
      80,
    );
    expect(
      store.householdData!.familyPreferences.contacts.last.name.length,
      80,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'async failure preserves edits, unlocks controls and allows retry',
    (tester) async {
      final store = _DelayedStore()..pending = Completer<void>();
      final controller = _controller(store);
      await _openEditor(tester, controller);
      await _enter(tester, _primary, '赵丽');
      await _tap(tester, find.text('自定义'));
      await _enter(tester, _seconds, '120');
      await tester.ensureVisible(find.text('保存联系人'));
      final save = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .onPressed!;
      save();
      save();
      await tester.pumpAndSettle();
      expect(store.saves, 1);
      expect(find.text('正在保存…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.enabled, isFalse);
      }
      for (final chip in tester.widgetList<ChoiceChip>(
        find.byType(ChoiceChip),
      )) {
        expect(chip.onSelected, isNull);
      }

      store.failHouseholdSave = true;
      store.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('档案保存失败'), findsOneWidget);
      expect(find.byType(ContactsEditor), findsOneWidget);
      expect(controller.preferences.contactName('primary'), '李华');
      expect(
        tester.widget<TextField>(find.byKey(_primary)).controller!.text,
        '赵丽',
      );
      expect(
        tester.widget<TextField>(find.byKey(_seconds)).controller!.text,
        '120',
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(tester.widget<TextField>(find.byKey(_primary)).enabled, isTrue);
      expect(_chip(tester, '30秒').onSelected, isNotNull);

      store.failHouseholdSave = false;
      store.pending = null;
      await _tap(tester, find.text('保存联系人'));
      expect(store.saves, 2);
      expect(
        store.householdData!.familyPreferences.contactName('primary'),
        '赵丽',
      );
      expect(store.householdData!.familyPreferences.escalationSeconds, 120);
      expect(find.byType(ContactsEditor), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dismissing while saving does not update a disposed editor', (
    tester,
  ) async {
    final store = _DelayedStore()..pending = Completer<void>();
    final controller = _controller(store);
    await _openEditor(tester, controller);
    await _tap(tester, find.text('保存联系人'));
    tester
        .state<ContactsEditorState>(find.byType(ContactsEditor))
        .context
        .findAncestorStateOfType<NavigatorState>()!
        .pop();
    await tester.pumpAndSettle();
    store.failHouseholdSave = true;
    store.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ContactsEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px layout supports large text, keyboard and validation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final store = MemorySettingsStore();
    final controller = _controller(store);
    await _openEditor(tester, controller, textScale: 2);
    expect(tester.takeException(), isNull);
    await _tap(tester, find.text('自定义'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    await tester.pumpAndSettle();
    await _enter(tester, _seconds, '4');
    await _tap(tester, find.text('保存联系人'));
    expect(find.text('备用联系人提醒延迟需为 5–86400 整数秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _enter(tester, _seconds, '300');
    await _tap(tester, find.text('保存联系人'));
    expect(store.householdData!.familyPreferences.escalationSeconds, 300);
    expect(find.byType(ContactsEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
