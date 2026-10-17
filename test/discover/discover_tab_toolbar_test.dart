import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_list/view/comic_list_page.dart';
import 'package:zephyr/page/discover/service/discover_tab_toolbar.dart';
import 'package:zephyr/page/discover/service/discover_tabs.dart';
import 'package:zephyr/page/discover/widgets/discover_plat_view.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation_button.dart';

Widget _app(Widget child) => MaterialApp(
  home: BlocProvider(
    create: (_) => GlobalSettingCubit(),
    child: Scaffold(body: child),
  ),
);

DiscoverTabs _tabs(DiscoverTabBarSide side) => DiscoverTabs(
  side: side,
  home: DiscoverLeafSpec(
    label: '发现',
    source: '',
    pluginName: '',
    iconUrl: '',
    content: (_) => const SizedBox(),
  ),
);

Widget _view(DiscoverTabs tabs, DiscoverTabBarSide side) => DiscoverPlatView(
  tabs: tabs,
  setting: DiscoverSettingState(tabSide: side),
  onSearch: () {},
  onCustomizeOrder: () {},
);

void main() {
  for (final side in [DiscoverTabBarSide.top, DiscoverTabBarSide.left]) {
    testWidgets('$side：漫画列表删除重复标题栏，设置入口进入 tab 工具栏', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tabs = _tabs(side);
      tabs.open(
        label: '最新',
        source: '',
        content: (_) => const ComicListPage(title: '最新'),
      );
      await tester.pumpWidget(_app(_view(tabs, side)));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('最新'), findsOneWidget);
      expect(find.byTooltip(LibraryPresentationButton.tooltip), findsOneWidget);
      tabs.goHome();
      await tester.pumpAndSettle();
      expect(find.byTooltip(LibraryPresentationButton.tooltip), findsNothing);
      await tester.pumpWidget(const SizedBox());
      tabs.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('独立路由仍保留标题与设置入口', (tester) async {
    await tester.pumpWidget(_app(const ComicListPage(title: '最新')));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('最新'), findsOneWidget);
    expect(find.byTooltip(LibraryPresentationButton.tooltip), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换标签时工具栏只打开当前标签的设置，关闭后无残留', (tester) async {
    final tabs = _tabs(DiscoverTabBarSide.top);
    tabs.open(label: '甲', source: '', content: (_) => const _ToolbarProbe('甲'));
    final first = tabs.tabs.last.id;
    tabs.open(label: '乙', source: '', content: (_) => const _ToolbarProbe('乙'));
    final second = tabs.tabs.last.id;
    await tester.pumpWidget(_app(_view(tabs, DiscoverTabBarSide.top)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(LibraryPresentationButton.tooltip));
    await tester.pumpAndSettle();
    expect(find.text('乙的设置'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    tabs.controller.focus(first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(LibraryPresentationButton.tooltip));
    await tester.pumpAndSettle();
    expect(find.text('甲的设置'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    tabs.close(first);
    tabs.close(second);
    await tester.pumpAndSettle();
    expect(find.byTooltip(LibraryPresentationButton.tooltip), findsNothing);
    await tester.pumpWidget(const SizedBox());
    tabs.dispose();
    expect(tester.takeException(), isNull);
  });
  testWidgets('长按只走正文登记的快速开关，不打开设置面板', (tester) async {
    var toggles = 0;
    final tabs = _tabs(DiscoverTabBarSide.top);
    tabs.open(
      label: '甲',
      source: '',
      content: (_) => _ToolbarProbe('甲', onToggle: () => toggles++),
    );
    await tester.pumpWidget(_app(_view(tabs, DiscoverTabBarSide.top)));
    await tester.pumpAndSettle();
    await tester.longPress(find.byTooltip(LibraryPresentationButton.tooltip));
    await tester.pumpAndSettle();
    expect(toggles, 1);
    expect(find.text('甲的设置'), findsNothing);
    // 没有登记开关的正文：长按不留半截手势。
    tabs.close(tabs.tabs.last.id);
    tabs.open(label: '乙', source: '', content: (_) => const _ToolbarProbe('乙'));
    await tester.pumpAndSettle();
    await tester.longPress(find.byTooltip(LibraryPresentationButton.tooltip));
    await tester.pumpAndSettle();
    expect(toggles, 1);
    await tester.pumpWidget(const SizedBox());
    tabs.dispose();
    expect(tester.takeException(), isNull);
  });
}

class _ToolbarProbe extends StatefulWidget {
  const _ToolbarProbe(this.label, {this.onToggle});
  final String label;

  /// 正文登记的展墙快开关；不传时长按应当没有任何动作。
  final VoidCallback? onToggle;
  @override
  State<_ToolbarProbe> createState() => _ToolbarProbeState();
}

class _ToolbarProbeState extends State<_ToolbarProbe> {
  DiscoverTabToolbarController? controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = DiscoverTabToolbarScope.maybeOf(context);
    if (identical(next, controller)) return;
    controller?.unregister(this);
    controller = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller?.register(
        this,
        (anchor) => showPopupPanel<void>(
          context: anchor,
          builder: (popup) => PopupPanel(
            title: Text('${widget.label}的设置'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(popup),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
        togglePresentation: widget.onToggle,
      );
    });
  }

  @override
  void dispose() {
    controller?.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
