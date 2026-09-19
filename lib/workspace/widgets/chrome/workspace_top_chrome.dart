import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';

/// 工作台顶栏的**两种形态** —— 区别不在长相，在**它占不占地方**。
///
/// 判据是「这个平台有没有鼠标指针」，不是「名字里带不带 desk」：
/// 带触摸屏的 Windows 笔记本仍然有指针，手机浏览器没有。
enum WorkspaceTopChromeMode {
  /// **有指针的平台（桌面）**：悬停揭示。内容从顶上铺满，顶栏叠在内容之上、
  /// 默认不可见也不吃鼠标，鼠标贴到窗口最顶端才淡入。
  ///
  /// 桌面端这么做是有原因的：泳道模式下每条泳道已经自带栏头，工作台再压一条
  /// **常驻**顶栏就是第二层顶栏（上面还叠着 macOS / Windows 原生标题栏）。
  reveal,

  /// **没有指针的平台（触摸屏）**：常驻。顶栏在**正常流**里占一行，
  /// 内容从它下面开始。
  ///
  /// 触摸屏上 `reveal` 等于**没有出口**：`MouseRegion` 永远不触发，
  /// 而工作台是 `Navigator.push` 上来的整页、没有系统返回按钮
  /// （`Esc` 只在键盘上存在）。所以那边必须常驻。
  persistent;

  /// 按平台给出形态。
  ///
  /// 用 `defaultTargetPlatform` 而不是 `dart:io` 的 `Platform.isMacOS`：
  /// 它是 Flutter 对「这个平台是什么」的正式回答（web 也走这一套 ——
  /// `defaultTargetPlatform` 在浏览器里按宿主系统给答案，手机浏览器 ⇒ 常驻、
  /// 桌面浏览器 ⇒ 揭示），而且判据能用 `debugDefaultTargetPlatformOverride`
  /// 把两种形态都跑一遍，`Platform` 在测试里改不动。
  static WorkspaceTopChromeMode forTargetPlatform(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return WorkspaceTopChromeMode.reveal;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return WorkspaceTopChromeMode.persistent;
    }
  }
}

/// 工作台顶栏**本体**（两种形态共用同一份内容）。
///
/// 放的是工作台级别的事：退出 / 当前书名 / 关闭当前漫画 / 切换模式 / 重置布局。
/// 泳道那些事（折叠 / 次序 / 独占 / 宽度）在**泳道栏头**里，不在这儿。
///
/// [mode] 只改三件事：
/// - 揭示形态**叠在内容之上**，需要投影把两层分开；常驻形态下面本来就是内容，
///   一条分隔线足够 —— 凭空一条影子反而像「有东西盖着」；
/// - 常驻形态要给**状态栏**让位，而且内边距要加在容器**自己**身上：
///   这样它的底色会铺到状态栏下面。把 `SafeArea` 套在整列外面就不行，
///   状态栏那一条会露出 `Scaffold` 的底色，与顶栏之间出现一道色差；
/// - 揭示形态恒为 [barHeight]（桌面端 `MediaQuery.padding` 为 0），
///   常驻形态总高 = [barHeight] + 状态栏内边距。
class WorkspaceTopChrome extends StatelessWidget {
  const WorkspaceTopChrome({
    super.key,
    required this.mode,
    required this.onExit,
    required this.onResetLayout,
  });

  /// 形态。刻意**不给默认值**：调用方一定知道自己在哪个平台上，
  /// 猜错的表现是「触摸屏上没有出口」——那正是这个参数存在的理由。
  final WorkspaceTopChromeMode mode;

  /// 退出工作台（回到进入前的页面）。
  final VoidCallback onExit;

  /// 重置布局。
  ///
  /// 由宿主传入而不是直接调 `cubit.resetLayout`：重置不只是「状态回默认」，
  /// 还要把**磁盘上的那份快照**一并作废 —— 否则重启之后它会被旧快照覆盖回来，
  /// 用户看到的是「重置了，但重启又变回去了」。而磁盘那一层在工作台页面上，
  /// 不在这个顶栏里。
  final VoidCallback onResetLayout;

  /// 顶栏那一行的高度（**不含**常驻形态的状态栏内边距）。
  /// 与泳道栏头同高 —— 揭示时正好接管那一行。
  static const double barHeight = 46;

  /// 触发带高度。**必须矮**：顶栏一出现就盖住泳道栏头，
  /// 触发带太高会让「操作泳道栏头」时顶栏反复闪现。只对 [WorkspaceTopChromeMode.reveal] 有意义。
  static const double triggerHeight = 10;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final floating = mode == WorkspaceTopChromeMode.reveal;

    // 常驻形态给状态栏让位。揭示形态是浮在**桌面**窗口上的，
    // 而桌面端 `MediaQuery.padding` 本来就是 0，不用特判。
    final topInset = floating ? 0.0 : MediaQuery.paddingOf(context).top;

