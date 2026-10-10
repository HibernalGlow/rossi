// 书签 / 历史工具栏与列表轨 chip 的 MD3 口径判据。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/workspace/shelf_list_toolbar_test.dart
//
// 这里只搭工具栏与 chip 本身（不搭卡片：那要 ObjectBox 与全局设置 Cubit，
// 本机是基线红）。断言的全部是**量得出来的东西**，不是「看起来对了」：
//
//   1. 图标钮 40 见方、图标 20 —— 与文件管理器工具栏同一份度量档；
//   2. 分组画成**下沉槽**（`ActionGroup`），槽内 4、槽与槽之间 12（外沿口径），
//      而且 **4 与 12 必须量出不同的值**（否则「分组」这条断言看不见违规）；
//   3. 导入 / 导出收成一颗带文字的菜单键，两项都能点到、各自回调；
//      不给回调时整组不出现；
//   4. 单选 chip 不画勾、选中走 `secondaryContainer` —— 并且留一条**阳性对照**
//      证明「不画勾」这件事真的会被看见。
//
// 书签卡片里那条「列表轨」（chips + 列表管理两颗键，同样装进一只槽）不在这里
// 断言：搭 `FavoriteShelfCard` 要 ObjectBox，本机是基线红。那一段的几何与这里
// 同源（`ActionGroup` + `ActionIconButton`），口径变了这里会先红。
//
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/action_group.dart';
import 'package:zephyr/workspace/model/shelf_library_query.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_toolbar.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_chip.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_list_toolbar.dart';
import 'package:zephyr/workspace/widgets/library_view/shelf_menu_button.dart';

/// 夹具：一条真会横向滚的工具栏，宽度给足，免得量到的间距被挤压。
Widget _harness(ShelfListToolbar toolbar) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 900, child: Align(alignment: Alignment.topLeft, child: toolbar)),
    ),
  );
}

ShelfListToolbar _toolbar({
  required TextEditingController controller,
  LibraryViewMode viewMode = LibraryViewMode.coverList,
  ShelfSort sort = const ShelfSort(field: ShelfSortField.time),
  ValueChanged<LibraryViewMode>? onViewMode,
  ValueChanged<ShelfSort>? onSort,
  VoidCallback? onExport,
  VoidCallback? onImport,
}) {
  return ShelfListToolbar(
    viewMode: viewMode,
    onViewMode: onViewMode ?? (_) {},
    sort: sort,
    onSort: onSort ?? (_) {},
    searchController: controller,
    onKeywordChanged: (_) {},
    count: 52,
    onExport: onExport,
    onImport: onImport,
    portLabel: '历史数据',
  );
}

Finder _iconOf(String tooltip) {
  // 触发键的图标如今两套并存：本仓自绘的 GlyphIcon（多数）与 Material Icon
  // 兜底（glyph 词表暂无对应符号的，如时间线）—— 都算「这颗键的图标」。
  return find.descendant(
    of: find.byTooltip(tooltip),
    matching: find.byWidgetPredicate(
      (widget) => widget is Icon || widget is GlyphIcon,
    ),
  );
}

