part of '../folder_shelf_page.dart';

extension _FolderShelfNavigationPart on _FolderShelfPageContentState {
  /// 悬浮物拆成两个独立 Positioned：
  /// - 面包屑置顶（只在子文件夹出现，滑入淡出）；
  /// - 菜单为右下角 Expressive 花瓣按钮，跟随滚动显隐。
  List<Widget> _buildFloatingNav(BuildContext context, FolderShelfState state) {
    // 面包屑：子文件夹 + 未上滑隐藏时才出现；右下角菜单：只跟随滚动显隐。
    final pillHidden = state.isRoot || !_navVisible;
    final leftHandMode = context
        .watch<GlobalSettingCubit>()
        .state
        .leftHandModeEnabled;
    return [
      Positioned(
        bottom: 16,
        left: leftHandMode ? 16 : null,
        right: leftHandMode ? null : 16,
        child: IgnorePointer(
          ignoring: !_navVisible,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: _navVisible ? Offset.zero : const Offset(0, 1),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: _navVisible ? 1 : 0,
              child: _buildNavMenuButton(context, state),
            ),
          ),
        ),
      ),
      Positioned(
        top: 8,
        left: 12,
        right: 12,
        child: IgnorePointer(
          ignoring: pillHidden,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: pillHidden ? const Offset(0, -1) : Offset.zero,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: pillHidden ? 0 : 1,
              child: _buildBreadcrumbPill(context, state),
            ),
          ),
        ),
      ),
    ];
  }

  /// 面包屑：返回 / 路径 / 回根。菜单由右端常驻按钮负责，这里不重复放。
  Widget _buildBreadcrumbPill(BuildContext context, FolderShelfState state) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          height: 48,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const GlyphIcon(AppGlyphs.arrowBack),
                tooltip: t.common.back,
                onPressed: () => context.read<FolderShelfBloc>().add(
                  const FolderShelfGoBack(),
                ),
              ),
              Expanded(
                child: Text(
                  state.breadcrumbTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const GlyphIcon(AppGlyphs.home),
                onPressed: () => context.read<FolderShelfBloc>().add(
                  const FolderShelfGoHome(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavMenuButton(BuildContext context, FolderShelfState state) =>
      ShelfFloatingActions(
        mode: state.mode,
        onSelect: () => context.read<FolderShelfBloc>().add(
          const FolderShelfEnterSelectionMode(),
        ),
        onCreateFolder: () => _showCreateFolderDialog(context),
        onImport: () => _importComic(context),
        onHelp: () => _showShelfHelpDialog(context),
      );
}
