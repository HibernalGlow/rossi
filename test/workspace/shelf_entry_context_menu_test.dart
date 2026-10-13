// 右键菜单**宿主**的判据：手势真的通到菜单、灰掉的项真的点不动。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/workspace/shelf_entry_context_menu_test.dart
//
// （本机必须解掉 `HTTP_PROXY`：沙箱代理会劫持 `flutter_tester` 的 WebSocket 握手。）
//
// 与 `shelf_entry_menu_check.dart` 的分工：那个文件管「有哪些项、哪一项可用」
// （纯逻辑，`dart run` 就能跑）；这个文件只管两件**只有真树才验得到**的事：
//
//   1. **手势 → 菜单**：桌面右键与触摸长按都得弹出来。挂错手势时界面完全正常，
//      只是「右键没反应」——那不报错，所以必须真的按一次；
//   2. **灰掉的项**：它必须**在场**（用户看得见这一项存在），但点不动、不回调。
//      禁用态就是 `CommonPopupMenuItem(onPressed: null)`（行内 `InkWell.onTap`
//      为空），写反了同样不报错，只会「点了没反应」。
//
// 这里不搭真实卡片（那要 ObjectBox 与全局设置 Cubit，本机是基线红），
// 只搭菜单宿主 + 一个假的行内容 —— 被测的东西全在宿主里。
//
// 项**按文案定位**（`shelfEntryActionLabel`）：菜单行由 `CommonPopupMenu` 画，
// 它按 `label` 渲染正文，可点与否落在那一行 `InkWell` 的 `onTap` 上。
//
// ignore_for_file: avoid_print
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/workspace/model/shelf_entry_menu_spec.dart';
import 'package:zephyr/workspace/widgets/cards/shelf_entry_context_menu.dart';

/// 夹具：一行可点内容 + 菜单宿主。选到的动作由测试自己收，夹具不存状态
/// —— 存状态的夹具会让「上一次用例的动作」跟着 widget 活下来。
class _Harness extends StatelessWidget {
  const _Harness({
    required this.input,
    required this.onAction,
    this.enabled = true,
  });

  final ShelfEntryMenuInput input;
  final void Function(ShelfEntryAction action) onAction;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: ShelfEntryContextMenuRegion(
            enabled: enabled,
            inputBuilder: () => input,
            onAction: (context, action) => onAction(action),
            child: const SizedBox(
              width: 200,
              height: 48,
              child: ColoredBox(color: Color(0xFFEEEEEE)),
            ),
          ),
        ),
      ),
    );
  }
}

String _labelOf(ShelfEntryMenuInput input, ShelfEntryAction action) =>
    shelfEntryActionLabel(
      action,
      kind: input.kind,
      isFavorite: input.isFavorite,
    );

/// 当前弹出来的菜单里，每一项的（动作, 能不能点）——按**规格的次序**（也就是画的次序）。
///
/// 先按规格逐项算出文案，再在树里找那一行最近的 `InkWell` 读 `onTap`：
/// 缺项与「本该可点却灰了」都会当场暴露。
List<(ShelfEntryAction, bool)> _menuItems(
  WidgetTester tester,
  ShelfEntryMenuInput input,
) {
  return [
    for (final spec in buildShelfEntryMenuItems(input))
      if (find
          .ancestor(
            of: find.text(_labelOf(input, spec.action)),
            matching: find.byType(InkWell),
          )
          .evaluate()
          .isNotEmpty)
        (
          spec.action,
          (find
                      .ancestor(
                        of: find.text(_labelOf(input, spec.action)),
                        matching: find.byType(InkWell),
                      )
                      .evaluate()
                      .first
                      .widget
                  as InkWell)
                  .onTap !=
              null,
        ),
  ];
}

/// 按动作找那一行。**灰掉的项也必须找得到** —— 所以不能按「可点的项」筛。
Finder _itemOf(ShelfEntryMenuInput input, ShelfEntryAction action) =>
    find.text(_labelOf(input, action));

void main() {
  testWidgets('桌面右键弹出菜单，项与次序与规格一致', (tester) async {
    const input = ShelfEntryMenuInput(
      kind: ShelfEntryKind.history,
      canOpenInFileManagerTab: true,
    );
    final seen = <ShelfEntryAction>[];
    await tester.pumpWidget(_Harness(input: input, onAction: seen.add));

    await tester.tap(
      find.byType(ShelfEntryContextMenuRegion),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    final expected = buildShelfEntryMenuItems(
      input,
    ).map((spec) => (spec.action, spec.enabled)).toList();
    expect(_menuItems(tester, input), expected);
    // 历史卡的菜单里必须有「收藏」这一项 —— 少了它整行判断就退化成收藏卡。
    expect(
      _menuItems(tester, input).map((entry) => entry.$1),
      contains(ShelfEntryAction.toggleFavorite),
    );
  });

  testWidgets('触摸端长按弹出同一份菜单', (tester) async {
    const input = ShelfEntryMenuInput(kind: ShelfEntryKind.favorite);
    await tester.pumpWidget(_Harness(input: input, onAction: (_) {}));

    await tester.longPress(find.byType(ShelfEntryContextMenuRegion));
    await tester.pumpAndSettle();

    expect(
      _menuItems(tester, input).map((entry) => entry.$1).toList(),
      buildShelfEntryMenuItems(input).map((spec) => spec.action).toList(),
    );
  });

  testWidgets('没有本地目录时那一项**在场但灰掉**', (tester) async {
    const input = ShelfEntryMenuInput(kind: ShelfEntryKind.favorite);
    await tester.pumpWidget(_Harness(input: input, onAction: (_) {}));

    await tester.tap(
      find.byType(ShelfEntryContextMenuRegion),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    final entry = _menuItems(tester, input)
        .where((item) => item.$1 == ShelfEntryAction.openInFileManagerTab)
        .toList();
    expect(entry, hasLength(1), reason: '灰掉 ≠ 隐藏：它必须在菜单里');
    expect(entry.single.$2, isFalse);
  });

  testWidgets('全局开关关掉时右键不弹菜单', (tester) async {
    final seen = <ShelfEntryAction>[];
    await tester.pumpWidget(
      _Harness(
        input: const ShelfEntryMenuInput(kind: ShelfEntryKind.favorite),
        enabled: false,
        onAction: seen.add,
      ),
    );

    await tester.tap(
      find.byType(ShelfEntryContextMenuRegion),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.byType(CommonPopupMenu), findsNothing);
    expect(seen, isEmpty);
  });

  testWidgets('点一个可用项会回调，点灰项不会', (tester) async {
    const input = ShelfEntryMenuInput(
      kind: ShelfEntryKind.history,
      canOpenInFileManagerTab: true,
      isFavorite: true,
    );
    final seen = <ShelfEntryAction>[];
    await tester.pumpWidget(_Harness(input: input, onAction: seen.add));

    await tester.tap(
      find.byType(ShelfEntryContextMenuRegion),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    // 先点灰掉的那一项（已收藏 ⇒ 「收藏」不可用）：菜单不关、不回调。
    await tester.tap(_itemOf(input, ShelfEntryAction.toggleFavorite));
    await tester.pumpAndSettle();
    expect(seen, isEmpty);

    // 再点「复制标题」：回调一次，菜单关掉。
    await tester.tap(_itemOf(input, ShelfEntryAction.copyTitle));
    await tester.pumpAndSettle();
    expect(seen, <ShelfEntryAction>[ShelfEntryAction.copyTitle]);
    expect(find.byType(CommonPopupMenu), findsNothing);
  });
}
