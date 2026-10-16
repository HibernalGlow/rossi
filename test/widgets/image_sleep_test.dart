import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/search/model/plugin_search_history_store.dart';

import 'package:zephyr/widgets/image_sleep.dart';
import 'package:zephyr/workspace/model/workspace_presence.dart';

class _MemorySettings extends GlobalSettingCubit {
  @override
  void updateState(GlobalSettingState Function(GlobalSettingState) updates) =>
      emit(updates(state));
}

Widget _host({required bool? asleep, required Widget child}) {
  Widget inner = child;
  if (asleep != null) {
    inner = WorkspaceImageSleepScope(asleep: asleep, child: inner);
  }
  return MaterialApp(
    home: Scaffold(body: Builder(builder: (context) => inner)),
  );
}

void main() {
  tearDown(() => WorkspacePresence.present.value = false);

  group('resolveImageSleep（纯函数判据）', () {
    test('scope 清醒 → 永不休眠（哪怕开关开着）', () {
      expect(
        resolveImageSleep(scopeAsleep: false, settingEnabled: true),
        isFalse,
      );
    });

    test('scope 声明休眠 + 开关开 → 休眠', () {
      expect(
        resolveImageSleep(scopeAsleep: true, settingEnabled: true),
        isTrue,
      );
    });

    test('scope 声明休眠 + 开关关 → 不休眠（用户约定：功能要可关）', () {
      expect(
        resolveImageSleep(scopeAsleep: true, settingEnabled: false),
        isFalse,
      );
    });
  });

  group('WorkspaceImageSleepScope / ImageSleep（widget 判据）', () {
    const marker = Key('marker');
    final placeholderFinder = find.descendant(
      of: find.byType(ImageSleep),
      matching: find.byType(ColoredBox),
    );

    for (final scope in <bool?>[null, false]) {
      testWidgets('scope=$scope 默认路径无需数据库或设置 provider', (tester) async {
        await tester.pumpWidget(
          _host(
            asleep: scope,
            child: const ImageSleep(child: SizedBox(key: marker)),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(marker), findsOneWidget);
      });
    }

    testWidgets('休眠只监听开关，搜索历史变化不重建占位，开关可即时恢复', (tester) async {
      final settings = _MemorySettings();
      addTearDown(settings.close);
      await tester.pumpWidget(
        BlocProvider<GlobalSettingCubit>.value(
          value: settings,
          child: _host(
            asleep: true,
            child: const ImageSleep(child: SizedBox(key: marker)),
          ),
        ),
      );
      expect(find.byKey(marker), findsNothing);
      final placeholder = tester.widget<ColoredBox>(placeholderFinder);
      await PluginSearchHistoryStore(settings, 'plugin').record('tag:artist');
      await tester.pump();
      expect(tester.widget<ColoredBox>(placeholderFinder), same(placeholder));
      settings.updateState(
        (state) => state.copyWith(workspaceSleepCoveredUi: false),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(marker), findsOneWidget);
      settings.updateState(
        (state) => state.copyWith(workspaceSleepCoveredUi: true),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(marker), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('scope 睡 + 开关开 → 内容被占位替换（live image 释放的前提）', (tester) async {
      await tester.pumpWidget(
        _host(
          asleep: true,
          child: ImageSleep(enabled: true, child: Container(key: marker)),
        ),
      );
      expect(find.byKey(marker), findsNothing);
      expect(placeholderFinder, findsOneWidget);
    });

    testWidgets('scope 清醒 → 内容照常渲染', (tester) async {
      await tester.pumpWidget(
        _host(
          asleep: false,
          child: ImageSleep(enabled: true, child: Container(key: marker)),
        ),
      );
      expect(find.byKey(marker), findsOneWidget);
    });

    testWidgets('无 scope（工作台内嵌页 / 根栈其他页）→ 永远清醒', (tester) async {
      await tester.pumpWidget(
        _host(
          asleep: null,
          child: ImageSleep(enabled: true, child: Container(key: marker)),
        ),
      );
      expect(find.byKey(marker), findsOneWidget);
    });

    testWidgets('scope 翻转（进/退工作台）→ 占位与内容跟着换回来', (tester) async {
      var asleep = true;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _host(
            asleep: asleep,
            child: ImageSleep(enabled: true, child: Container(key: marker)),
          ),
        ),
      );
      expect(find.byKey(marker), findsNothing);

      // 退工作台：scope 翻醒。
      asleep = false;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _host(
            asleep: asleep,
            child: ImageSleep(enabled: true, child: Container(key: marker)),
          ),
        ),
      );
      expect(find.byKey(marker), findsOneWidget);
    });

    testWidgets('WorkspacePresence 默认不在场（进工作台前无任何休眠）', (tester) async {
      expect(WorkspacePresence.present.value, isFalse);
      await tester.pumpWidget(
        _host(
          asleep: WorkspacePresence.present.value,
          child: ImageSleep(enabled: true, child: Container(key: marker)),
        ),
      );
      expect(find.byKey(marker), findsOneWidget);
    });
  });
}
