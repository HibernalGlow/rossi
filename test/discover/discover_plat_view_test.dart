// 只用 material_ui：它自带一套 MaterialApp / Scaffold / Icons（与主应用同一套），
// 再 import flutter/material 会得到一堆二义名。
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:plat/plat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
import 'package:zephyr/page/discover/service/discover_tabs.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/widgets/discover_plat_view.dart';
import 'package:zephyr/workspace/router/workspace_lane_dispatch.dart';
import 'package:zephyr/workspace/widgets/containers/embedded_upstream_page.dart';

/// 标签条的悬停判据。
///
/// 起因：实机日志里刷了一串 `MouseTracker` 的 `!_debugDuringDeviceUpdate` 断言。
/// 那条断言是**次生**的 —— `_deviceUpdatePhase` 里的异常会跳过复位标志，之后每帧都撞。
/// 所以这里要抓的是「悬停标签/关闭钮/tooltip 时抛的第一异常」。
DiscoverTabs _tabs() => DiscoverTabs(
  side: DiscoverTabBarSide.top,
  home: DiscoverLeafSpec(
    label: '发现',
    source: '',
    pluginName: '',
    iconUrl: '',
    content: (context) => const SizedBox(width: 40, height: 40),
  ),
);

Future<void> _pump(
  WidgetTester tester,
  DiscoverTabs tabs, {
  Size surface = const Size(800, 600),
  bool centered = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      // 与 main.dart 的根一致：少了这几位 delegate，PopupMenuButton 会先抛
      // 「No MaterialLocalizations」，然后它的 ErrorWidget 把标签条撑爆 ——
      // 那会把这个判据本身带偏。
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: BlocProvider(
        create: (_) => GlobalSettingCubit(),
        child: Scaffold(
          body: Align(
            alignment: centered ? Alignment.center : Alignment.topLeft,
            child: SizedBox(
              width: surface.width,
              height: surface.height,
              child: DiscoverPlatView(
                tabs: tabs,
                setting: const DiscoverSettingState(),
                onSearch: () {},
                onCustomizeOrder: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 拖一条标签：`Draggable<TabDragPayload>` 的整条链路（拖起、跟随指针的浮层、
/// 落点判定）都要过一遍 —— 这是标签条上唯一会在指针移动中途改命中树的动作。
Future<void> _dragChip(WidgetTester tester, String from, Offset delta) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  await gesture.moveTo(tester.getCenter(find.text(from).first));
  await tester.pumpAndSettle();
  await gesture.down(tester.getCenter(find.text(from).first));
  await tester.pumpAndSettle();
  for (var step = 1; step <= 6; step++) {
    await gesture.moveBy(Offset(delta.dx / 6, delta.dy / 6));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  await gesture.up();
  await tester.pumpAndSettle();
  await gesture.removePointer();
}

/// 探针：叶子内容被建了几次。
///
/// 帧自循环在测试里只有两种露脸方式 —— `pumpAndSettle` 超时，或者把某个
/// 子树的重建次数推到几百。所以这里数它。
int _leafBuilds = 0;

Widget _probedLeaf() {
  _leafBuilds++;
  return const SizedBox(width: 40, height: 40);
}

/// 真实宿主：发现页在工作台里住在 `EmbeddedUpstreamPage` 之下 —— 那层带一个
/// `Listener(onPointerDown)` 与一条局部 Navigator。指针进出的配对要在那一层
/// 也走一遍，不然测不到「hover 回调里改了命中树」这类重入。
Future<void> _pumpInLaneHost(WidgetTester tester, DiscoverTabs tabs) async {
  _leafBuilds = 0;
  await tester.pumpWidget(
    MaterialApp(
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: BlocProvider(
        create: (_) => GlobalSettingCubit(),
        child: Scaffold(
          body: EmbeddedUpstreamPage(
            host: const WorkspaceLaneHost('right', 'discover'),
            instanceKey: 'discover',
            isVisible: true,
            builder: (context) => DiscoverPlatView(
              tabs: tabs,
              setting: const DiscoverSettingState(),
              onSearch: () {},
              onCustomizeOrder: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 只做内存写入的设置 cubit。
///
/// 生产那份 `updateDiscoverSetting` 会落 ObjectBox，而本机测试起不来那套原生库；
/// 菜单点选要验的是「点完不抛、树跟着转」，与持久化无关，所以这里只 emit。
class _MemSettingCubit extends GlobalSettingCubit {
  @override
  void updateDiscoverSetting(
    DiscoverSettingState Function(DiscoverSettingState current) updates,
  ) {
    emit(state.copyWith(discoverSetting: updates(state.discoverSetting)));
  }
}

Future<void> _pumpTuneMenuHost(WidgetTester tester, DiscoverTabs tabs) async {
  await tester.pumpWidget(
    MaterialApp(
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: BlocProvider<GlobalSettingCubit>(
        // 类型参数要写 GlobalSettingCubit：_DisplayOptionsButton 读的是它，
        // 传子类型只会让 Provider 找不到。
        create: (_) => _MemSettingCubit(),
        child: Scaffold(
          body: DiscoverPlatView(
            tabs: tabs,
            setting: const DiscoverSettingState(),
            onSearch: () {},
            onCustomizeOrder: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 带身份的叶子：State 对象被销毁重建 = 「重挂」，也就是用户说的「重载」。
class _LeafStateProbe extends StatefulWidget {
  const _LeafStateProbe();

  @override
  State<_LeafStateProbe> createState() => _LeafStateProbeState();
}

class _LeafStateProbeState extends State<_LeafStateProbe> {
  static final List<_LeafStateProbeState> live = <_LeafStateProbeState>[];

  @override
  void initState() {
    super.initState();
    live.add(this);
  }

  @override
  void dispose() {
    live.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 40, height: 40);
}

void main() {
  testWidgets('只有一条标签时画得出来，且不抛', (tester) async {
    final tabs = _tabs();
    await _pump(tester, tabs);
    expect(tester.takeException(), isNull);
    expect(find.text('发现'), findsWidgets);
    tabs.dispose();
  });

  testWidgets('开两条标签后悬停到标签上，不抛异常', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '排行',
      source: 'p1',
      content: (context) => const SizedBox(width: 40, height: 40),
    );
    await _pump(tester, tabs);
    expect(tester.takeException(), isNull);

    final chip = find.text('排行');
    expect(chip, findsOneWidget);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(chip));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await gesture.removePointer();
    tabs.dispose();
  });

  testWidgets('悬停关闭按钮再移开，不抛异常', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '最新',
      source: 'p1',
      content: (context) => const SizedBox(width: 40, height: 40),
    );
    await _pump(tester, tabs);

    final close = find.byIcon(Icons.close);
    expect(close, findsWidgets);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(close.first));
    await tester.pumpAndSettle();
    await gesture.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await gesture.removePointer();
    tabs.dispose();
  });

  testWidgets('横向拖一条标签换序，不抛异常', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '排行',
      source: 'p1',
      content: (context) => const SizedBox(width: 40, height: 40),
    );
    tabs.open(
      label: '最新',
      source: 'p1',
      content: (context) => const SizedBox(width: 40, height: 40),
    );
    await _pump(tester, tabs);
    expect(tester.takeException(), isNull);

    await _dragChip(tester, '排行', const Offset(80, 0));
    expect(tester.takeException(), isNull);
    expect(tabs.tabs.length, 3);
    tabs.dispose();
  });

  testWidgets('窄泳道里开三条标签：标签条不溢出、不抛', (tester) async {
    final tabs = _tabs();
    for (final label in ['排行', '最新', '收藏']) {
      tabs.open(
        label: label,
        source: 'p1',
        content: (context) => const SizedBox(width: 40, height: 40),
      );
    }
    // 320 宽是「面板图标必须完整」那笔账里最窄的一档；标签条在这里必须走滚动，
    // 而不是把 trailing 那三颗挤出去 —— 布局异常会顺手把 MouseTracker 的
    // 复位标志跳过去，表现就是日志里刷一串 !_debugDuringDeviceUpdate。
    await _pump(tester, tabs, surface: const Size(320, 600), centered: false);
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('竖向轨在窄宽度下也不抛', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '排行',
      source: 'p1',
      content: (context) => const SizedBox(width: 40, height: 40),
    );
    tabs.setSide(DiscoverTabBarSide.left);
    await _pump(tester, tabs, surface: const Size(320, 600), centered: false);
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('指针悬停在标签条上时切到竖向轨：不抛、帧收敛', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '排行',
      source: 'p1',
      content: (context) => const SizedBox(width: 40, height: 40),
    );
    await _pump(tester, tabs, surface: const Size(480, 600), centered: false);
    expect(tester.takeException(), isNull);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    // 指针停在标签条中段 —— 实机卡死时指针就在标签条上（刚点完标签显示菜单）。
    await gesture.moveTo(tester.getCenter(find.text('排行').first));
    await tester.pumpAndSettle();

    // 与 _DisplayOptionsButton 的 onSelected 同款顺序：先改设置（触发 watch 重建），
    // 再动树上的朝向。
    tabs.setSide(DiscoverTabBarSide.left);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 切完轨还悬着：竖排布局下的 hover 派发也要干净。
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(tester.takeException(), isNull);

    // 来回切两次，把 enter/exit 配对的不同组合都走到。
    tabs.setSide(DiscoverTabBarSide.top);
    await tester.pumpAndSettle();
    tabs.setSide(DiscoverTabBarSide.right);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await gesture.removePointer();
    tabs.dispose();
  });

  testWidgets('结果页那颗伪装搜索框：在标签里点它 ⇒ 开一条同来源的搜索标签', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '排行',
      source: 'p1',
      content: (context) {
        final scope = DiscoverTabScope.maybeOf(context)!;
        return Align(
          child: TextButton(
            onPressed: () => scope.openSearchInput(
              SearchStates.initial().copyWith(from: 'p1'),
              aggregateMode: false,
            ),
            child: const Text('去搜索'),
          ),
        );
      },
    );
    await _pump(tester, tabs);
    final before = tabs.tabs.length;

    await tester.tap(find.text('去搜索'));
    await tester.pumpAndSettle();

    expect(tabs.tabs.length, before + 1);
    final opened = DiscoverTabs.specOfLeaf(
      tabs.tabs.last.child as LeafSnapshot,
    )!;
    // 来源必须跟着走：在 p1 的搜索结果里点搜索框，不该跳成一个没来源的搜索。
    expect(opened.source, 'p1');
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('往内容区拖（这一组不收外来落点）也不抛异常', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '收藏',
      source: 'p1',
      content: (context) => const SizedBox(width: 40, height: 40),
    );
    await _pump(tester, tabs);
    expect(tester.takeException(), isNull);

    await _dragChip(tester, '收藏', const Offset(0, 160));
    expect(tester.takeException(), isNull);
    tabs.dispose();
  });

  testWidgets('泳道宿主里反复进出悬停：帧要收敛，且不抛', (tester) async {
    final tabs = _tabs();
    tabs.open(label: '排行', source: 'p1', content: (c) => _probedLeaf());
    tabs.open(label: '最新', source: 'p1', content: (c) => _probedLeaf());
    await _pumpInLaneHost(tester, tabs);
    expect(tester.takeException(), isNull);
    final baseline = _leafBuilds;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    // 在两条标签与内容区之间来回扫三次：每一趟都会打出一对 enter/exit，
    // 也就是「hover 回调里改命中树」最容易自激的那条路。
    for (var round = 0; round < 3; round++) {
      await gesture.moveTo(tester.getCenter(find.text('排行').first));
      await tester.pumpAndSettle();
      await gesture.moveTo(tester.getCenter(find.text('最新').first));
      await tester.pumpAndSettle();
      await gesture.moveTo(const Offset(240, 420));
      await tester.pumpAndSettle();
    }
    await gesture.removePointer();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 收敛判据：来回扫 9 趟，重建必须还是个位数级别。自循环会直接冲到几百
    // 或者让上面的 pumpAndSettle 超时。
    expect(
      _leafBuilds - baseline,
      lessThan(20),
      reason:
          '叶子重建了 '
          '${_leafBuilds - baseline} 次，帧没有收敛',
    );
    tabs.dispose();
  });

  testWidgets('泳道宿主里点标签切换：帧要收敛', (tester) async {
    final tabs = _tabs();
    tabs.open(label: '排行', source: 'p1', content: (c) => _probedLeaf());
    tabs.open(label: '最新', source: 'p1', content: (c) => _probedLeaf());
    await _pumpInLaneHost(tester, tabs);
    final baseline = _leafBuilds;

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text(i.isEven ? '排行' : '最新').first);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    // 4 次切换：每次最多重绘两三条标签的内容，不该超过两位数。
    expect(
      _leafBuilds - baseline,
      lessThan(24),
      reason:
          '切换后重建了 '
          '${_leafBuilds - baseline} 次',
    );
    tabs.dispose();
  });
  testWidgets('指针停在标签上不动时，鼠标注解数量必须不变', (tester) async {
    // `!_debugDuringDeviceUpdate` 那条断言唯一的燃料是「hover 期间命中树里的
    // 鼠标注解还在变」：每一次增删都会让 RendererBinding 再排一次
    // _scheduleMouseTrackerUpdate，于是设备更新相里套设备更新相。
    // 这里让指针**停在**标签上什么都不做，只推进时间：数量必须一动不动。
    final tabs = _tabs();
    tabs.open(label: '排行', source: 'p1', content: (c) => _probedLeaf());
    await _pumpInLaneHost(tester, tabs);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('排行').first));
    await tester.pumpAndSettle();
    final baseline = find.byType(MouseRegion).evaluate().length;
    expect(baseline, greaterThan(0));

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(MouseRegion).evaluate().length,
        baseline,
        reason: '第 $i 次静置之后鼠标注解数量变了 —— 悬停期间有人在改命中树',
      );
    }
    expect(tester.takeException(), isNull);
    await gesture.removePointer();
    tabs.dispose();
  });

  testWidgets('点「标签显示」：开菜单、逐项点一遍都不抛', (tester) async {
    // 实机「点这颗按钮就卡死」的那条路。根因是 `PopupMenuButton.constraints`
    // 其实是**菜单**的尺寸（不是按钮的）：填成 32×32 会把五项内容当场撑破。
    final tabs = _tabs();
    tabs.open(label: '排行', source: 'p1', content: (c) => _probedLeaf());
    await _pumpTuneMenuHost(tester, tabs);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '开「标签显示」菜单时溢出过');
    expect(find.text(t.discover.tabShowIcon), findsOneWidget);

    for (final label in [
      t.discover.tabShowIcon,
      t.discover.tabShowPluginShort,
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '点「$label」之后抛了');
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
    }
    await tester.tapAt(const Offset(4, 4)); // 关掉菜单
    await tester.pumpAndSettle();

    for (final side in DiscoverTabBarSide.values) {
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text(side.label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '切到「${side.label}」之后抛了');
    }
    tabs.dispose();
  });

  testWidgets('切朝向**不重挂**标签内容（叶子 State 还是同一个）', (tester) async {
    final tabs = _tabs();
    tabs.open(
      label: '排行',
      source: 'p1',
      content: (c) => const _LeafStateProbe(),
    );
    await _pump(tester, tabs, surface: const Size(900, 600), centered: false);
    await tester.pumpAndSettle();
    expect(_LeafStateProbeState.live, hasLength(1));
    final before = _LeafStateProbeState.live.single;

    for (final side in [
      DiscoverTabBarSide.left,
      DiscoverTabBarSide.right,
      DiscoverTabBarSide.top,
    ]) {
      tabs.setSide(side);
      await tester.pumpAndSettle();
      expect(
        _LeafStateProbeState.live,
        hasLength(1),
        reason: '切到 ${side.label} 之后叶子被重挂了（重建 = 用户说的重载）',
      );
      expect(
        identical(_LeafStateProbeState.live.single, before),
        isTrue,
        reason: '切到 ${side.label} 之后叶子换了 State 实例',
      );
    }
    tabs.dispose();
  });

  testWidgets('拖轨内侧那条边：轨变宽，松手落进设置', (tester) async {
    final cubit = _MemSettingCubit();
    // 偏好与树要**一致**：只设树的话，窄页面钳制会把树推回横向，
    // 界面停在 Offstage 里，把手根本不在可命中树里。
    cubit.updateDiscoverSetting(
      (current) => current.copyWith(tabSide: DiscoverTabBarSide.left),
    );
    final tabs = _tabs();
    tabs.open(
      label: '排行',
      source: 'p1',
      content: (c) => const _LeafStateProbe(),
    );
    tabs.setSide(DiscoverTabBarSide.left);
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: BlocProvider<GlobalSettingCubit>(
          create: (_) => cubit,
          child: Scaffold(
            body: SizedBox(
              width: 900,
              height: 600,
              child: DiscoverPlatView(
                tabs: tabs,
                setting: cubit.state.discoverSetting,
                onSearch: () {},
                onCustomizeOrder: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final startWidth = cubit.state.discoverSetting.tabRailWidth;

    await tester.drag(
      find.byKey(DiscoverPlatView.railHandleKey),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      cubit.state.discoverSetting.tabRailWidth,
      greaterThan(startWidth),
      reason: '拖完没落进设置',
    );

    // 往回死命拖：必须停在实测地板上，且那一帧不抛。
    // 地板之下标签的固定开销（图标 + 间距 + 关闭钮）摆不下，会抛 RenderFlex
    // 溢出 —— 而那是设备更新相里的异常，会把 MouseTracker 的复位标志跳过去。
    for (var i = 0; i < 6; i++) {
      await tester.drag(
        find.byKey(DiscoverPlatView.railHandleKey),
        const Offset(-200, 0),
      );
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull, reason: '拖到地板时溢出过');
    expect(
      cubit.state.discoverSetting.tabRailWidth,
      DiscoverPlatView.railMinWidth,
      reason: '没停在地板上',
    );
    tabs.dispose();
  });
}
