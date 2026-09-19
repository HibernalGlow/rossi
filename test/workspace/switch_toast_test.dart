// 「切换提示」（N-17）的运行时与卡片判据。
//
// 差分与去重语义对照上游 `ReaderSwitchToastRuntime.tsx`（previousRef 差分）
// 与 `ReaderSwitchToastStore.ts` 的 `show`（同文 500ms 去重、全空即丢弃）。
// 模板引擎本身的逐条对照判据在 `switch_toast_template_test.dart`。

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_read/json/common_ep_info_json/common_ep_info_json.dart';
import 'package:zephyr/page/comic_read/model/normal_comic_ep_info.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/service/reader/switch_toast_service.dart';
import 'package:zephyr/workspace/widgets/cards/switch_toast_card.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/widgets/toast/toast_overlay.dart';

/// 不落盘的设置更新（objectbox 在判据里不存在）。
class _InMemoryGlobalSettingCubit extends GlobalSettingCubit {
  @override
  void updateSwitchToastSetting(
    SwitchToastSettingState Function(SwitchToastSettingState current) updates,
  ) {
    emit(
      state.copyWith(switchToastSetting: updates(state.switchToastSetting)),
    );
  }
}

/// 收 eventBus 上的 [ToastEvent]（服务层没有 context，走的就是这条路）。
class _InMemoryEvents {
  _InMemoryEvents() {
    // 订阅必须在构造时**真的建立**：`late final` 的初始化器只在首次读取时才跑，
    // 而这里直到 dispose 才会读到它 —— 那之前事件全部漏听。
    _sub = eventBus.on<ToastEvent>().listen(received.add);
  }

  SwitchToastSettingState settings = const SwitchToastSettingState();
  final List<ToastEvent> received = [];
  late final StreamSubscription<ToastEvent> _sub;

  Future<void> pump() async {
    await Future<void>.delayed(Duration.zero);
  }

  void dispose() {
    _sub.cancel();
  }
}

