import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/platform/desktop/reveal_in_file_manager.dart';
import 'package:zephyr/workspace/model/file_manager_entry_menu_spec.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/common_popup.dart';

/// 文件管理器**一个条目**的右键菜单宿主。
///
/// 三件事分开：
///
/// - **有哪些项、哪一项可用、要不要二次确认、点一下算哪种手势** —— 纯函数
///   `lib/workspace/model/file_manager_entry_menu_spec.dart`（判据
///   `dart run test/workspace/file_manager_entry_menu_check.dart`）；
/// - **长什么样、在哪儿弹** —— 本文件；
/// - **动作怎么落地** —— `lib/workspace/method/file_manager_actions.dart`
///   （问参数、说结果）加卡片里的桥调用（那一层才有会话 id 与忙状态）。
///
/// # 弹出动画与工作台那排「更多」同源
///
/// 这一份曾经走 MD3 的 `MenuAnchor`（Material 自己的淡入缩放），与栏头 ⋮、
/// 文件管理器「更多」的 FlClash 托盘动画不是一套。现在统一走
/// [showCommonPopupMenu]：托盘从右键 / 长按那一点长出来、放不下时自己朝上翻，
/// 全仓菜单只有一份弹出动画。菜单面也随之换成 [CommonPopupSurface]
/// （superellipse 卡片），与工作台其余菜单同貌 —— 顺带把那份只为
/// `MenuAnchor` 存在的 `md3MenuStyle` 一并去掉。
///
/// # 触发方式：桌面右键 + 触摸长按
///
/// 两个手势都挂，不按平台分叉。理由：桌面端长按弹菜单无害，而**按
/// `defaultTargetPlatform` 分叉会在「带触摸屏的桌面」上错** —— 平台说 desktop、
/// 用户却用触控笔长按，于是菜单永远出不来。
///
/// 两个手势都**只请菜单，不碰选中集合**。这里曾经是「先异步收敛一次选中态、
/// 再弹菜单」（`onBeforeOpen`），因为桥那侧的复制 / 回收站 / 永久删除只读选中
/// 集合；现在它们收调用方显式报的路径（`file_ops_trash_paths` 等），目标在动作
/// 开始时由 `_actionTargets` 算一次，于是「右键一个没选中的文件 = 对这一个」
/// 不需要把高亮和操作条一起立起来。
class FileManagerEntryContextMenuRegion extends StatelessWidget {
  const FileManagerEntryContextMenuRegion({
    super.key,
    required this.child,
    required this.inputBuilder,
    required this.onAction,
    this.enabled = true,
  });

  final Widget child;

  /// 造出这一次菜单要用的输入。
  ///
  /// **必须是 O(1) 的**：它在右键 / 长按那一下被调一次，只许读卡片手里
  /// **已有的**缓存（最近一次快照 + 选中态投影），不许查一次库、发一次桥调用。
  final FileManagerEntryMenuInput Function() inputBuilder;

  /// 用户选了一个动作。选中后菜单已经关掉了，这里只负责执行。
  final void Function(BuildContext context, FileManagerEntryAction action)
  onAction;

  /// 关掉时整块直通 —— 连手势都不挂（挂着手势会让长按变得「有反应」，
  /// 而它明明什么都不该发生）。
  final bool enabled;

  void _openAt(BuildContext context, Offset globalPosition) {
    final input = inputBuilder();
    final specs = buildFileManagerEntryMenuItems(input);
    final items = <CommonPopupMenuItem>[];
    for (var index = 0; index < specs.length; index += 1) {
      final spec = specs[index];
      // 分组：相关动作要成组，组间用分隔线。前两组（打开 / 剪贴板+编辑）
      // 与危险组之间必须隔开 —— 挨在一起最容易点错。
      if (index > 0 && spec.dangerous && !specs[index - 1].dangerous) {
        items.add(const CommonPopupMenuItem.divider());
      }
      items.add(
        CommonPopupMenuItem(
          label: fileManagerEntryActionLabel(spec.action, input: input),
          glyph: fileManagerEntryActionIcon(spec.action),
          // `onPressed: null` 就是禁用态：菜单项**永远在场**，只是有的不可点。
          danger: spec.dangerous,
          onPressed: spec.enabled ? () => onAction(context, spec.action) : null,
        ),
      );
    }
    // 路由自己会在选中 / 点空白时关掉，不必等它。
    unawaited(
      showCommonPopupMenu(
        context: context,
        position: globalPosition,
        items: items,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return GestureDetector(
      // `deferToChild`：手势只在这一行本身吃掉了事件时才认，不抢上层滚动的。
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapUp: (details) => _openAt(context, details.globalPosition),
      onLongPressStart: (details) => _openAt(context, details.globalPosition),
      child: child,
    );
  }
}

/// 一行被「多选」选上时的样子。
///
/// # 为什么是浮在上面的一层，而不是把底色交给每一档视图
///
/// 六档视图各自的 `InkWell` 里已经有一层**不透明**的容器底色
/// （`surfaceContainerHighest`），铺在它下面的颜色会被盖掉。要「染一下底色」
/// 就得改六处 `LibraryEntrySurface`，而那一份是文件管理器 / 书签 / 历史
/// 三家共用的行契约 —— 为文件管理器一家的多选去动它，代价与风险都不对。
///
/// 所以做成叠在行上的一层：**半透明主色 + 2dp 主色描边 + 角标**。三样各有分工 ——
/// 描边保证在任何缩略图上都看得见边界，染色保证整行都算「被选上」，
/// 角标保证**在缩略图把整格铺满的网格档里也分辨得出**（那两档没有底色可言）。
class FileManagerEntrySelectionShell extends StatelessWidget {
  const FileManagerEntrySelectionShell({
    super.key,
    required this.selected,
    required this.child,
  });

  final bool selected;
  final Widget child;

  static const _radius = BorderRadius.all(Radius.circular(8));

  @override
  Widget build(BuildContext context) {
    if (!selected) return child;
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        child,
        // `IgnorePointer`：这一层只是画，不能把行自己的点击/右键吞掉。
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                border: Border.all(color: scheme.primary, width: 2),
                borderRadius: _radius,
              ),
            ),
          ),
        ),
        Positioned(top: 3, right: 3, child: _check(scheme)),
      ],
    );
  }

  Widget _check(ColorScheme scheme) {
    return IgnorePointer(
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
        ),
        child: GlyphIcon(AppGlyphs.check, size: 12, color: scheme.onPrimary),
      ),
    );
  }
}

