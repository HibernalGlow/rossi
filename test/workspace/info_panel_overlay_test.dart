// 叠加信息面板的最小行为判据：
//
//   1. **右缘悬停揭示**：指针进右缘 18px 带 ⇒ 面板滑入视口；离开 ⇒ 延时滑出；
//   2. **钉住 = 常开**：钉住后指针离开不再收起；
//   3. **关闭按钮**：把钉住与悬停两个来源一起收掉；
//   4. 面板里住的是信息面板注册的那五张卡（成员关系只有一处可改）。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/workspace/info_panel_overlay_test.dart
//
// （与其余工作台判据同一条理由：必须解掉沙箱代理，否则 flutter_tester 的
//   WebSocket 握手被劫持。）
//
// 这里不搭 `WorkspaceReaderHost`：真实阅读器要 ObjectBox 与图源注册表，
// 而叠加层的显示规则只依赖 `WorkspaceCubit` 与指针位置 —— 内容给个替身即可。
//
// **为什么断言的是几何而不是「在不在树上」**：隐藏态的面板只是被 `AnimatedPositioned`
// 推到视口外（收起动画与 `IgnorePointer` 都要求子树留在树上），所以
// `findsNothing` 那种写法测的是实现细节；「标题的左缘落在视口里/外」才是用户看到的。
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/widgets/panels/info_panel_overlay.dart';

const double kLaneWidth = 900;

Future<WorkspaceCubit> _pumpOverlay(WidgetTester tester) async {
  tester.view.physicalSize = const Size(kLaneWidth, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final cubit = WorkspaceCubit();
  addTearDown(cubit.close);

  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<WorkspaceCubit>.value(
        value: cubit,
        child: const Scaffold(
          body: InfoPanelOverlay(
            child: ColoredBox(color: Colors.blueGrey),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

/// 面板当前是否**在视口里**：拿标题栏「信息」两个字的左缘判。
/// 滑出态它的 dx 落在视口右侧之外（`right: -(width + 16)`）。
bool _panelInViewport(WidgetTester tester) {
  final found = find.text('信息');
  if (found.evaluate().isEmpty) return false;
  return tester.getTopLeft(found).dx < kLaneWidth;
}

void main() {
  // 指针一律用**鼠标**手势驱动 —— `MouseRegion` 只认 hover 序列，
  // 默认的测试手势是触摸指针，喂进去什么也不会发生。
  testWidgets('右缘悬停揭示信息面板，离开后延时收起', (tester) async {
    await _pumpOverlay(tester);
    expect(_panelInViewport(tester), isFalse, reason: '前置：初始是隐藏的');

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(10, 10));
    addTearDown(gesture.removePointer);

    // 进右缘触发带（视口宽 900，触发带占最后 18px）。
    await gesture.moveTo(const Offset(kLaneWidth - 8, 300));
    await tester.pumpAndSettle();
    expect(_panelInViewport(tester), isTrue, reason: '悬停揭示');
    // 五张信息卡都在（成员关系来自注册表，判据不复写清单）。
    expect(find.text('书籍信息'), findsOneWidget);
    expect(find.text('图像信息'), findsOneWidget);
    expect(find.text('存储信息'), findsOneWidget);
    expect(find.text('时间信息'), findsOneWidget);
    expect(find.text('预加载状态'), findsOneWidget);

    // 离开触发带 ⇒ 延时收起（收起动作发生在 hideDelay 之后）。
    await gesture.moveTo(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(_panelInViewport(tester), isFalse, reason: '未钉住 ⇒ 离开后收起');
  });

  testWidgets('钉住后面板常开，关闭按钮把两个来源一起收掉', (tester) async {
    final cubit = await _pumpOverlay(tester);

    cubit.setInfoPanelPinned(true);
    await tester.pumpAndSettle();
    expect(_panelInViewport(tester), isTrue);

    // 钉住时指针在哪儿都不该收它。
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(10, 10));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(const Offset(400, 400));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(_panelInViewport(tester), isTrue, reason: '钉住 = 常开');
    expect(cubit.state.infoPanelPinned, isTrue);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(_panelInViewport(tester), isFalse);
    expect(
      cubit.state.infoPanelPinned,
      isFalse,
      reason: '关闭按钮同时取消钉住（否则它会在下一次构建里自己弹回来）',
    );
  });

  testWidgets('Reader 独占 / 全屏时右缘感应带让位给泳道边缘揭示', (tester) async {
    final cubit = await _pumpOverlay(tester);

    cubit.toggleSoloLane(LaneId.reader);
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(10, 10));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(const Offset(kLaneWidth - 8, 300));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(
      _panelInViewport(tester),
      isFalse,
      reason: '独占时右缘归「揭示相邻泳道」，叠加层不该抢这块触发带',
    );
  });
}
