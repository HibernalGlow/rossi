import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/view/comic_read.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/reader_hover_reveal_layer.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';
import 'package:zephyr/workspace/router/workspace_lane_dispatch.dart';
import 'package:zephyr/workspace/router/workspace_navigation_bridge.dart';
import 'package:zephyr/workspace/widgets/reader/workspace_reader_empty_canvas.dart';
import 'package:zephyr/workspace/widgets/reader/workspace_reader_fullscreen_scope.dart';

/// **阅读器泳道的真正内容**：上游原版 `ComicReadPage`，一个字都没改。
///
/// 四处「让它能住进泳道」的处理，全部在泳道这一侧：
///
/// 1. **视口改写**：阅读器的版式全部按 `MediaQuery.size` 算（页宽、双页分割、
///    底部工具条的宽窄分支都读它）。泳道比窗口窄，所以这里把 `MediaQuery.size`
///    改写成泳道的实际尺寸 —— 阅读器于是认为「窗口就这么大」，版式自洽。
///    这不是把它压缩，而是给它一个正确的视口。
/// 2. **给一条自己的路由栈**（[Navigator]）：泳道不是一条导航栈上的页面。
///    没有这层时，阅读器顶栏的自动返回按钮读的是**工作台自己那条路由**
///    （`ModalRoute.canPop == true`），点一下退出的不是这本漫画、而是整个工作台；
///    底部的阅读设置面板也会铺满窗口而不是泳道。给它一个只有一页的局部导航器之后，
///    「返回」不再被凭空插出来，泳道内的面板与弹层也只作用在这条泳道里。
/// 3. **参与落点记账**：进这块内容的**推入**不是开在这儿（这条泳道只有一条上游
///    页面），所以不上报导航器；但**回退**要用落点 —— 用户在阅读器里按下指针之后，
///    落点必须跟过来（见 `WorkspaceNavigationBridge.attachLaneContent`）。
///    不跟过来的话，阅读器里的一下「返回」（`context.pop()`，例如阅读错误页那个
///    按钮）会按上一次在**面板**里的落点算，退掉那块面板里的一页：退错了对象。
/// 4. **实例身份**：以 `identityKey` 作 widget key。同一本书同一章重建时复用同一个
///    阅读器状态；换书 / 换章时整体重建，不会串页、不会残留上一本的进度。
///
/// 阅读器自带的 breadcrumb、页码、视图工具条与底部缩略条**留在泳道内部**
/// （neoview：Reader 的上下 chrome 是 Reader 的 dock，不是横向泳道）。
class WorkspaceReaderHost extends StatefulWidget {
  const WorkspaceReaderHost({super.key, required this.target});

  /// 当前要读的目标；`null` 表示这条泳道空闲。
  final WorkspaceReaderTarget? target;

  @override
  State<WorkspaceReaderHost> createState() => _WorkspaceReaderHostState();
}

class _WorkspaceReaderHostState extends State<WorkspaceReaderHost> {
  /// 这条泳道自己的身份 —— 落点记账按 `(laneId, panelId)` 认。
  ///
  /// 阅读器泳道里没有「换面板」这回事，第二段只是个常量占位：它让身份唯一，
  /// 并不指向 `WorkspacePanelRegistry` 里的任何一条。
  static const WorkspaceLaneHost _host = WorkspaceLaneHost(
    LaneId.reader,
    'reader',
  );

  @override
  void initState() {
    super.initState();
    _updateRegistration();
  }

  @override
  void didUpdateWidget(WorkspaceReaderHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateRegistration();
  }

  @override
  void dispose() {
    WorkspaceNavigationBridge.instance.detachLaneContent(_host);
    super.dispose();
  }

  /// 有内容（正读着某一本）时才是落点；空画布不占落点 ——
  /// 否则用户在空泳道里的按下会把落点从真正的面板上抢走。
  void _updateRegistration() {
    final bridge = WorkspaceNavigationBridge.instance;
    if (widget.target == null) {
      bridge.detachLaneContent(_host);
    } else {
      bridge.attachLaneContent(_host);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.target;
    if (current == null) {
      return const WorkspaceReaderEmptyCanvas();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height,
        );
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(size: size),
          child: Listener(
            // translucent：空白处按下也算「用户在这条泳道里」，
            // 但不抢子节点的命中（阅读器自己的翻页 / 唤出上下栏照旧）。
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) =>
                WorkspaceNavigationBridge.instance.noteLaneInteraction(_host),
            child: Navigator(
              key: ValueKey<String>('reader-navigator:${current.identityKey}'),
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => _buildReader(context, current),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReader(BuildContext hostContext, WorkspaceReaderTarget current) {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      bloc: hostContext.read<WorkspaceCubit>(),
      buildWhen: (prev, curr) =>
          prev.isReaderFullscreen != curr.isReaderFullscreen ||
          prev.interaction.revealZones.bottom !=
              curr.interaction.revealZones.bottom,
      builder: (context, state) {
        final cubit = hostContext.read<WorkspaceCubit>();
        final bottom = state.interaction.revealZones.bottom;
        return ReaderHoverTriggerScope(
          // 下唤出区由「设置 → 布局」那块画布管：阅读器住在泳道里，
          // 它的底栏就是工作台的底边。阅读器自己的「唤出感应区高度」
          // 在那时不再参与（两处都说话时只有这里说的是「画出来的那一块」）。
          bottomRect: (
            x: bottom.x,
            y: bottom.y,
            width: bottom.width,
            height: bottom.height,
          ),
          child: ReaderFullscreenScope(
            isFullscreen: state.isReaderFullscreen,
            onToggleFullscreen: cubit.toggleReaderFullscreen,
            child: ComicReadPage(
              comicId: current.comicId,
              order: current.order,
              chapterId: current.chapterId,
              requestId: current.requestId,
              storageChapterId: current.storageChapterId,
              logicalKey: current.logicalKey,
              chapterExtern: current.chapterExtern,
              epsNumber: current.epsNumber,
              from: current.from,
              stringSelectCubit: current.stringSelectCubit,
              type: current.type,
              comicInfo: current.comicInfo,
            ),
          ),
        );
      },
    );
  }
}
