import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/controls/slider.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';

/// 直接 emit 预设 state，不走 updateReadSetting（后者会写 ObjectBox，
/// Windows 下 `flutter test` 缺 objectbox.dll 跑不起来）。
Widget _harness({
  required GlobalSettingCubit globalCubit,
  required ComicReadPreferenceCubit preferenceCubit,
  required ReaderCubit readerCubit,
  ValueChanged<int>? onJumpToSlot,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider.value(value: globalCubit),
      BlocProvider.value(value: preferenceCubit),
      BlocProvider.value(value: readerCubit),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            SliderWidget(onJumpToSlot: onJumpToSlot),
          ],
        ),
      ),
    ),
  );
}

/// 最靠近 Slider 的 Directionality：LTR 时是 MaterialApp 自带的，
/// RTL 时是我们包的那层。
TextDirection _sliderDirection(WidgetTester tester) {
  Directionality? nearest;
  tester.element(find.byType(Slider)).visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is Directionality) {
      nearest = widget;
      return false;
    }
    return true;
  });
  return nearest!.textDirection;
}

Future<ReaderCubit> _pumpHarness(
  WidgetTester tester, {
  int readMode = kReadModeRowLtr,
  ValueChanged<int>? onJumpToSlot,
}) async {
  final globalCubit = GlobalSettingCubit();
  globalCubit.emit(
    globalCubit.state.copyWith(
      readSetting: globalCubit.state.readSetting.copyWith(readMode: readMode),
    ),
  );
  final readerCubit = ReaderCubit()
    ..updateTotalSlots(10)
    ..updateCurrentSlot(2);

  await tester.pumpWidget(
    _harness(
      globalCubit: globalCubit,
      preferenceCubit: ComicReadPreferenceCubit(),
      readerCubit: readerCubit,
      onJumpToSlot: onJumpToSlot,
    ),
  );
  await tester.pumpAndSettle();
  return readerCubit;
}

void main() {
  testWidgets('单页从左到右：滑杆方向为 ltr', (tester) async {
    await _pumpHarness(tester, readMode: kReadModeRowLtr);
    expect(_sliderDirection(tester), TextDirection.ltr);
  });

  testWidgets('单页从右到左：滑杆方向为 rtl', (tester) async {
    await _pumpHarness(tester, readMode: kReadModeRowRtl);
    expect(_sliderDirection(tester), TextDirection.rtl);
  });

  testWidgets('鼠标点完轨道后再动一下，待提交的跳页不能被取消', (tester) async {
    final committed = <int>[];
    final readerCubit = await _pumpHarness(
      tester,
      onJumpToSlot: committed.add,
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    final trackCenter = tester.getCenter(find.byType(Slider));
    await gesture.addPointer(location: trackCenter);
    await gesture.down(trackCenter);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    // 桌面端点完不可能手不动：指针仍在轨道上，再挪 6px 就会触发 onHover。
    await gesture.moveTo(trackCenter + const Offset(6, 0));
    await tester.pump(const Duration(milliseconds: 400));

    expect(committed, isNotEmpty, reason: '进度条动了，但页面一次都没跳');
    // 提交的目标必须就是滑块现在指着的那一页，否则就是「条与画面各说各话」。
    expect(
      committed.last,
      readerCubit.state.sliderValue.round(),
      reason: '跳页目标与滑块读数不一致',
    );
  });

  testWidgets('第一次 onChanged 就把 isSliderRolling 立起来', (tester) async {
    final readerCubit = await _pumpHarness(tester);

    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pump();

    // 防抖窗口里标记必须已经为真：否则这期间任何 onPageChanged 都会经
    // updateCurrentSlot 把滑块拽回画面当前那一页（表现为「点完又弹回去」）。
    expect(readerCubit.state.isSliderRolling, isTrue);
  });

  testWidgets('进度悬停连续更新保留同一浮层，退出先播统一收回动画', (tester) async {
    await _pumpHarness(tester);
    final track = tester.getCenter(find.byType(Slider));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(track);
    await mouse.moveTo(track + const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 80));
    final preview = find.byType(CommonPopupOverlayMotion);
    expect(preview, findsOneWidget);
    final retained = tester.state(preview);
    await mouse.moveTo(track + const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.state(preview), same(retained), reason: '不能每次 hover 重建并重启入场');
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(preview, findsOneWidget, reason: '退出不能瞬间移除托盘');
    expect(tester.widget<CommonPopupOverlayMotion>(preview).visible, isFalse);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(preview, findsNothing);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });
}
