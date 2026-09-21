import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_info/action/comic_info_action_entry.dart';
import 'package:zephyr/page/comic_info/action/comic_info_action_scope.dart';
import 'package:zephyr/page/comic_info/widgets/comic_info_action_rail.dart';
import 'package:zephyr/widgets/glass/liquid_glass.dart';

/// 只测 rail 本身：不起 `ComicInfoPage`（那要 ObjectBox + 好几个 bloc + 一次网络），
/// 用一个假 scope 钉住「点下去之后到底调了哪个方法」——也就是派发真的按注册表 id 走，
/// rail 里没有第二份「这条该干什么」的判断。
class _FakeScope implements ComicInfoActionScope {
  _FakeScope(this.items);

  final List<ComicInfoActionEntry> items;
  final dispatched = <String>[];

  @override
  List<ComicInfoActionEntry> comicInfoActionItems() => items;

  @override
  void actionBack(BuildContext context) =>
      dispatched.add(ComicInfoActionIds.back);

  @override
  void actionHome(BuildContext context) =>
      dispatched.add(ComicInfoActionIds.home);

  @override
  void actionRead(BuildContext context) =>
      dispatched.add(ComicInfoActionIds.read);
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);

ComicInfoActionEntry _entry(
  String id, {
  VoidCallback? onTap = _noop,
  bool enabled = true,
}) => ComicInfoActionEntry(
  actionId: id,
  icon: Icons.bug_report_outlined,
  label: 'label-$id',
  onTap: onTap,
  enabled: enabled,
);

void _noop() {}

