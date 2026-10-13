import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/type/breadcrumb_style.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/navigation/path_breadcrumb.dart';

class _Routes extends NavigatorObserver {
  Route<dynamic>? last;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      last = route;
}

const entries = [
  PathCrumb(id: '/', label: '/', isRoot: true),
  PathCrumb(id: '/Library', label: 'Library'),
  PathCrumb(id: '/Library/Comics', label: 'Comics'),
  PathCrumb(id: '/Library/Comics/Arknights', label: 'Arknights'),
  PathCrumb(
    id: '/Library/Comics/Arknights/Endfield',
    label: 'Endfield',
    isCurrent: true,
  ),
];

void main() {
  Widget subject({
    required BreadcrumbStyle style,
    double width = 780,
    double textScale = 1,
    bool enabled = true,
    bool reduced = false,
    TextDirection direction = TextDirection.ltr,
    ValueChanged<PathCrumb>? onSelected,
    NavigatorObserver? observer,
    List<PathCrumb> path = entries,
  }) => MaterialApp(
    navigatorObservers: [?observer],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduced,
      ),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: PathBreadcrumb(
            entries: path,
            style: style,
            enabled: enabled,
            overflowLabel: '展开上级路径',
            itemKey: (entry) => ValueKey(entry.id),
            onSelected: onSelected ?? (_) {},
            trailing: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.expand_more),
            ),
          ),
        ),
      ),
    ),
  );

  for (final style in BreadcrumbStyle.values) {
    testWidgets('$style 路径跳转与当前项回调', (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(
        subject(style: style, onSelected: (entry) => selected.add(entry.id)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('/Library/Comics')));
      await tester.tap(find.text('Endfield'));
      expect(selected, ['/Library/Comics', entries.last.id]);
      expect(
        tester.getSize(find.byKey(const ValueKey('/'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('$style 长路径保留首尾、祖先经统一弹层可达', (tester) async {
      final observer = _Routes();
      final selected = <String>[];
      await tester.pumpWidget(
        subject(
          style: style,
          width: 280,
          observer: observer,
          onSelected: (entry) => selected.add(entry.id),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('/')), findsOneWidget);
      expect(find.text('Endfield'), findsOneWidget);
      expect(find.text('Library'), findsNothing);
      await tester.tap(find.byTooltip('展开上级路径'));
      await tester.pumpAndSettle();
      expect(observer.last, isA<CommonPopupRoute>());
      await tester.tap(find.text('Comics'));
      await tester.pumpAndSettle();
      expect(selected, ['/Library/Comics']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$style 大字号窄面板与超长单目录不溢出', (tester) async {
      for (final direction in TextDirection.values) {
        await tester.pumpWidget(
          subject(
            style: style,
            width: 240,
            textScale: 2,
            direction: direction,
            path: [
              entries.first,
              PathCrumb(
                id: '/very-long',
                label: '非常长的目录名称 ' * 15,
                isCurrent: true,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final row = tester.getRect(find.byType(PathBreadcrumb));
        for (final id in ['/', '/very-long']) {
          final rect = tester.getRect(find.byKey(ValueKey(id)));
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.left, greaterThanOrEqualTo(row.left));
          expect(rect.right, lessThanOrEqualTo(row.right));
        }
      }
    });

    testWidgets('$style 禁用时没有路径操作', (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(
        subject(
          style: style,
          enabled: false,
          onSelected: (entry) => selected.add(entry.id),
        ),
      );
      await tester.tap(find.text('Endfield'));
      expect(selected, isEmpty);
    });
  }

  testWidgets('悬停高亮连续移动，减少动画时直接到目标', (tester) async {
    await tester.pumpWidget(
      subject(style: BreadcrumbStyle.expressive, reduced: true),
    );
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(
      tester.getCenter(find.byKey(const ValueKey('/Library'))),
    );
    await tester.pump();
    ActionBubblePainter painter() =>
        tester
                .widget<CustomPaint>(
                  find
                      .descendant(
                        of: find.byType(ActionBubbleRegion),
                        matching: find.byWidgetPredicate(
                          (widget) =>
                              widget is CustomPaint &&
                              widget.foregroundPainter is ActionBubblePainter,
                        ),
                      )
                      .first,
                )
                .foregroundPainter!
            as ActionBubblePainter;
    final first = painter().rect();
    await pointer.moveTo(
      tester.getCenter(find.byKey(const ValueKey('/Library/Comics'))),
    );
    await tester.pump();
    expect(painter().rect().left, greaterThan(first.left));
    expect(painter().alpha(), 1);
    await pointer.removePointer();
  });

  test('旧设置和未来未知样式降级为克制型，两种样式都能往返序列化', () {
    expect(
      FileManagerSettingState.fromJson({}).breadcrumbStyle,
      BreadcrumbStyle.restrained,
    );
    expect(
      FileManagerSettingState.fromJson({
        'breadcrumbStyle': 'future',
      }).breadcrumbStyle,
      BreadcrumbStyle.restrained,
    );
    for (final style in BreadcrumbStyle.values) {
      final source = FileManagerSettingState(breadcrumbStyle: style);
      expect(
        FileManagerSettingState.fromJson(source.toJson()).breadcrumbStyle,
        style,
      );
    }
  });
}
