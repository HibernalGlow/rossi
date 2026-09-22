part of '../file_manager_card_test.dart';
// 打点与

/// 主页不再是独立的 IconButton，而是导航掌里的一片多边形热区。
///
/// 它没有自己的图标（可见的只是底部一道横杠），所以按 Tooltip 文案找；
/// 而它的**矩形是整只掌**，中心被刷新圆键占着 —— 想点到「下区」必须
/// 自己算一个落在梯形里的点，直接 `tester.tap(finder)` 会点到刷新。
Finder _homeRegion() => find.byWidgetPredicate(
  (widget) => widget is Tooltip && (widget.message ?? '').startsWith('主页'),
);


/// 主页热区（掌形下部的梯形）里的一个点：宽度的中间、高度的 85%。
Offset _homeRegionPoint(WidgetTester tester) {
  final rect = tester.getRect(_homeRegion());
  return Offset(rect.center.dx, rect.top + rect.height * 0.85);
}


Future<void> _tapHomeRegion(WidgetTester tester) async {
  final target = _homeRegion();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tapAt(_homeRegionPoint(tester));
  await tester.pumpAndSettle();
}


Future<void> _longPressHomeRegion(WidgetTester tester) async {
  final target = _homeRegion();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.longPressAt(_homeRegionPoint(tester));
  await tester.pumpAndSettle();
}


/// 掌形里某个方向的落点：把归一化坐标映射到掌的矩形上。
Offset _padPoint(WidgetTester tester, Offset normalized) {
  final rect = tester.getRect(find.byType(FileManagerNavigationPad));
  return Offset(
    rect.left + rect.width * normalized.dx,
    rect.top + rect.height * normalized.dy,
  );
}


Future<GlobalSettingCubit> _pumpCard(
  WidgetTester tester, {
  double width = 340,
  GlobalSettingCubit? settings,
}) async {
  tester.view.physicalSize = const Size(1000, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cubit = settings ?? _TestGlobalSettingCubit();
  await tester.pumpWidget(
    BlocProvider<GlobalSettingCubit>.value(
      value: cubit,
      child: MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: FileManagerCard(isExpanded: true, onToggle: () {}),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}


/// 工具栏横向滚动，窄卡片下「文件树」那颗按钮先要滚进视口才点得到。
Future<void> _openTree(WidgetTester tester) async {
  final toggle = find.byTooltip('文件树');
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}
