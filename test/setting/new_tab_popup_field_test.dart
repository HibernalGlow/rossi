// 「新页签启动选项」那三颗选择字段的判据。
//
// # 为什么单独钉这一份
//
// 这三处是 `PopupSelectField`（字段形状 + 全仓统一托盘弹出器）的第二批用户，
// 而它们的图标映射**写在调用点**：条目样式那一组走
// `LibraryViewMode.values.asNameMap()[name]?.icon`，键拼错只会静默没图标
// （返回 null，编译期什么都不报）—— 正是用户判「图标还是没补全」的那一类缺口。
// 操作绑定那批已有 `test/operation_binding/` 覆盖，这一页此前一处测试都没有。
//
// # 判据钉的是什么
//
// 1. 点开的是 `CommonPopupMenu`（托盘那一套），不是 SDK 默认的 DropdownMenu 淡入缩放。
// 2. 每个字段都带**当前值**，且当前值自己那一侧也画图标（不只在菜单里）。
// 3. 选项行带前导图标：选项来源 = 历史 / 预设 / 定位，条目样式 = 从
//    `LibraryViewMode.icon` 现取（这条就是 asNameMap 那处静默失败的阳性对照）。
// 4. 点选项真的改到设置上（不是只换个显示字）。

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/setting/global/file_manager_new_tab_settings.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';

import '../test_helper.dart';

void main() {
  // 字段选完会走 `GlobalSettingCubit.updateFileManagerSetting` ⇒ 落库；
  // 没有这层夹具时那条路在 `objectbox` 的 `!` 上炸（实测）。
  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  late GlobalSettingCubit cubit;

  Future<GlobalSettingCubit> pump(WidgetTester tester) async {
    cubit = GlobalSettingCubit();
    await tester.pumpWidget(
      BlocProvider<GlobalSettingCubit>(
        create: (_) => cubit,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: FileManagerNewTabSettings(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  /// 点开某一颗字段，顺手确认弹的是托盘菜单。
  ///
  /// 点的是字段里的 `InkWell` 而不是浮起 label 那颗 `Text` —— label 坐在边框线上，
  /// 它的中心被 `_RenderDecoration` 盖住，`tap` 会打在装饰上（实测 warnIfMissed 警告）。
  Future<void> open(WidgetTester tester, String label) async {
    final field = find.ancestor(
      of: find.text(label),
      matching: find.byType(InkWell),
    );
    expect(field, findsOneWidget, reason: '找不到「$label」这颗字段');
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(
      find.byType(CommonPopupMenu),
      findsOneWidget,
      reason: '「$label」没走统一托盘弹出器',
    );
  }

  Finder glyphInMenu(Glyph glyph) => find.descendant(
    of: find.byType(CommonPopupMenu),
    matching: find.byWidgetPredicate((w) => w is GlyphIcon && w.glyph == glyph),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // cubit 的写库路径固定读 id=1 那行；测试库里没有就按 main 的做法种一行。
    if (objectbox.userSettingBox.get(1) == null) {
      objectbox.userSettingBox.put(UserSetting());
    }
  });

  testWidgets('选项来源：图标取自「历史 / 预设 / 定位」，点下去真的改设置', (tester) async {
    await pump(tester);
    // 当前值不硬编：这一档的默认由设置自己说，字段必须把它显示出来。
    final currentPolicy = cubit.state.fileManagerSetting.newTabPolicy;
    expect(
      find.text(currentPolicy.label),
      findsOneWidget,
      reason: '字段得先显示当前值，否则用户不知道自己选的是哪档',
    );

    await open(tester, '选项来源');
    expect(
      glyphInMenu(AppGlyphs.history),
      findsOneWidget,
      reason: '「继承最近使用的页签」没有图标 = 这一页还是漏补的那一处',
    );
    expect(glyphInMenu(AppGlyphs.reset), findsOneWidget);
    expect(glyphInMenu(AppGlyphs.target), findsOneWidget);

    final next = FileManagerTabStartupPolicy.values.firstWhere(
      (policy) => policy != currentPolicy,
    );
    await tester.tap(find.text(next.label).last);
    await tester.pumpAndSettle();
    expect(cubit.state.fileManagerSetting.newTabPolicy, next);
    expect(find.byType(CommonPopupMenu), findsNothing, reason: '点完叶子要收起整个菜单');
  });

  testWidgets('默认条目样式的图标是从 LibraryViewMode.icon 现取的（不是各写一份）', (tester) async {
    await pump(tester);
    // 默认 compact ⇒ 字段上那颗就该是它自己那颗，而不是菜单里才有图标。
    expect(
      find.byWidgetPredicate(
        (w) => w is GlyphIcon && w.glyph == LibraryViewMode.compact.icon,
      ),
      findsWidgets,
    );

    await open(tester, '默认条目样式');
    for (final mode in LibraryViewMode.values) {
      expect(
        glyphInMenu(mode.icon),
        findsOneWidget,
        reason: '${mode.label} 这一行没图标：asNameMap 那条键接错了',
      );
    }

    await tester.tap(find.text(LibraryViewMode.coverGrid.label).last);
    await tester.pumpAndSettle();
    expect(
      cubit.state.fileManagerSetting.newTabViewMode,
      LibraryViewMode.coverGrid.name,
    );
  });
}
