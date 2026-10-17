part of 'comic_operation.dart';

enum _OperationKind { generic, download }

class _OperationItemData {
  const _OperationItemData({
    required this.icon,
    required this.text,
    this.kind = _OperationKind.generic,
    this.onTap,
    this.onLongPress,
    this.onLongPressTooltip,
    this.enabled = true,
    this.highlighted = false,

    /// 高亮时图标填充成实心（收藏的星、点赞的心这类「开/关」语义）。
    this.fillsWhenHighlighted = false,
    this.accentColor,
    this.iconColor,
    this.primary = false,
  });

  final Glyph icon;
  final String text;

  /// 下载项要额外接下载状态流，单独渲染。
  final _OperationKind kind;
  final VoidCallback? onTap;

  /// 长按回调，参数是**全局坐标**——弹菜单的那一项要在手指按下的位置开
  /// （与书架卡片右键/长按菜单同一套做法），只给一个 VoidCallback 就不够了。
  final void Function(Offset position)? onLongPress;

  /// 长按的悬停提示（桌面端可发现性）。
  final String? onLongPressTooltip;
  final bool enabled;
  final bool highlighted;
  final bool fillsWhenHighlighted;
  final Color? accentColor;

  /// 覆盖图标颜色（用于下载状态的语义色）。
  final Color? iconColor;
  final bool primary;
}

/// 下载卡片：跟着下载任务/下载记录切图标与文案，让「点一下会发生什么」可预期。
class _DownloadOperationCard extends StatelessWidget {
  const _DownloadOperationCard({
    required this.item,
    required this.compact,
    required this.from,
    required this.comicId,
    required this.taskStream,
    this.inline = false,
  });

  final _OperationItemData item;
  final bool compact;
  final String from;
  final String comicId;
  final Stream<DownloadTask?> taskStream;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DownloadTask?>(
      stream: taskStream,
      initialData: DownloadQueueManager.instance.getTaskByComic(from, comicId),
      builder: (context, snapshot) {
        if (inline) {
          return _InlineOperationButton(
            item: _decorate(context, snapshot.data),
          );
        }
        return _OperationCard(
          item: _decorate(context, snapshot.data),
          compact: compact,
        );
      },
    );
  }

  _OperationItemData _decorate(BuildContext context, DownloadTask? task) {
    // 不允许下载时保持原样（「禁止下载」）。
    if (!item.enabled) {
      return item;
    }

    final colorScheme = context.theme.colorScheme;
    final state = resolveComicDownloadVisualState(
      isDownloading: task?.isDownloading ?? false,
      isCompleted: task?.isCompleted ?? false,
      stateCode:
          task?.taskInfo?.stateCode ?? (task == null ? 'none' : 'queued'),
      hasRecord: hasComicDownloadRecord(from: from, comicId: comicId),
    );

    final (Glyph icon, String text, Color? iconColor) = switch (state) {
      ComicDownloadVisualState.downloading => (
        AppGlyphs.downloading,
        t.reader.downloadStatusDownloading,
        colorScheme.primary,
      ),
      ComicDownloadVisualState.paused => (
        AppGlyphs.pauseCircle,
        t.reader.downloadStatusPaused,
        Colors.orange,
      ),
      ComicDownloadVisualState.failed => (
        AppGlyphs.error,
        t.reader.downloadStatusFailed,
        Colors.red,
      ),
      ComicDownloadVisualState.completed => (
        AppGlyphs.downloadDone,
        t.reader.downloadManage,
        Colors.green,
      ),
      ComicDownloadVisualState.notDownloaded => (
        AppGlyphs.cloudDownload,
        t.comicInfo.download,
        null,
      ),
    };

    return _OperationItemData(
      kind: item.kind,
      icon: icon,
      text: text,
      onTap: item.onTap,
      onLongPress: item.onLongPress,
      onLongPressTooltip: item.onLongPressTooltip,
      enabled: item.enabled,
      iconColor: iconColor,
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.item, this.compact = false});

  final _OperationItemData item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = item.accentColor ?? context.theme.colorScheme.primary;
    final background = item.highlighted
        ? accent.withValues(alpha: 0.14)
        : context.theme.colorScheme.surfaceContainerLowest;
    final foreground = !item.enabled
        ? context.theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : item.highlighted
        ? accent
        : context.textColor;

    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: item.onTap,
        // material_ui 的 InkWell 只暴露 onLongPress（没有 Start 变体），拿不到手指
        // 的按下点，于是菜单锚在卡片自己的中心。
        onLongPress: item.onLongPress == null
            ? null
            : () => item.onLongPress!(_menuAnchor(context)),
        child: Ink(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 10 : 11,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedGlyphIcon(
                item.icon,
                filled: item.fillsWhenHighlighted && item.highlighted,
                size: compact ? 18 : 20,
                color: item.iconColor ?? foreground,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  item.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 13 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final tooltip = item.onLongPressTooltip;
    if (tooltip == null || item.onLongPress == null) {
      return card;
    }
    // triggerMode 必须是 manual：默认的 longPress 触发会在触摸设备上与
    // 卡片自身的 onLongPress 抢同一个手势，导致长按变成「弹提示」。
    // 桌面端悬停提示不依赖 triggerMode，仍然正常显示。
    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.manual,
      child: card,
    );
  }

  /// 长按菜单的锚点：这张卡自己的中心（全局坐标）。
  Offset _menuAnchor(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return Offset.zero;
    }
    return box.localToGlobal(box.size.center(Offset.zero));
  }
}

class _InlineOperationButton extends StatelessWidget {
  const _InlineOperationButton({required this.item});
  final _OperationItemData item;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: const StadiumBorder(),
    );
    final icon = AnimatedGlyphIcon(
      item.icon,
      filled: item.fillsWhenHighlighted && item.highlighted,
      size: 20,
    );
    final button = item.highlighted
        ? FilledButton.icon(
            onPressed: item.enabled ? item.onTap : null,
            style: style,
            icon: icon,
            label: Text(item.text),
          )
        : FilledButton.tonalIcon(
            onPressed: item.enabled ? item.onTap : null,
            style: style,
            icon: icon,
            label: Text(item.text),
          );
    if (item.onLongPress == null) return button;
    return Tooltip(
      message: item.onLongPressTooltip ?? item.text,
      triggerMode: TooltipTriggerMode.manual,
      child: GestureDetector(
        onLongPressStart: item.enabled
            ? (details) => item.onLongPress!(details.globalPosition)
            : null,
        child: button,
      ),
    );
  }
}