/// 一个动作对应哪句话。
///
/// 文案先用字面量：这条线还没有把文件管理器的字符串收进 slang
/// （`t.shelfMenu.*` 那一套只覆盖收藏 / 历史卡片）。
/// 收口时把本函数整体换成 `t.fileManagerMenu.*` 即可 —— 只有这一处。
///
/// 「移到回收站」的后缀由**平台能力**决定，不是由这次调用临时算的：
/// 这个后缀要在**点之前**就能看见，否则用户点完才从提示条里知道删了回不来。
String fileManagerEntryActionLabel(
  FileManagerEntryAction action, {
  required FileManagerEntryMenuInput input,
}) {
  switch (action) {
    case FileManagerEntryAction.open:
      return '打开';
    case FileManagerEntryAction.openInNewTab:
      return '在新页签打开';
    case FileManagerEntryAction.revealInFileManager:
      // 词跟着平台变（访达 / 资源管理器 / 打开所在目录）—— Linux 那边做不到
      // 「选中这一项」，就不能写成和前两家一样。措辞的单一出处在
      // `reveal_in_file_manager.dart::revealMenuLabel`。
      return revealMenuLabel(currentRevealHost());
    case FileManagerEntryAction.copy:
      return '复制';
    case FileManagerEntryAction.cut:
      return '剪切';
    case FileManagerEntryAction.paste:
      // 落在文件上没有定义，菜单里它会是灰的；文案也跟着说「粘贴」而不是
      // 「粘贴到这一项」—— 灰掉的那一项本来就该读起来不像一个完整动作。
      return input.isDirectory ? '粘贴到这一项' : '粘贴';
    case FileManagerEntryAction.copyPath:
      return '复制路径';
    case FileManagerEntryAction.rename:
      return '重命名';
    case FileManagerEntryAction.createFolder:
      return '新建文件夹';
    case FileManagerEntryAction.trash:
      // 「可撤销」与「删了就没了」必须在**菜单上**就分辨得出：macOS 上没有程序化
      // 恢复接口，删了只进系统废纸篓，用户得先知道这件事再点。
      return input.trashRestoreSupported ? '移到回收站' : '移到回收站（无法撤销）';
    case FileManagerEntryAction.deletePermanently:
      return '永久删除';
  }
}

Glyph fileManagerEntryActionIcon(FileManagerEntryAction action) {
  switch (action) {
    case FileManagerEntryAction.open:
      return AppGlyphs.openExternal;
    case FileManagerEntryAction.openInNewTab:
      return AppGlyphs.layoutTabs;
    case FileManagerEntryAction.revealInFileManager:
      return AppGlyphs.folder;
    case FileManagerEntryAction.copy:
      return AppGlyphs.copy;
    case FileManagerEntryAction.cut:
      return AppGlyphs.cut;
    case FileManagerEntryAction.paste:
      return AppGlyphs.paste;
    case FileManagerEntryAction.copyPath:
      return AppGlyphs.link;
    case FileManagerEntryAction.rename:
      return AppGlyphs.edit;
    case FileManagerEntryAction.createFolder:
      return AppGlyphs.folderPlus;
    case FileManagerEntryAction.trash:
      return AppGlyphs.delete;
    case FileManagerEntryAction.deletePermanently:
      return AppGlyphs.delete;
  }
}
