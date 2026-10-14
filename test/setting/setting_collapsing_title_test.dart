/// 设置页折叠大标题的回读：进入时是大标题，滚动后缩成常驻小栏。
///
/// # 为什么这条要量几何而不是「widget 在不在」
/// 「折叠」这件事唯一可观测的结果是**同一份内容在滚动前后离视口顶部的距离变了**，
/// 以及标题在两态都还在（pinned）。只断言 `find.byType(M3EAppBar)` 有一条，
/// 换谁都能交出一张「有顶栏但根本不折叠」的壳子还全绿。
///
/// # 两条写法上的钉子（都是这一轮自己踩的）
/// 文案一律走 `t.…`，不写字面量：测试里 `t` 的默认档不一定是中文，写死「书架」会得到
/// `Found 0 widgets`，看着像顶栏没渲染。
/// 拖动距离必须越过滚动 slop：`-12` 那种会被识别成「点一下」，直接撞上开关行的落库路径。
library;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/setting/bookshelf/bookshelf_setting_page.dart';
import 'package:zephyr/page/setting/global/file_manager_setting_page.dart';
import 'package:zephyr/page/setting/global/storage_setting_page.dart';
import 'package:zephyr/page/theme_color/view/theme_color_page.dart';
import 'package:zephyr/page/setting/global/sync_setting_page.dart';
import 'package:zephyr/page/setting/global/toast_setting_page.dart';
import 'package:zephyr/page/about/view/about_page.dart';
import 'package:zephyr/page/font_setting/view/font_setting_page.dart';
import 'package:zephyr/page/setting/common/setting_detail_scope.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/page/setting/common/setting_route.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';

import '../test_helper.dart';

/// 应用里设置页不是普通 `MaterialPageRoute`，而是 [settingPageRoute]
/// （全屏 `CommonPopupRoute`，带自己的入场动画与锚点）。折叠顶栏必须在那条路上也成立，
/// 所以这里能把两种推送方式都跑起来。
Widget _host(Widget page, {bool viaSettingRoute = false}) => BlocProvider(
  create: (_) => GlobalSettingCubit(),
  child: MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              viaSettingRoute
                  ? settingPageRoute<void>(
                      context: context,
                      builder: (_) => page,
                    )
                  : MaterialPageRoute(builder: (_) => page),
            ),
            child: const Text('打开设置页'),
          ),
        ),
      ),
    ),
  ),
);

/// 内容第一张卡离视口顶部的距离：大标题展开时它被顶得低，收起后往上走。
double _contentTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(SettingGroup).first).dy;

Future<void> _open(
  WidgetTester tester,
  Widget page, {
  bool viaSettingRoute = false,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(page, viaSettingRoute: viaSettingRoute));
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开设置页'));
  await tester.pumpAndSettle();
}

void main() {
  // 开关行一点就落库，没库就只能验「展开态」那半屏。
  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    if (objectbox.userSettingBox.get(1) == null) {
      objectbox.userSettingBox.put(UserSetting());
    }
  });

  testWidgets('独立成页：大标题随内容滚走，缩回后标题仍常驻', (tester) async {
    await _open(tester, const BookshelfSettingPage());

    final title = find.descendant(
      of: find.byType(M3EAppBar),
      matching: find.text(t.settings.bookshelf),
    );
    expect(title, findsOneWidget, reason: '大标题没挂进 M3E 折叠顶栏');
    expect(
      find.byType(BackButton),
      findsOneWidget,
      reason: '折叠顶栏把返回键丢了，这一页就出不去',
    );

    final expanded = _contentTop(tester);
    // largeFlexible 那档展开是 120（带副标题 152），旧的实色小栏只有 72。
    expect(
      expanded,
      greaterThanOrEqualTo(110),
      reason: '进入页面没先看到大标题（内容顶只在 $expanded）',
    );

    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pumpAndSettle();

    final collapsed = _contentTop(tester);
    expect(
      collapsed,
      lessThan(expanded - 30),
      reason: '滚了 320，内容只上移 ${expanded - collapsed}，顶栏没跟着收',
    );
    expect(title, findsOneWidget, reason: '收起后标题该缩着留下，不是消失');
    expect(
      tester.widgetList<ListTile>(
        find.descendant(
          of: find.byType(SettingGroup),
          matching: find.byType(ListTile),
        ),
      ),
      isNotEmpty,
      reason: '折叠改动不该把分组表面弄丢',
    );
  });

  testWidgets('应用自己的路由（全屏弹层）里也一样折叠', (tester) async {
    await _open(tester, const BookshelfSettingPage(), viaSettingRoute: true);
    final expanded = _contentTop(tester);
    expect(
      find.byType(M3EAppBar),
      findsOneWidget,
      reason: 'CommonPopupRoute 里没挂上折叠顶栏',
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(_contentTop(tester), lessThan(expanded - 30), reason: '弹层路由里顶栏没跟着收');
    expect(
      find.descendant(
        of: find.byType(M3EAppBar),
        matching: find.text(t.settings.bookshelf),
      ),
      findsOneWidget,
      reason: '收起后标题该缩着留下',
    );
  });

  testWidgets('短页不为了能折叠而造内容', (tester) async {
    // 存储只有 1 张卡 4 行，是「一屏放得下」的那种页面。
    await _open(tester, const StorageSettingPage());
    // `SliverChildListDelegate.childList` 在这版 SDK 里是私有的，读不到列表项，
    // 那就数画出来的卡：外壳要是为了撑滚动而插东西，这里会多出来。
    expect(find.byType(SettingSectionCard), findsOneWidget);
    // 顶部也没被撑成一屏的「大标题占位」——展开高度就是顶栏那一档。
    expect(_contentTop(tester), lessThan(220));
  });

  // 逐页的大字号回归：顶栏是定高的（见 setting_ui.dart 里那段钳制的实测注释），
  // 每页的介绍长短不同，只守 setting_browser 那一条用例挡不住「某页介绍特别长」。
  // 表里刻意混了三种 body：裸 ListView（提示样式/文件管理器/同步/存储）、
  // AnimatedBuilder 包着 ListView 的（字体设置）、以及 SingleChildScrollView（主题色）——
  // NestedScrollView 只接受可滚动 body，第三种形态必须单独证一次。
  for (final (name, page) in <(String, Widget)>[
    ('提示样式', ToastSettingPage()),
    ('文件管理器', FileManagerSettingPage()),
    ('字体设置', FontSettingPage()),
    ('同步', SyncSettingPage()),
    ('主题色', ThemeColorPage()),
    ('存储', StorageSettingPage()),
    ('关于应用', AboutPage()),
  ]) {
    testWidgets('$name：textScale 2 的窄面板不顶穿顶栏', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cubit = GlobalSettingCubit();
      addTearDown(cubit.close);
      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: page,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$name 在 2 倍字号下溢出');
    });
  }

  testWidgets('双栏右栏不挂大标题（左栏已经写着这一页的名字）', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => GlobalSettingCubit(),
        child: MaterialApp(
          home: const SettingDetailScope(
            child: Scaffold(body: BookshelfSettingPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NestedScrollView), findsNothing);
    expect(find.byType(M3EAppBar), findsNothing);
    // 只有一处：小标题栏那一份。第一张卡过去也叫「书架」，
    // 现在大标题说过一遍就不重复了（见 setting_group.dart 的可空标题）。
    expect(find.text(t.settings.bookshelf), findsOneWidget);
  });
}