void main() {
  testWidgets('点击按 id 派发到 scope 的对应方法', (tester) async {
    final scope = _FakeScope([
      _entry(ComicInfoActionIds.back),
      _entry(ComicInfoActionIds.read),
    ]);
    await tester.pumpWidget(
      _wrap(ComicInfoActionRail(scope: scope, items: scope.items)),
    );

    expect(find.byType(IconButton), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.bug_report_outlined).first);
    expect(scope.dispatched, [ComicInfoActionIds.back]);
    await tester.tap(find.byIcon(Icons.bug_report_outlined).last);
    expect(scope.dispatched, [
      ComicInfoActionIds.back,
      ComicInfoActionIds.read,
    ]);
  });

  testWidgets('enabled=false 画成禁用态，且提示仍在', (tester) async {
    final scope = _FakeScope([
      _entry(ComicInfoActionIds.export, enabled: false),
    ]);
    await tester.pumpWidget(
      _wrap(ComicInfoActionRail(scope: scope, items: scope.items)),
    );

    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
      reason: '禁用要交给 IconButton 自己，才会画成禁用态而不是换个颜色',
    );
    expect(
      find.byType(Tooltip),
      findsOneWidget,
      reason: '提示还得在，用户才知道这颗为什么现在不能点',
    );
  });

  testWidgets('空清单整条 rail 不占位', (tester) async {
    final scope = _FakeScope(const []);
    await tester.pumpWidget(
      _wrap(ComicInfoActionRail(scope: scope, items: scope.items)),
    );

    expect(tester.getSize(find.byType(ComicInfoActionRail)), Size.zero);
  });

  testWidgets('胶囊按内容多高就多高，不铺满一列（第一版的回归：挤占漫画宽度）', (tester) async {
    final scope = _FakeScope([
      _entry(ComicInfoActionIds.back),
      _entry(ComicInfoActionIds.home),
    ]);
    await tester.pumpWidget(
      _wrap(ComicInfoActionRail(scope: scope, items: scope.items)),
    );

    final size = tester.getSize(find.byType(ComicInfoActionRail));
    // 视口是 600x600：铺满一列就是回归成第一版那条 52px 的空白列。
    expect(size.height, lessThan(140), reason: '两颗 = 约 94px，不是整屏高');
    expect(size.width, lessThan(60));
    expect(size.width, greaterThan(40));
    expect(size.height, greaterThan(80));
  });

  test('未接执行端的 id 派发返回 false（不许静默吞掉）', () {
    final scope = _FakeScope(const []);
    expect(
      dispatchComicInfoAction(scope, ComicInfoActionIds.collect, _NoContext()),
      isFalse,
      reason: 'collect 要等车道 C-2；现在必须报「没接」而不是什么都不发生',
    );
  });

  // ── 几何：悬浮 = 不占正文宽度，且两颗都完整在窗口内 ─────────────────────────
  //
  // 钉的是实机连打两版的那两个问题：① `Row` 版把正文挤窄 104px；② `Stack` 版里
  // `Positioned(right: 8)` 只给了单边 ⇒ 子节点拿到松约束，而 `Center` 没有
  // widthFactor 时会撑到 constraints.biggest，右边那颗被裁在窗口外。

  Future<void> mountOverlay(
    WidgetTester tester, {
    required _FakeScope left,
    required _FakeScope right,
    Size viewport = const Size(500, 600),
    bool glass = false,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComicInfoActionOverlay(
            scope: left,
            glass: glass,
            leftItems: left.items,
            rightItems: right.items,
            child: const ColoredBox(
              key: ValueKey('content'),
              color: Colors.blue,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('两颗胶囊都完整落在窗口内，右边那颗右边缘正好离边 8px', (tester) async {
    await mountOverlay(
      tester,
      left: _FakeScope([
        _entry(ComicInfoActionIds.back),
        _entry(ComicInfoActionIds.home),
      ]),
      right: _FakeScope([_entry(ComicInfoActionIds.read)]),
    );

    final railFinder = find.byType(ComicInfoActionRail);
    expect(railFinder, findsNWidgets(2));
    final rails = [
      tester.getRect(railFinder.first),
      tester.getRect(railFinder.last),
    ];
    for (final rect in rails) {
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(500), reason: '被裁到窗口外就是这次的 bug');
      expect(rect.bottom, lessThanOrEqualTo(600));
    }
    expect(rails.first.left, 8, reason: '左那颗离左边 8px');
    expect(rails.last.right, 492, reason: '右那颗离右边 8px，不是撑到中间');
    expect(rails.first.width, ComicInfoActionRail.maxWidth);
    expect(rails.last.width, ComicInfoActionRail.maxWidth);
    // 垂直居中（两颗都按内容高，居中在 600 高的视口里）。
    expect(rails.last.center.dy, closeTo(300, 1));
  });

  testWidgets('正文宽度不受胶囊影响（悬浮不占布局）', (tester) async {
    await mountOverlay(
      tester,
      left: _FakeScope([_entry(ComicInfoActionIds.back)]),
      right: _FakeScope([_entry(ComicInfoActionIds.read)]),
    );

    // 正文自己占满 500 —— 胶囊是浮在它上面的，不是从它旁边切走的。
    final content = find.byKey(const ValueKey('content'));
    expect(tester.getRect(content).width, 500);
    expect(tester.getRect(content).left, 0);
  });

  testWidgets('玻璃档与实底档都渲染得出来（开关两头都要能走通）', (tester) async {
    for (final glass in [false, true]) {
      await mountOverlay(
        tester,
        left: _FakeScope([_entry(ComicInfoActionIds.back)]),
        right: _FakeScope([_entry(ComicInfoActionIds.read)]),
        glass: glass,
      );
      expect(find.byType(IconButton), findsNWidgets(2), reason: 'glass=$glass');
      expect(
        find.byType(glass ? LiquidGlassSurface : Material),
        findsWidgets,
        reason: 'glass=$glass 时该有它那一档承底',
      );
    }
  });
}

/// [dispatchComicInfoAction] 只用 context 转交给 scope，这条判据里那条路径走不到；
/// 造一个真的 BuildContext 要为了一行签名，不值。
class _NoContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