void main() {
  late TextEditingController controller;

  setUp(() => controller = TextEditingController());
  tearDown(() => controller.dispose());

  testWidgets('图标钮 40 见方、图标 20 —— 与文件管理器同一份度量档', (tester) async {
    await tester.pumpWidget(
      _harness(_toolbar(controller: controller, onExport: () {}, onImport: () {})),
    );
    await tester.pumpAndSettle();

    for (final tooltip in ['视图模式：封面列表', '排序：时间 · 降序', '搜索', '历史数据']) {
      final trigger = find.byTooltip(tooltip);
      expect(trigger, findsOneWidget, reason: '$tooltip 找不到触发键');
      expect(
        tester.getSize(trigger),
        const Size(
          FileManagerToolbarMetrics.buttonSize,
          FileManagerToolbarMetrics.buttonSize,
        ),
        reason: '$tooltip 不是 40 见方',
      );
      expect(
        tester.getSize(_iconOf(tooltip)),
        const Size.square(FileManagerToolbarMetrics.iconSize),
        reason: '$tooltip 的图标不是 20',
      );
    }

    // 阳性对照：同一把尺子必须看得见「旧的 18dp 裸图标」那种画法。
    // 没有这一段，上面那两条断言可能只是量不到东西而空过。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IconButton(
            icon: const Icon(Icons.search, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(Icon)),
      const Size.square(18),
      reason: '对照不成立 —— 这把尺子量不出 18 与 20 的差别',
    );
  });

  testWidgets('分组画成下沉槽：槽内 4、槽与槽之间 12，且两个值真的不同', (tester) async {
    await tester.pumpWidget(
      _harness(_toolbar(controller: controller, onExport: () {}, onImport: () {})),
    );
    await tester.pumpAndSettle();

    // 一槽一组：这条工具栏上是「怎么看」与「数据」两只。
    expect(
      find.byType(ActionGroup),
      findsNWidgets(2),
      reason: '分组没画成槽，或者多长出一只',
    );

    double edgeGap(String from, String to) =>
        tester.getRect(find.byTooltip(to)).left -
        tester.getRect(find.byTooltip(from)).right;

    // 槽内：两颗键之间就是组内间距本身（槽的内边距不出现在两颗键之间）。
    final within = edgeGap('视图模式：封面列表', '排序：时间 · 降序');
    expect(within, ActionGroupMetrics.gapWithinGroup);

    // 这一版夹具**没有**时间线那颗键：分隔符跟着它一起进 `if`，所以
    // 「排序 → 搜索」之间仍然只有一个 4。留在外面会叠成 8，同一个槽里
    // 就有了两种间距 —— 这一条就是那次修复的回归判据。
    expect(edgeGap('排序：时间 · 降序', '搜索'), ActionGroupMetrics.gapWithinGroup);

    // 槽间：两颗键各自还隔着**自己那片槽壁**，所以量到的是「组间间距 +
    // 两片槽壁」。断言这个**和**：槽壁厚度或组间间距任一处变了都会红。
    final between = edgeGap('搜索', '历史数据');
    expect(
      between,
      ActionGroupMetrics.gapBetweenGroups + ActionGroupMetrics.wellPadding * 2,
    );

    // 断言这两个值互不相等：分组这件事的全部含义就是「组间比组内松」。
    // 如果哪天两处都写成同一个数，这条会红，而上面两条会一起绿着骗人。
    expect(
      within,
      isNot(between),
      reason: '组内与组间同一个间距，等于没有分组',
    );

    // 阳性对照：槽得是**画出来的**，不是一只透明的 Container —— 上面三条
    // 全靠间距，间距对了但槽没画照样会全绿。
    final viewWell = find.byType(ActionGroup).first;
    final wellRect = tester.getRect(viewWell);
    final first = tester.getRect(find.byTooltip('视图模式：封面列表'));
    final last = tester.getRect(find.byTooltip('搜索'));

    // 槽正好箍住这一组的两端：两片槽壁各 wellPadding —— 厚度、也即
    // 「槽存在」这件事，是从这里量出来的（与槽里有几颗键无关）。
    expect(wellRect.left, first.left - ActionGroupMetrics.wellPadding);
    expect(wellRect.right, last.right + ActionGroupMetrics.wellPadding);
    // 槽与槽里的键共用同一条 40 的高度带，不然同一条栏上会出现两种高度。
    expect(wellRect.height, ActionGroupMetrics.buttonSize);

    // 底色得真画上：`ActionGroup` 不传 `fill` 时取 `surfaceContainer`
    // （比卡片底低一档，读作「这一片是可操作区」）。
    final scheme = Theme.of(tester.element(viewWell)).colorScheme;
    final container = tester.widget<Container>(
      find.descendant(of: viewWell, matching: find.byType(Container)),
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      scheme.surfaceContainer,
      reason: '槽没画底色 —— 看上去就只是一排飘着的图标',
    );
  });

  testWidgets('导入 / 导出是一颗菜单键，两项各自回调', (tester) async {
    var exports = 0;
    var imports = 0;
    await tester.pumpWidget(
      _harness(
        _toolbar(
          controller: controller,
          onExport: () => exports++,
          onImport: () => imports++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 两颗长得几乎一样的下载/上传箭头收成一颗：整组只有一个触发键。
    expect(find.byTooltip('历史数据'), findsOneWidget);
    expect(find.byTooltip('导出书签为 JSON'), findsNothing);

    await tester.tap(find.byTooltip('历史数据'));
    await tester.pumpAndSettle();

    final items = tester
        .widgetList<ShelfMenuItem>(find.byType(ShelfMenuItem))
        .map((item) => item.label)
        .toList();
    expect(items, ['导出为 JSON', '从 JSON 导入']);

    await tester.tap(find.widgetWithText(ShelfMenuItem, '导出为 JSON'));
    await tester.pumpAndSettle();
    expect(exports, 1);
    expect(imports, 0);

    await tester.tap(find.byTooltip('历史数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ShelfMenuItem, '从 JSON 导入'));
    await tester.pumpAndSettle();
    expect(imports, 1);
    expect(exports, 1);
  });

  testWidgets('没有导入导出这一侧时，整组不出现（而不是给一颗点了没反应的键）', (tester) async {
    await tester.pumpWidget(_harness(_toolbar(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.byTooltip('历史数据'), findsNothing);
    expect(find.byType(ShelfMenuItem), findsNothing);
    // 同一条工具栏在给了回调的那一版里确实有这一组 —— 见上一个用例，
    // 所以这里的 findsNothing 不是「压根没画」。
  });

  testWidgets('busy 时导入导出整组按不住', (tester) async {
    await tester.pumpWidget(
      _harness(
        ShelfListToolbar(
          viewMode: LibraryViewMode.coverList,
          onViewMode: (_) {},
          sort: const ShelfSort(field: ShelfSortField.time),
          onSort: (_) {},
          searchController: controller,
          onKeywordChanged: (_) {},
          count: 1,
          onExport: () {},
          onImport: () {},
          portLabel: '历史数据',
          busy: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 触发键整颗禁用：忙的时候不该还能发起第二次读写。
    // `Tooltip` 是 `IconButton` 的**后代**（按钮自己把 tooltip 包在里面），
    // 所以往上看，不要往下找。
    final trigger = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('历史数据'),
        matching: find.byType(IconButton),
      ),
    );
    expect(trigger.onPressed, isNull, reason: 'busy 时触发键还能按');
  });

  testWidgets('单选 chip：不画勾、选中走 secondaryContainer', (tester) async {
    late ColorScheme scheme;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            scheme = Theme.of(context).colorScheme;
            return Scaffold(
              body: Column(
                children: [
                  ShelfListChip(label: '全部', selected: true, onTap: () {}),
                  ShelfListChip(label: '未分类', selected: false, onTap: () {}),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
    expect(chips, hasLength(2));
    final selectedChip = chips.first;
    final unselectedChip = chips.last;

    // 1. 勾：单选轨上不画勾（那是多选的符号）。
    expect(selectedChip.showCheckmark, isFalse);
    expect(unselectedChip.showCheckmark, isFalse);
    // 2. 选中态走 secondaryContainer，而不是 primary 染色。
    expect(selectedChip.selectedColor, scheme.secondaryContainer);
    expect(selectedChip.labelStyle!.color, scheme.onSecondaryContainer);
    // 选中时不描边：MD3 的 chip 靠底色分层，不靠「底色 + 一圈线」。
    expect(selectedChip.side!.color.a, 0);
    // 3. 未选中也得有自己的容器底色：全局 chipTheme 把 backgroundColor 覆成了
    //    surface，在 useMaterial3 下它会盖过 M3 默认的 surfaceContainerLow，
    //    于是那颗 chip 只剩一圈描边、读起来不像可点的档。
    expect(unselectedChip.backgroundColor, scheme.surfaceContainerLow);
    expect(unselectedChip.labelStyle!.color, scheme.onSurfaceVariant);
    expect(unselectedChip.side!.color, scheme.outlineVariant);
  });

  testWidgets('阳性对照：不写 showCheckmark 时默认档是会画勾的', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // 与 ShelfListChip 唯一的差别就是不传 showCheckmark。
              ChoiceChip(label: const Text('全部'), selected: true, onSelected: (_) {}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
    // `material_ui` 的 ChoiceChip M3 默认档写着 `showCheckmark: true`
    // （`_ChoiceChipDefaultsM3`）。这里读到 null 就意味着「跟随默认 = 画勾」，
    // 于是上面那条 isFalse 是真做了事，不是本来就不会画。
    expect(chip.showCheckmark, isNull);
  });

  testWidgets('时间线：给了动作才有那颗键，且状态写在 tooltip 上', (tester) async {
    // 不给 onTimeline ⇒ 整颗不出现（文件管理器那侧就没有时间线这个概念）。
    await tester.pumpWidget(_harness(_toolbar(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('按天看时间线'), findsNothing);

    var toggles = 0;
    await tester.pumpWidget(
      _harness(
        ShelfListToolbar(
          viewMode: LibraryViewMode.coverList,
          onViewMode: (_) {},
          sort: const ShelfSort(field: ShelfSortField.time),
          onSort: (_) {},
          searchController: controller,
          onKeywordChanged: (_) {},
          count: 3,
          onTimeline: () => toggles++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('按天看时间线'), findsOneWidget);
    await tester.tap(find.byTooltip('按天看时间线'));
    await tester.pumpAndSettle();
    expect(toggles, 1);
  });

  testWidgets('时间线开着时视图与排序两颗键**在场但灰掉**', (tester) async {
    IconButton triggerFor(String tooltip) => tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );

    Widget bar({required bool timelineOn}) => _harness(
      ShelfListToolbar(
        viewMode: LibraryViewMode.coverList,
        onViewMode: (_) {},
        sort: const ShelfSort(field: ShelfSortField.time),
        onSort: (_) {},
        searchController: controller,
        onKeywordChanged: (_) {},
        count: 3,
        timelineOn: timelineOn,
        onTimeline: () {},
      ),
    );

    await tester.pumpWidget(bar(timelineOn: false));
    await tester.pumpAndSettle();
    // 先量「关着」这一侧：两颗键都可点。没有这一段，下面的 isNull
    // 可能只是因为整条工具栏压根没画出来。
    expect(triggerFor('视图模式：封面列表').onPressed, isNotNull);
    expect(triggerFor('排序：时间 · 降序').onPressed, isNotNull);
    expect(find.byTooltip('视图模式（时间线下不适用）'), findsNothing);

    await tester.pumpWidget(bar(timelineOn: true));
    await tester.pumpAndSettle();
    expect(
      triggerFor('视图模式（时间线下不适用）').onPressed,
      isNull,
      reason: '时间线用自己的行式，视图档此刻不该还能改',
    );
    expect(
      triggerFor('排序（时间线固定按时间排）').onPressed,
      isNull,
      reason: '时间线固定按时间倒序，排序档此刻不该还能改',
    );
    // 灰掉 ≠ 藏掉：两颗键仍然在场，用户看得见「有这件事，只是现在做不了」。
    expect(find.byTooltip('视图模式：封面列表'), findsNothing);
    expect(find.byTooltip('排序：时间 · 降序'), findsNothing);
  });
}
