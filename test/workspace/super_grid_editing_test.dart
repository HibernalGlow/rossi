import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/grid/card_resize_handle.dart';
import 'package:zephyr/workspace/widgets/grid/grid.dart';
import 'package:zephyr/workspace/widgets/grid/super_grid.dart';

const _cardKey = ValueKey<String>('statistics-card');
const _secondKey = ValueKey<String>('second-card');
const _bodyKey = ValueKey<String>('statistics-body');

class _EditingFixture extends StatefulWidget {
  const _EditingFixture({
    required this.width,
    this.initiallyEditing = false,
    this.twoCards = false,
    this.fullWidthCards = true,
    this.scrollable = false,
    this.reduceMotion = false,
  });
  final double width;
  final bool initiallyEditing;
  final bool twoCards;
  final bool fullWidthCards;
  final bool scrollable;
  final bool reduceMotion;

  @override
  State<_EditingFixture> createState() => _EditingFixtureState();
}

class _EditingFixtureState extends State<_EditingFixture> {
  late bool editing = widget.initiallyEditing;
  int widthSpan = 2;
  int heightSpan = 1;
  int resizeCount = 0;
  int removeCount = 0;
  int reorderCount = 0;
  int contentBuilds = 0;
  bool expanded = true;
  List<Key> order = [_cardKey, _secondKey];
  final horizontal = ScrollController();
  final vertical = ScrollController();
  late final content = Builder(
    builder: (_) {
      contentBuilds++;
      return const SizedBox(height: 32, child: Text('阅读统计内容'));
    },
  );

  @override
  void dispose() {
    horizontal.dispose();
    vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: widget.reduceMotion),
      child: ScrollConfiguration(
        behavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: child!,
      ),
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: widget.scrollable ? 480 : widget.width,
          child: SingleChildScrollView(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: widget.width,
              height: 540,
              child: Column(
                children: [
                  TextButton(
                    onPressed: () => setState(() => editing = !editing),
                    child: Text(editing ? '完成布局' : '自定义布局'),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: vertical,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          SuperGrid(
                            editing: editing,
                            crossAxisCount: 8,
                            onResizeCard: (key, width, height) {
                              expect(key, _cardKey);
                              setState(() {
                                widthSpan = width;
                                heightSpan = height;
                                resizeCount++;
                              });
                            },
                            onRemoveCard: (_) => removeCount++,
                            onChanged: (items) => setState(() {
                              order = items.map((item) => item.key!).toList();
                              reorderCount++;
                            }),
                            children: [
                              for (final key
                                  in widget.twoCards ? order : [_cardKey])
                                GridItem(
                                  key: key,
                                  crossAxisCellCount:
                                      widget.twoCards && widget.fullWidthCards
                                      ? 8
                                      : widthSpan * 2,
                                  logicalWidthSpan:
                                      widget.twoCards && widget.fullWidthCards
                                      ? 4
                                      : widthSpan,
                                  mainAxisCellCount: heightSpan,
                                  child: CollapsibleCard(
                                    cardId: key.toString(),
                                    key: key == _cardKey ? _bodyKey : null,
                                    margin: EdgeInsets.zero,
                                    title: key == _cardKey ? '阅读统计' : '第二张卡片',
                                    icon: AppGlyphs.gridPlus,
                                    isExpanded: expanded,
                                    onToggle: () =>
                                        setState(() => expanded = !expanded),
                                    child: content,
                                  ),
                                ),
                            ],
                          ),
                          if (widget.scrollable) const SizedBox(height: 1200),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

_EditingFixtureState _fixture(WidgetTester tester) =>
    tester.state<_EditingFixtureState>(find.byType(_EditingFixture));

Future<void> _enterEditing(WidgetTester tester) async {
  await tester.tap(find.text('自定义布局'));
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('卡片布局').first);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [240.0, 640.0]) {
    testWidgets('统计卡片在宽度 $width 下可反复进入和退出布局编辑', (tester) async {
      await tester.pumpWidget(_EditingFixture(width: width));
      final originalWidth = tester.getSize(find.byKey(_bodyKey)).width;
      for (var cycle = 0; cycle < 3; cycle++) {
        await _enterEditing(tester);
        expect(find.text('阅读统计内容'), findsOneWidget);
        expect(find.byType(CardResizeHandle), findsOneWidget);
        expect(find.byTooltip('卡片布局'), findsOneWidget);
        expect(find.text('2×2'), findsNothing);
        expect(tester.getSize(find.byKey(_bodyKey)).width, originalWidth);
        final menu = tester.getRect(find.byTooltip('卡片布局'));
        final fold = tester.getRect(find.byTooltip('折叠阅读统计'));
        expect(menu.overlaps(fold), isFalse);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('完成布局'));
        await tester.pumpAndSettle();
        expect(find.byType(CardResizeHandle), findsNothing);
      }
    });
  }

  testWidgets('直接编辑态挂载及窄卡片菜单无递归，预设和收起可用', (tester) async {
    await tester.pumpWidget(
      const _EditingFixture(width: 240, initiallyEditing: true),
    );
    await _openMenu(tester);
    await tester.tap(find.text('2×2'));
    await tester.pumpAndSettle();
    expect(_fixture(tester).heightSpan, 2);
    final card = tester.getRect(find.byKey(_bodyKey));
    final grip = tester.getRect(find.byType(CardResizeHandle));
    expect(grip.bottom, closeTo(card.bottom, .1));
    expect(grip.right, lessThanOrEqualTo(card.right));
    await _openMenu(tester);
    await tester.tap(find.text('从该面板收起'));
    await tester.pumpAndSettle();
    expect(_fixture(tester).removeCount, 1);
    expect(tester.takeException(), isNull);
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('$kind 按下立即反馈，像素预览跟手，松开只保存一次且不滚动泳道', (tester) async {
      final haptics = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        const _EditingFixture(
          width: 640,
          initiallyEditing: true,
          scrollable: true,
        ),
      );
      final fixture = _fixture(tester);
      final original = tester.getSize(find.byKey(_bodyKey));
      final originalBuilds = fixture.contentBuilds;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CardResizeHandle)),
        kind: kind,
      );
      await tester.pump();
      expect(find.textContaining('松开保存'), findsOneWidget);
      final scale = tester.widget<AnimatedScale>(
        find.descendant(
          of: find.byType(CardResizeHandle),
          matching: find.byType(AnimatedScale),
        ),
      );
      expect(scale.scale, .88);
      expect(haptics.length, 1);
      for (var step = 1; step <= 6; step++) {
        await gesture.moveBy(const Offset(15, 18));
        await tester.pump(const Duration(milliseconds: 16));
        final size = tester.getSize(find.byKey(_bodyKey));
        expect(size.width, closeTo(original.width + step * 15, .1));
        expect(size.height, closeTo(original.height + step * 18, .1));
        final grip = tester.getRect(find.byType(CardResizeHandle));
        expect(
          grip.bottom,
          closeTo(tester.getRect(find.byKey(_bodyKey)).bottom, .1),
        );
        expect(fixture.resizeCount, 0);
        expect(fixture.horizontal.offset, 0);
        expect(fixture.vertical.offset, 0);
      }
      expect(fixture.contentBuilds, originalBuilds);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fixture.resizeCount, 1);
      expect(fixture.widthSpan, 3);
      expect(fixture.heightSpan, 2);
      expect(find.textContaining('松开保存'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('取消拖拽撤回预览，按下但未移动也不写布局', (tester) async {
    await tester.pumpWidget(
      const _EditingFixture(width: 640, initiallyEditing: true),
    );
    final original = tester.getSize(find.byKey(_bodyKey));
    var gesture = await tester.startGesture(
      tester.getCenter(find.byType(CardResizeHandle)),
    );
    await gesture.moveBy(const Offset(90, 100));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_bodyKey)), original);
    expect(_fixture(tester).resizeCount, 0);
    gesture = await tester.startGesture(
      tester.getCenter(find.byType(CardResizeHandle)),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_fixture(tester).resizeCount, 0);
    expect(find.textContaining('松开保存'), findsNothing);
  });

