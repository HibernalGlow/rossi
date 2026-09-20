import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_info/action/comic_info_action_entry.dart';
import 'package:zephyr/page/comic_info/action/comic_info_action_scope.dart';
import 'package:zephyr/page/comic_info/widgets/comic_info_action_rail.dart';

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

  test('未接执行端的 id 派发返回 false（不许静默吞掉）', () {
    final scope = _FakeScope(const []);
    expect(
      dispatchComicInfoAction(scope, ComicInfoActionIds.collect, _NoContext()),
      isFalse,
      reason: 'collect 要等车道 C-2；现在必须报「没接」而不是什么都不发生',
    );
  });
}

/// [dispatchComicInfoAction] 只用 context 转交给 scope，这条判据里那条路径走不到；
/// 造一个真的 BuildContext 要为了一行签名，不值。
class _NoContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
