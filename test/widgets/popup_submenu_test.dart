// `CommonPopupMenu` 的二级（`subItems`）判据。
//
// # 为什么单独钉这一份
//
// `subItems` 是从 FlClash 搬过来的机制，本仓**直到文件管理器「更多」与泳道「更多」
// 收成二级之前，没有任何调用点** —— 一条零流量的路径不敢只靠读代码放行。
// 这两处菜单各有一个「六项单选组」和「一个住着输入框的子项」，都压在这条路径上。
//
// # 判据钉的是什么
//
// 1. **收起时子项真的不在树上**：不是透明度为 0、不是被裁掉，而是根本没建。
//    这一条同时是「父行代替整组」的前提；父行要是还带着子项平铺，折叠就没省到高度。
// 2. **点父行不关菜单**：收起→展开是同一次交互，菜单不能先消失再弹一次。
// 3. **退一层有两条路**：子级顶部那颗重复的父行表头，以及 Esc / 系统返回键
//    （`canPop` 只在顶层为 true，于是返回键落到 `_pop()` 而不是关菜单）——
//    用户按返回的手感不该改变任何值。
// 4. **退回顶层后能换另一个父行**：只有最前那一层收点击（后面的层包着
//    `IgnorePointer`），所以同级切换必须先退一层；这一条钉住「退得回去、也切得过来」。
// 5. **点叶子才落账并收起整个菜单**，且 `content` 那一行（输入框那一类）
//    在二级里既渲染得出来、又不会被「整行点击语义」误关。
//
// 与动效无关：弹簧/托盘只按停稳之后的状态判（同 `popup_panel_test.dart` 的口径）。

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/common_popup.dart';

const Key _subContentKey = ValueKey<String>('submenu-content-row');

void main() {
  final opened = <String>[];

  List<CommonPopupMenuItem> items() => [
    CommonPopupMenuItem(
      label: '顶层开关',
      glyph: AppGlyphs.eye,
      onPressed: () => opened.add('plain'),
    ),
    CommonPopupMenuItem(
      label: '组甲：当前值',
      glyph: AppGlyphs.passThrough,
      subItems: [
        CommonPopupMenuItem(
          label: '甲一',
          glyph: AppGlyphs.dot,
          onPressed: () => opened.add('甲一'),
        ),
        CommonPopupMenuItem(
          label: '甲二',
          glyph: AppGlyphs.dice,
          checked: true,
          onPressed: () => opened.add('甲二'),
        ),
        // 泳道「常规宽度」就是这一类：子项里住着一只输入框（这里用带 key 的
        // 替身），点它不该收菜单、也不该落账。
        const CommonPopupMenuItem(
          glyph: AppGlyphs.resize,
          content: Text('输入替身', key: _subContentKey),
        ),
      ],
    ),
    CommonPopupMenuItem(
      label: '组乙：当前值',
      glyph: AppGlyphs.category,
      subItems: [
        CommonPopupMenuItem(
          label: '乙一',
          glyph: AppGlyphs.calendar,
          onPressed: () => opened.add('乙一'),
        ),
      ],
    ),
  ];

  Widget host() => BlocProvider<GlobalSettingCubit>(
    create: (_) => GlobalSettingCubit(),
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: CommonPopupBox<void>(
            targetBuilder: (open) => IconButton(
              tooltip: '更多',
              onPressed: open,
              icon: const GlyphIcon(AppGlyphs.more),
            ),
            popupBuilder: (_) => CommonPopupMenu(items: items()),
          ),
        ),
      ),
    ),
  );

  setUp(() => opened.clear());

  testWidgets('二级收起时子项不在树上，展开之后才建出来', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();

    expect(find.text('顶层开关'), findsOneWidget);
    expect(find.textContaining('组甲'), findsOneWidget);
    // 判据 1：父行是唯一的那一行。
    expect(find.text('甲一'), findsNothing);
    expect(find.text('乙一'), findsNothing);

    await tester.tap(find.textContaining('组甲'));
    await tester.pumpAndSettle();

    expect(find.text('甲一'), findsOneWidget);
    expect(find.text('甲二'), findsOneWidget);
    // 别的组没跟着一起展开。
    expect(find.text('乙一'), findsNothing);
    // 判据 2：展开不关菜单，顶层那几行还在树上。
    expect(find.text('顶层开关'), findsWidgets);
    expect(opened, isEmpty);
  });

  testWidgets('退一层：点子级里那颗表头回顶层，系统返回键同一条路', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('组甲'));
    await tester.pumpAndSettle();
    expect(find.text('甲一'), findsOneWidget);

    // 只有最前那一层收点击（后面的层包着 `IgnorePointer`），所以
    // `hitTestable()` 筛出来的就是子级里那颗重复的父行表头。
    await tester.tap(find.textContaining('组甲').hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('甲一'), findsNothing, reason: '子项该随这一层一起收回去');
    expect(
      find.textContaining('组甲'),
      findsOneWidget,
      reason: '退一层之后菜单必须还开着，否则表头等于「关掉」',
    );

    // 判据 4：退回顶层之后换另一个父行，展开的是它自己的子项。
    await tester.tap(find.textContaining('组乙'));
    await tester.pumpAndSettle();
    expect(find.text('乙一'), findsOneWidget);
    expect(find.text('甲一'), findsNothing);

    // 判据 3：`PopScope(canPop: topIndex == 0)` —— 系统返回键（Esc / Android back）
    // 走的是同一个 `maybePop`，在二级里也只能退一层，不能把整个菜单关掉。
    // （刻意不用 `tester.pageBack()`：那是点 Scaffold 那枚 'Back' 提示的助手，
    //  模态弹层上没有那枚按钮，它会直接 fail，量的不是这条路。）
    await tester
        .state<NavigatorState>(find.byType(Navigator))
        .maybePop();
    await tester.pumpAndSettle();

    expect(find.text('乙一'), findsNothing);
    expect(
      find.textContaining('组乙'),
      findsOneWidget,
      reason: '返回键在二级里是退一层，不是关菜单',
    );
  });

  testWidgets('点叶子落账并收起整个菜单，content 那一行不抢点击', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('组甲'));
    await tester.pumpAndSettle();

    // 判据 5 的前半：content 行在二级里画得出来，点它不关菜单也不落账。
    expect(find.byKey(_subContentKey), findsOneWidget);
    await tester.tap(find.byKey(_subContentKey), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('甲一'), findsOneWidget);
    expect(opened, isEmpty);

    await tester.tap(find.text('甲二'));
    await tester.pumpAndSettle();

    expect(opened, ['甲二']);
    expect(
      find.byTooltip('更多'),
      findsOneWidget,
      reason: '菜单该收起，回到那颗触发键',
    );
    expect(find.text('甲二'), findsNothing);
  });
}