    // 总高**精确**等于 `barHeight + 状态栏内边距`。这一层 `SizedBox` 不是装饰：
    // `BoxDecoration` 的边框会占掉内容盒的 1px（`Container` 把边框宽度算进自己的
    // 内边距），只写 `padding` + `decoration` 的话总高会变成 47 —— 判据量的就是
    // 这一圈矩形（「内容正好从顶栏下面开始」），差 1px 在界面上看不出来，
    // 只有判据抓得住。
    return SizedBox(
      height: barHeight + topInset,
      child: Container(
        padding: EdgeInsets.only(top: topInset),
        decoration: BoxDecoration(
          // 不透明：揭示形态正好叠在泳道栏头那一行上，
          // 半透明会让下面那行字透出来变成鬼影。
          color: theme.colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          boxShadow: floating
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
          builder: (context, state) => _buildRow(context, state),
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, WorkspaceState state) {
    final theme = Theme.of(context);
    final cubit = context.read<WorkspaceCubit>();
    final isSwimlane = state.mode == WorkspaceMode.swimlane;
    final target = state.readerTarget;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            tooltip: '退出工作台（Esc 亦可）',
            visualDensity: VisualDensity.compact,
            onPressed: onExit,
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.dashboard_customize_rounded,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            '工作台',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.6,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isSwimlane ? '多列泳道' : '沉浸四边栏',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: theme.colorScheme.outline,
              ),
            ),
          ),

          // 当前在读哪一本 —— 泳道模式有栏头显示书名，四边栏模式只剩这里。
          if (target != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '· ${target.displayTitle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],

          const Spacer(),

          if (target != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: '关闭当前漫画（回到空态）',
              visualDensity: VisualDensity.compact,
              onPressed: cubit.closeReader,
            ),
          IconButton(
            icon: Icon(
              isSwimlane ? Icons.dock_rounded : Icons.view_column_rounded,
              size: 18,
            ),
            tooltip: isSwimlane ? '切换为沉浸四边栏' : '切换为多列泳道',
            visualDensity: VisualDensity.compact,
            onPressed: cubit.toggleMode,
          ),
          IconButton(
            icon: const Icon(Icons.restore_rounded, size: 18),
            tooltip: '重置布局（不影响当前正在读的这一本）',
            visualDensity: VisualDensity.compact,
            onPressed: onResetLayout,
          ),
        ],
      ),
    );
  }
}

/// 顶栏的**揭示形态**（桌面）：把 [WorkspaceTopChrome] 做成浮层，
/// 鼠标贴到窗口最顶端才淡入。
///
/// 返回的是一个 `Positioned`，所以**必须**放在 `Stack` 里 —— 这也是它
/// 与 [WorkspaceTopChrome] 分开的原因：本体是个正常流里的盒子，
/// 两种形态各自决定怎么摆它。
///
/// 揭示规则（两段 hover，互不打架）：
/// - 触发带 = 窗口最顶端 [WorkspaceTopChrome.triggerHeight] 像素，**垫在顶栏下层**。
///   于是顶栏不可见时鼠标能穿到它、可见时被顶栏接住 —— 顶栏自己也是
///   [MouseRegion]，鼠标从触发带滑到顶栏上时 `_barHover` 立刻接管，
///   不会出现「滑下去就收起来」的抖动。
/// - 鼠标离开顶栏（往下超过 [WorkspaceTopChrome.barHeight] 或移出窗口）才收起。
class WorkspaceTopChromeReveal extends StatefulWidget {
  const WorkspaceTopChromeReveal({
    super.key,
    required this.onExit,
    required this.onResetLayout,
  });

  final VoidCallback onExit;
  final VoidCallback onResetLayout;

  @override
  State<WorkspaceTopChromeReveal> createState() =>
      _WorkspaceTopChromeRevealState();
}

class _WorkspaceTopChromeRevealState extends State<WorkspaceTopChromeReveal> {
  bool _triggerHover = false;
  bool _barHover = false;

  bool get _visible => _triggerHover || _barHover;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SizedBox(
        height: WorkspaceTopChrome.barHeight,
        child: Stack(
          children: [
            // 触发带（下层）：顶栏不可见时鼠标穿到这里召唤它。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: WorkspaceTopChrome.triggerHeight,
              child: MouseRegion(
                onEnter: (_) => setState(() => _triggerHover = true),
                onExit: (_) => setState(() => _triggerHover = false),
                child: const SizedBox.expand(),
              ),
            ),

            // 顶栏本体（上层）：不可见时不吃鼠标事件。
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_visible,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _barHover = true),
                  onExit: (_) => setState(() => _barHover = false),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    opacity: _visible ? 1 : 0,
                    child: WorkspaceTopChrome(
                      mode: WorkspaceTopChromeMode.reveal,
                      onExit: widget.onExit,
                      onResetLayout: widget.onResetLayout,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
