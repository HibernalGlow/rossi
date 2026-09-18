import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/view/comic_read.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';
import 'package:zephyr/workspace/widgets/reader/workspace_reader_empty_canvas.dart';

/// **阅读器泳道的真正内容**：上游原版 `ComicReadPage`，一个字都没改。
///
/// 三处「让它能住进泳道」的处理，全部在泳道这一侧：
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
/// 3. **实例身份**：以 `identityKey` 作 widget key。同一本书同一章重建时复用同一个
///    阅读器状态；换书 / 换章时整体重建，不会串页、不会残留上一本的进度。
///
/// 阅读器自带的 breadcrumb、页码、视图工具条与底部缩略条**留在泳道内部**
/// （neoview：Reader 的上下 chrome 是 Reader 的 dock，不是横向泳道）。
class WorkspaceReaderHost extends StatelessWidget {
  const WorkspaceReaderHost({super.key, required this.target});

  /// 当前要读的目标；`null` 表示这条泳道空闲。
  final WorkspaceReaderTarget? target;

  @override
  Widget build(BuildContext context) {
    final current = target;
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
          child: Navigator(
            key: ValueKey<String>('reader-navigator:${current.identityKey}'),
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => _buildReader(context, current),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReader(BuildContext context, WorkspaceReaderTarget current) {
    return ComicReadPage(
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
    );
  }
}
