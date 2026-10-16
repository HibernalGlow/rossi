import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/src/rust/api/file_manager/types.dart';
import 'package:zephyr/src/rust/api/file_ops.dart';
import 'package:zephyr/src/rust/api/local.dart';
import 'package:zephyr/src/rust/frb_generated.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_card.dart';
import 'package:zephyr/workspace/service/file_manager_tab_bridge.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_navigation_pad.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_content_layout.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_thumbnail.dart';
import 'package:zephyr/i18n/strings.g.dart';
part 'parts/file_manager_card_test_fakes_part.dart';
part 'parts/file_manager_card_test_fixture_part.dart';
part 'parts/file_manager_card_test_helper_part.dart';
part 'parts/file_manager_card_test_selection_part.dart';
part 'parts/file_manager_card_test_tabs_part.dart';
part 'parts/file_manager_card_test_layout_part.dart';
part 'parts/file_manager_card_test_search_part.dart';
part 'parts/file_manager_card_test_entry_tabs_part.dart';

// Fake only the FRB boundary. Render the real card with the same Material
// library as main.dart and no Scaffold/Material supplied by its host.

void main() {
  late _FileManagerApi api;
  late _TestGlobalSettingCubit settings;
  setUp(() {
    api = _FileManagerApi();
    settings = _TestGlobalSettingCubit();
    // 卡片在发出第一条桥调用**之前**要先读一次「上次打开的页签」（`_startSession` →
    // `FileManagerTabMemory.restore`），那一份住在 SharedPreferences 里。这里没有桩时
    // 那条 future 在 `testWidgets` 里永远不落地（同一次调用在裸 `test()` 里会立刻抛
    // MissingPluginException，所以 `read()` 的兜底在测试里救不到），于是每个用例都卡在
    // `_pumpCard` 的 pumpAndSettle 上。给一个空档，比让整张卡片的测试全哑便宜。
    SharedPreferences.setMockInitialValues({});
    RustLib.initMock(api: api);
    // 启动期才解析的路径，测试里默认按「还没解析出来」起跑；需要它的用例自己注入。
    preparedSettingsDbPathForTests = null;
  });
  // FRB 2.12 的 `RustLib.dispose()` 只关端口管理器，**不**清 `_EntrypointState`，
  // 所以下一个用例的 `initMock` 会撞「Should not initialize flutter_rust_bridge twice」，
  // 整个文件只有第一个用例能跑。`resetState()` 是它留给测试的出口。
  tearDown(() {
    RustLib.dispose();
    // ignore: invalid_use_of_internal_member
    RustLib.instance.resetState();
  });

  // 多选模式那几条在 `parts/file_manager_card_test_selection_part.dart`：
  // 宿主函数的局部变量对 part 不可见，所以把「当前这一个 api」以取值函数的形式递进去
  // （直接传实例会传错 —— `setUp` 每个用例换一个新的）。
  _selectionTapTests(() => api);
  _tabMenuTests(() => api);
  _layoutTests(() => api);
  _searchTests(() => api);
  _entryTabTests(() => api);

  for (final width in [260.0, 340.0, 700.0]) {
    for (final mode in FileManagerViewMode.values) {
      testWidgets('Material 祖先与 $width 宽度 $mode 含多条子文件名不报错', (tester) async {
        api.snapshot = _snapshot(viewMode: mode, columnsEnabled: true);
        await _pumpCard(tester, width: width);
        expect(tester.takeException(), isNull);
        expect(find.byType(InputChip), findsWidgets);
        expect(find.byType(ActionChip), findsOneWidget);
        expect(find.text('book.cbz'), findsOneWidget);
        // The popup also needs matching MaterialLocalizations, not SDK ones.
        await _openTabMenu(tester, 'books');
        await tester.pumpAndSettle();
        expect(find.text('固定页签'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('「显示快速切换栏」收掉那一排胶囊，再开立刻回来', (tester) async {
    await _pumpCard(tester, settings: settings);
    // 证伪前提：夹具的快照里真有一个 root，默认开着时它必须画得出来。
    // 少了这一句，下面的 `findsNothing` 有可能只是「从来就没画过」。
    expect(find.byType(ActionChip), findsOneWidget);

    final more = find.byTooltip('更多');
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示快速切换栏'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(settings.state.fileManagerSetting.showRootsBar, isFalse);
    expect(find.byType(ActionChip), findsNothing);
    // 收掉的只是卡片外壳上那一行，浏览本身照常。
    expect(find.text('book.cbz'), findsOneWidget);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示快速切换栏'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(settings.state.fileManagerSetting.showRootsBar, isTrue);
    expect(find.byType(ActionChip), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('导航掌五个方向各自派发对应动作，互不抢事件', (tester) async {
    api.snapshot = _snapshot(
      canGoBack: true,
      canGoForward: true,
      homePath: '/home',
    );
    await _pumpCard(tester);

    // 每片热区都是被 ClipPath 裁过的多边形：点在轮廓里才算命中。
    // 取点还要避开中心的刷新圆（它占中间 0.28~0.72 那一块并且压在四片之上），
    // 否则点「左」会点成「刷新」—— 这正是这个用例要守住的行为。
    await tester.tapAt(_padPoint(tester, const Offset(0.15, 0.5)));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerBrowseFileManagerGoBack),
      hasLength(1),
    );

    await tester.tapAt(_padPoint(tester, const Offset(0.85, 0.5)));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerBrowseFileManagerGoForward),
      hasLength(1),
    );

    await tester.tapAt(_padPoint(tester, const Offset(0.5, 0.2)));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerBrowseFileManagerGoUp),
      hasLength(1),
    );

    // 中心圆：刷新。它压在四片热区之上，这一块必须归它。
    await tester.tapAt(_padPoint(tester, const Offset(0.5, 0.5)));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerBrowseFileManagerRefresh),
      hasLength(1),
    );
    // 上一步不能顺带把「主页」也触发了。
    expect(api.callsTo(#crateApiFileManagerBrowseFileManagerGoHome), isEmpty);

    await _tapHomeRegion(tester);
    expect(
      api.callsTo(#crateApiFileManagerBrowseFileManagerGoHome),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('卡片够宽时导航摊开成五颗标准键，掌形不画', (tester) async {
    api.snapshot = _snapshot(
      canGoBack: true,
      canGoForward: true,
      homePath: '/home',
    );
    await _pumpCard(tester, width: 700);

    expect(find.byType(FileManagerNavigationPad), findsNothing);
    // 动作与掌形一一对应，tooltip 文案也是同一份 —— 换画法不换语义。
    for (final tip in ['后退', '前进', '上一级', '刷新']) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    expect(_homeRegion(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('摊开形态各自派发对应动作，主页那颗右键也弹菜单', (tester) async {
    api.snapshot = _snapshot(
      canGoBack: true,
      canGoForward: true,
      homePath: '/home',
    );
    await _pumpCard(tester, width: 700);

    await tester.tap(find.byTooltip('后退'));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerBrowseFileManagerGoBack),
      hasLength(1),
    );

    await tester.tap(find.byTooltip('前进'));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerBrowseFileManagerGoForward),
      hasLength(1),
    );

    await tester.tap(find.byTooltip('上一级'));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerBrowseFileManagerGoUp),
      hasLength(1),
    );

    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerBrowseFileManagerRefresh),
      hasLength(1),
    );
    expect(api.callsTo(#crateApiFileManagerBrowseFileManagerGoHome), isEmpty);

    await _tapHomeRegion(tester);
    expect(
      api.callsTo(#crateApiFileManagerBrowseFileManagerGoHome),
      hasLength(1),
    );

    // 右键入口挂在按钮外层：桌面端不必先长按。
    await tester.tapAt(_homeRegionPoint(tester), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('回到主页'), findsOneWidget);
    expect(find.text('把当前目录设为主页'), findsOneWidget);
    expect(find.text('清除主页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('工具栏整行只有一个几何档：图标钮 40 见方', (tester) async {
    api.snapshot = _snapshot(
      canGoBack: true,
      canGoForward: true,
      homePath: '/home',
    );
    await _pumpCard(tester, width: 700);

    // 40 是 MD3 图标按钮的规范边长；写死数字而不是引常量，否则改坏常量测不出来。
    const md3Button = Size(40, 40);
    for (final tip in [
      '后退',
      '刷新',
      '条目样式：封面列表',
      '排序：名称',
      '搜索（空格分词，-排除）',
      '内容布局：内容视图',
      '关闭穿透模式',
      '更多',
    ]) {
      expect(tester.getRect(find.byTooltip(tip)).size, md3Button, reason: tip);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('收起形态的掌与摊开时同高，整行只有一个高度带', (tester) async {
    api.snapshot = _snapshot(
      canGoBack: true,
      canGoForward: true,
      homePath: '/home',
    );
    await _pumpCard(tester, width: 340);

    expect(find.byType(FileManagerNavigationPad), findsOneWidget);
    expect(
      tester.getRect(find.byType(FileManagerNavigationPad)).size,
      const Size(40, 40),
    );
    expect(tester.getRect(find.byTooltip('更多')).size, const Size(40, 40));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('未设主页时单击即设主页，并写回全局设置', (tester) async {
    // 未设主页时不再禁用：第一次用的人不必先猜「要长按/右键」。
    settings = _TestGlobalSettingCubit();
    await _pumpCard(tester, settings: settings);

    // 卡片内部快照只随动作的**返回值**更新，所以先把 mock 换成「已接受该主页」，
    // 再点 —— 用来断言卡片落盘的确实是核心接受后的那个路径。
    api.snapshot = _snapshot(homePath: '/books');
    await _tapHomeRegion(tester);

    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerSetHomePath)
          .single
          .namedArguments[#path],
      '/books',
    );
    expect(settings.state.fileManagerSetting.homePath, '/books');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('已设主页时单击回主页，长按菜单里可改设与清除', (tester) async {
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(homePath: '/home'),
    );
    api.snapshot = _snapshot(homePath: '/home');
    await _pumpCard(tester, settings: settings);

    await _tapHomeRegion(tester);
    expect(
      api.callsTo(#crateApiFileManagerBrowseFileManagerGoHome),
      hasLength(1),
    );

    // 长按打开主页菜单：三个动作按当前能力置灰。
    await _longPressHomeRegion(tester);
    expect(find.text('回到主页'), findsOneWidget);
    expect(find.text('把当前目录设为主页'), findsOneWidget);
    expect(find.text('清除主页'), findsOneWidget);

    await tester.tap(find.text('把当前目录设为主页'));
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerSetHomePath)
          .single
          .namedArguments[#path],
      '/books',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('主页键可被全局设置关掉', (tester) async {
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(homeEnabled: false),
    );
    await _pumpCard(tester, settings: settings);
    expect(_homeRegion(), findsNothing);
    // 其余导航方向不受影响：掌还在，四个方向加中心刷新都还在。
    expect(find.byType(FileManagerNavigationPad), findsOneWidget);
    expect(find.byTooltip('刷新'), findsOneWidget);
    expect(find.byTooltip('后退'), findsOneWidget);
    expect(find.byTooltip('上一级'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('会话创建时带上落盘的主页', (tester) async {
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(homePath: '/home'),
    );
    await _pumpCard(tester, settings: settings);
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerCreate)
          .single
          .namedArguments[#homePath],
      '/home',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('没设过主页时不传参数，会话保持未设主页', (tester) async {
    settings = _TestGlobalSettingCubit();
    await _pumpCard(tester, settings: settings);
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerCreate)
          .single
          .namedArguments[#homePath],
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('开了「启动时默认打开主页」后会话直接落在主页目录', (tester) async {
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(
        homePath: '/home',
        openHomeOnStart: true,
      ),
    );
    await _pumpCard(tester, settings: settings);
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerCreate)
          .single
          .namedArguments[#initialPath],
      '/home',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('开关默认关着：不传 initialPath，由核心选默认目录', (tester) async {
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(homePath: '/home'),
    );
    await _pumpCard(tester, settings: settings);
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerCreate)
          .single
          .namedArguments[#initialPath],
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('主页键关掉后启动落点跟着失效，不出现「主页没了却还往里跳」', (tester) async {
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(
        homeEnabled: false,
        homePath: '/home',
        openHomeOnStart: true,
      ),
    );
    await _pumpCard(tester, settings: settings);
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerCreate)
          .single
          .namedArguments[#initialPath],
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('开着开关但还没设主页时不传 initialPath', (tester) async {
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(openHomeOnStart: true),
    );
    await _pumpCard(tester, settings: settings);
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerCreate)
          .single
          .namedArguments[#initialPath],
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('会话创建时带上设置库路径与记忆开关', (tester) async {
    preparedSettingsDbPathForTests = '/tmp/rossi/settings.db';
    settings = _TestGlobalSettingCubit(
      fileManagerSetting: const FileManagerSettingState(
        rememberViewState: false,
      ),
    );
    await _pumpCard(tester, settings: settings);

    final args = api
        .callsTo(#crateApiFileManagerBrowseFileManagerCreate)
        .single
        .namedArguments;
    expect(args[#settingsDbPath], '/tmp/rossi/settings.db');
    expect(args[#rememberViewState], isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('路径还没解析出来时按不记忆建会话，而不是卡在加载态', (tester) async {
    preparedSettingsDbPathForTests = null;
    await _pumpCard(tester);

    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerCreate)
          .single
          .namedArguments[#settingsDbPath],
      isNull,
    );
    expect(find.text('book.cbz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('全局关掉记忆后同步给活着的会话，且不重复打桥', (tester) async {
    await _pumpCard(tester, settings: settings);
    expect(
      api.callsTo(#crateApiFileManagerSettingsFileManagerSetRememberViewState),
      isEmpty,
    );

    settings.updateFileManagerSetting(
      (current) => current.copyWith(rememberViewState: false),
    );
    await tester.pumpAndSettle();

    final calls = api.callsTo(
      #crateApiFileManagerSettingsFileManagerSetRememberViewState,
    );
    expect(calls, hasLength(1));
    expect(calls.single.namedArguments[#enabled], isFalse);

    // 假 API 不会像 Rust 那样把新值写回快照，所以这里正好验「每次用户改动最多补发一次」：
    // 没有守卫的话每帧都会再发一次。
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerSettingsFileManagerSetRememberViewState),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('排序菜单提供日期与随机字段并可开临时排序', (tester) async {
    await _pumpCard(tester);
    final sortButton = find.byTooltip('排序：名称');
    await tester.ensureVisible(sortButton);
    await tester.tap(sortButton);
    await tester.pumpAndSettle();

    expect(find.text('修改日期'), findsOneWidget);
    expect(find.text('随机'), findsOneWidget);
    expect(find.text('临时排序（不记住本目录）'), findsOneWidget);

    await tester.tap(find.text('随机'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerSettingsFileManagerSetSort)
          .single
          .namedArguments[#field],
      FileManagerSortField.random,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('临时排序按当前快照取反后提交', (tester) async {
    api.snapshot = _snapshot(sortTemporary: true);
    await _pumpCard(tester);
    final sortButton = find.byTooltip('排序：名称');
    await tester.ensureVisible(sortButton);
    await tester.tap(sortButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('临时排序（不记住本目录）'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerSettingsFileManagerSetSortTemporary)
          .single
          .namedArguments[#enabled],
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('类型筛选在更多菜单的二级里，点开父行才提交到 Rust', (tester) async {
    await _pumpCard(tester);
    final more = find.byTooltip('更多');
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();

    // 顶层只剩带当前值的那一行父项。三条负断言是 subItems 折叠的证伪：
    // 二级要是没真收起来（或者父行标签没接到当前快照），这里当场红。
    expect(find.text('类型：全部'), findsOneWidget);
    expect(find.text('类型：图片'), findsNothing);
    expect(find.text('图片'), findsNothing);

    await tester.tap(find.text('类型：全部'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('图片'), findsOneWidget);

    await tester.tap(find.text('图片'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerSettingsFileManagerSetEntryFilter)
          .single
          .namedArguments[#filter],
      FileManagerEntryFilter.images,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final height in [260.0, 760.0]) {
    testWidgets('独立面板在 $height 高度自带 Material 且不溢出', (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      api.snapshot = _snapshot(columnsEnabled: true);
      await tester.pumpWidget(
        BlocProvider<GlobalSettingCubit>.value(
          value: _TestGlobalSettingCubit(),
          child: MaterialApp(
            home: Center(
              child: SizedBox(
                width: 340,
                height: height,
                child: FileManagerCard(
                  isExpanded: true,
                  onToggle: () {},
                  isStandalone: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('book.cbz'), findsOneWidget);
      final root = find.byType(ActionChip);
      await tester.ensureVisible(root);
      await tester.pumpAndSettle();
      await tester.tap(root);
      await tester.pumpAndSettle();
      expect(
        api
            .callsTo(#crateApiFileManagerBrowseFileManagerNavigate)
            .single
            .namedArguments[#path],
        '/home',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('归档双击只发一次打开归档，普通单击仍使用 Neo 打开动作', (tester) async {
    await _pumpCard(tester);
    await tester.tap(find.text('book.cbz'));
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tap(find.text('book.cbz'));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerEntryOpsFileManagerOpenArchive),
      hasLength(1),
    );
    expect(
      api.callsTo(#crateApiFileManagerEntryOpsFileManagerOpenEntry),
      isEmpty,
    );
    await tester.tap(find.text('book.cbz'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(
      api.callsTo(#crateApiFileManagerEntryOpsFileManagerOpenEntry),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('会穿透的文件夹行：双击只发一次强制进入，单击仍是穿透打开', (tester) async {
    api.snapshot = _snapshot(folderPenetratable: true);
    await _pumpCard(tester);
    final openEntry = #crateApiFileManagerEntryOpsFileManagerOpenEntry;
    final folder = find.text('series with a long name');

    await tester.tap(folder);
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tap(folder);
    await tester.pumpAndSettle();
    final forced = api.callsTo(openEntry).toList();
    expect(forced, hasLength(1));
    expect(
      forced.single.namedArguments[#forceEnter],
      isTrue,
      reason: '双击的含义是「进这一层」，必须把穿透绕过去',
    );
    expect(
      api.callsTo(#crateApiFileManagerEntryOpsFileManagerOpenArchive),
      isEmpty,
    );

    // 单击：等满双击窗口才是「穿透打开」，窗口内一条桥都不许发出去。
    await tester.tap(folder);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      api.callsTo(openEntry),
      hasLength(1),
      reason: '第一击要等第二击的判决，不能抢先把书打开',
    );
    await tester.pump(const Duration(milliseconds: 400));
    final tapped = api.callsTo(openEntry).toList();
    expect(tapped, hasLength(2));
    expect(
      tapped.last.namedArguments[#forceEnter],
      isFalse,
      reason: '单击保持原样：交出去的还是穿透后的那一本',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('判成不可穿透的文件夹行不挂双击：单击不等双击窗口', (tester) async {
    await _pumpCard(tester);
    await tester.tap(find.text('series with a long name'));
    await tester.pump(const Duration(milliseconds: 100));
    // 与上一条同一把尺的反面：这里 100ms 就必须已经发出去 ——
    // 挂上双击识别器的代价是那 300ms，双击没意义的行不该替它付。
    final call = api
        .callsTo(#crateApiFileManagerEntryOpsFileManagerOpenEntry)
        .single;
    expect(call.namedArguments[#forceEnter], isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('按钮是否可用直接使用 Rust 能力，不在 Dart 重算页签规则', (tester) async {
    api.snapshot = _snapshot(canCreate: false, canClose: false);
    await _pumpCard(tester);
    expect(
      tester
          .widget<IconButton>(
            // 「新建页签」按钮已换成自绘 `GlyphIcon(AppGlyphs.add)`，
            // `find.widgetWithIcon` 只认 Material `Icon` ⇒ 从 glyph 往上找这颗按钮。
            find.ancestor(
              of: find.byWidgetPredicate(
                (w) => w is GlyphIcon && w.glyph == AppGlyphs.add,
              ),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<InputChip>(find.byType(InputChip).first).onDeleted,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('初始化快照失败后重试复用同一 Rust 会话', (tester) async {
    api.snapshotError = StateError('cannot read directory');
    await _pumpCard(tester);
    expect(find.text('重试'), findsOneWidget);
    api.snapshotError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerBrowseFileManagerCreate),
      hasLength(1),
    );
    expect(find.text('book.cbz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      api.callsTo(#crateApiFileManagerSettingsFileManagerClose),
      hasLength(1),
    );
  });

  testWidgets('文件与文件夹缩略图组件存在且平滑回退语义图标', (tester) async {
    await _pumpCard(tester);
    expect(find.byType(FileManagerThumbnailWidget), findsWidgets);
    // 语义图标已换成自绘 `GlyphIcon`：归档 → openBook、目录 → folder。
    // `find.byIcon` 只认 Material `Icon`；而迁移把「同一语义只许一颗图标」落到了
    // 实处 —— 这颗 folder 现在还被「进入文件夹」按钮与条目徽标共用（全树 3 处）
    // ⇒ 断言**限定在缩略图子树内**，认的仍是「缩略图回退成语义图标」这件事。
    Finder fallback(Glyph glyph) => find.descendant(
      of: find.byType(FileManagerThumbnailWidget),
      matching: find.byWidgetPredicate(
        (w) => w is GlyphIcon && w.glyph == glyph,
      ),
    );
    expect(fallback(AppGlyphs.openBook), findsOneWidget);
    expect(fallback(AppGlyphs.folder), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('工具栏包含 NeoView 风格视图模式菜单并支持切换', (tester) async {
    await _pumpCard(tester);
    final menuButton = find.byTooltip('条目样式：封面列表');
    expect(menuButton, findsOneWidget);

    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    expect(find.text('紧凑列表'), findsOneWidget);
    expect(find.text('封面列表'), findsOneWidget);
    expect(find.text('横幅'), findsOneWidget);
    expect(find.text('详细信息'), findsOneWidget);
    expect(find.text('封面网格'), findsOneWidget);
    expect(find.text('自由缩略图'), findsOneWidget);

    await tester.tap(find.text('详细信息'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      api
          .callsTo(#crateApiFileManagerSettingsFileManagerSetViewMode)
          .single
          .namedArguments[#mode],
      FileManagerViewMode.details,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('详细信息视图渲染表头并支持点击表头字段排序', (tester) async {
    api.snapshot = _snapshot(viewMode: FileManagerViewMode.details);
    await _pumpCard(tester, width: 700);

    expect(find.text('名称'), findsWidgets);
    expect(find.text('类型'), findsWidgets);
    expect(find.text('大小'), findsWidgets);
    expect(find.text('修改时间'), findsWidgets);

    // 点击“大小”表头列切换排序
    await tester.tap(find.text('大小').first);
    await tester.pumpAndSettle();

    expect(
      api
          .callsTo(#crateApiFileManagerSettingsFileManagerSetSort)
          .last
          .namedArguments[#field],
      FileManagerSortField.size,
    );

    // 点击“修改时间”表头列切换排序
    await tester.tap(find.text('修改时间').first);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerSettingsFileManagerSetSort)
          .last
          .namedArguments[#field],
      FileManagerSortField.date,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('单页签时收起整行页签，新建与恢复搬到路径操作菜单', (tester) async {
    api.snapshot = _snapshot(tabCount: 1);
    await _pumpCard(tester);
    expect(find.byType(InputChip), findsNothing);
    expect(find.byTooltip('新建页签'), findsNothing);
    expect(find.byTooltip('恢复已关闭页签'), findsNothing);

    await tester.tap(find.byTooltip('路径操作'));
    await tester.pumpAndSettle();
    expect(find.text('新建页签'), findsOneWidget);
    await tester.tap(find.text('恢复页签：closed'));
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerReopenClosedTab)
          .single
          .namedArguments[#tabId],
      BigInt.from(3),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('面包屑左对齐：放得下的路径不顶到行尾', (tester) async {
    await _pumpCard(tester, width: 260);
    final scroll = find.byKey(const ValueKey('file-manager-breadcrumb-scroll'));
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('file-manager-breadcrumb:/')))
          .dx,
      closeTo(tester.getTopLeft(scroll).dx, 1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