  for (final editing in [false, true]) {
    testWidgets('编辑模式 $editing 长按标题重排，放开保存且不折叠卡片', (tester) async {
      await tester.pumpWidget(
        _EditingFixture(width: 640, initiallyEditing: editing, twoCards: true),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('阅读统计')),
      );
      await tester.pump(const Duration(milliseconds: 220));
      await gesture.moveTo(tester.getCenter(find.text('第二张卡片')));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_fixture(tester).reorderCount, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_fixture(tester).order, [_secondKey, _cardKey]);
      expect(_fixture(tester).reorderCount, 1);
      expect(_fixture(tester).expanded, isTrue);
      expect(_fixture(tester).horizontal.offset, 0);
      expect(_fixture(tester).vertical.offset, 0);
      await tester.tap(editing ? find.byTooltip('折叠阅读统计') : find.text('阅读统计'));
      await tester.pumpAndSettle();
      expect(_fixture(tester).expanded, isFalse);
      expect(_fixture(tester).reorderCount, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('右侧卡片调整尺寸保持原位并停在面板边缘', (tester) async {
    await tester.pumpWidget(
      const _EditingFixture(
        width: 640,
        initiallyEditing: true,
        twoCards: true,
        fullWidthCards: false,
      ),
    );
    final second = find.byType(CollapsibleCard).last;
    final origin = tester.getRect(second);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CardResizeHandle).last),
    );
    await gesture.moveBy(const Offset(100, 70));
    await tester.pump();
    final preview = tester.getRect(second);
    expect(preview.topLeft, origin.topLeft);
    expect(preview.right, origin.right);
    expect(preview.height, closeTo(origin.height + 70, .1));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(_fixture(tester).resizeCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('标题栏压缩至 40，系统减少动画时拖动反馈无持续动画', (tester) async {
    await tester.pumpWidget(
      const _EditingFixture(
        width: 640,
        initiallyEditing: true,
        reduceMotion: true,
      ),
    );
    final title = tester.getRect(find.text('阅读统计'));
    final body = tester.getRect(find.text('阅读统计内容'));
    expect(body.top - tester.getRect(find.byKey(_bodyKey)).top, 40);
    expect(title.height, lessThan(40));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CardResizeHandle)),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('展示模式隐藏布局菜单和折叠按钮，单击标题仍能折叠', (tester) async {
    await tester.pumpWidget(const _EditingFixture(width: 640));
    await tester.pumpAndSettle();
    expect(find.byTooltip('卡片布局'), findsNothing);
    expect(find.byTooltip('折叠阅读统计'), findsNothing);
    await tester.tap(find.text('阅读统计'));
    await tester.pumpAndSettle();
    expect(_fixture(tester).expanded, isFalse);
    await tester.tap(find.text('自定义布局'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('卡片布局'), findsOneWidget);
    expect(find.byTooltip('展开阅读统计'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