void main() {
  group('运行时（对照 Runtime 差分 + Store 去重）', () {
    late _InMemoryEvents events;

    setUp(() {
      events = _InMemoryEvents();
      SwitchToastService.instance.settingsSourceOverride = () =>
          events.settings;
      SwitchToastService.instance.resetForTest();
      SwitchToastService.instance.start();
    });

    tearDown(() {
      ReaderSessionCoordinator.instance.detachSession('b1');
      SwitchToastService.instance.resetForTest();
      SwitchToastService.instance.settingsSourceOverride = null;
      events.dispose();
    });

    void attach({int slot = 2}) {
      ReaderSessionCoordinator.instance.attachSession(
        comicId: 'b1',
        from: 'test',
        title: 'Demo',
        epInfo: NormalComicEpInfo(
          epName: '第 1 话',
          docs: const [
            Doc(originalName: '001.jpg', path: 'p1', fileServer: 's', id: '1'),
            Doc(originalName: '002.jpg', path: 'p2', fileServer: 's', id: '2'),
            Doc(originalName: '003.jpg', path: 'p3', fileServer: 's', id: '3'),
            Doc(originalName: '004.jpg', path: 'p4', fileServer: 's', id: '4'),
          ],
        ),
        currentSlot: slot,
        totalSlots: 4,
        jumpToSlot: (_) async {},
      );
    }

    test('开关联动：都没开时什么都不弹', () async {
      attach();
      await events.pump();
      expect(events.received, isEmpty);
    });

    test('首次进入一本书弹书籍提示（上游同款：attach 即 book 变更）', () async {
      events.settings = const SwitchToastSettingState(enableBook: true);
      attach();
      await events.pump();
      expect(events.received, hasLength(1));
      expect(events.received.single.title, '已切换到 Demo（第 3 / 4 页）');
      // 本地来源为空 → 上游同款：路径模板仍渲染出「路径：」前缀（变量为空串）。
      expect(events.received.single.message, '路径：');
    });

    test('翻页弹页面提示；切书不重复弹', () async {
      events.settings = const SwitchToastSettingState(
        enableBook: true,
        enablePage: true,
      );
      attach();
      await events.pump();
      ReaderSessionCoordinator.instance.updateProgress(
        currentSlot: 3,
        totalSlots: 4,
      );
      await events.pump();
      expect(events.received, hasLength(2));
      expect(events.received.last.title, '第 4 / 4 页');
      expect(events.received.last.message, '004.jpg');
    });

    test('只开页面开关时切书不弹', () async {
      events.settings = const SwitchToastSettingState(enablePage: true);
      attach();
      await events.pump();
      expect(events.received, isEmpty);
    });

    test('同一条提示 500ms 内只弹一次（上游 Store 同款去重）', () async {
      events.settings = const SwitchToastSettingState(enableBook: true);
      attach();
      await events.pump();
      // 关掉再原地重开同一本书：标题完全相同，落在去重窗口内。
      ReaderSessionCoordinator.instance.detachSession('b1');
      attach();
      await events.pump();
      expect(events.received, hasLength(1));
    });

    test('两本模板都清空时不弹（上游同款：全空即丢弃）', () async {
      events.settings = const SwitchToastSettingState(
        enableBook: true,
        bookTitleTemplate: '',
        bookDescriptionTemplate: '',
      );
      attach();
      await events.pump();
      expect(events.received, isEmpty);
    });
  });

  group('切换提示卡片', () {
    late _InMemoryGlobalSettingCubit cubit;

    Widget host(Widget child) {
      return BlocProvider<GlobalSettingCubit>.value(
        value: cubit,
        child: MaterialApp(
          home: Scaffold(
            // 真实宿主（面板/泳道）里卡片住在滚动视图内：判据给同样的交叉轴，
            // 否则长内容在固定高度盒里直接炸 RenderFlex。
            body: SizedBox(
              width: 380,
              height: 700,
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      );
    }

    setUp(() {
      cubit = _InMemoryGlobalSettingCubit();
      ToastOverlayController.instance.resetForTest();
    });

    tearDown(() {
      ToastOverlayController.instance.resetForTest();
    });

    testWidgets('渲染四要素：触发开关、两本模板、变量表、测试按钮', (tester) async {
      await tester.pumpWidget(
        host(const SwitchToastCard(isExpanded: true, onToggle: _noop)),
      );
      await tester.pumpAndSettle();

      expect(find.text('触发条件'), findsOneWidget);
      expect(find.text('切换书籍时显示提示'), findsOneWidget);
      expect(find.text('切换页面时显示提示'), findsOneWidget);
      expect(find.text('书籍提示模板'), findsOneWidget);
      expect(find.text('页面提示模板'), findsOneWidget);
      expect(find.text('{{book.displayName}}'), findsWidgets);
      expect(find.text('{{page.indexDisplay}}'), findsWidgets);
      expect(find.text('显示测试提示'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('拨动开关写回设置（经 cubit，不是局部 State）', (tester) async {
      await tester.pumpWidget(
        host(const SwitchToastCard(isExpanded: true, onToggle: _noop)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('切换书籍时显示提示'));
      await tester.pumpAndSettle();
      expect(cubit.state.switchToastSetting.enableBook, isTrue);

      await tester.tap(find.text('切换页面时显示提示'));
      await tester.pumpAndSettle();
      expect(cubit.state.switchToastSetting.enablePage, isTrue);
    });

    testWidgets('测试按钮真的把提示弹到屏上（防「静默失效」）', (tester) async {
      await tester.pumpWidget(
        host(const SwitchToastCard(isExpanded: true, onToggle: _noop)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('显示测试提示'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('切换提示测试'), findsOneWidget);
      expect(find.text('这是一条切换提示的预览'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });
}

void _noop() {}
