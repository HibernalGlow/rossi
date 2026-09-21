import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/file_manager_entry_menu_spec.dart';

/// 文件管理器**一个条目**的右键菜单宿主，按 Material Design 3 规格实现。
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
/// # 为什么用 `MenuAnchor` 而不是 `showMenu` / `PopupMenuButton`
///
/// `showMenu` 走的是 M2 的 `PopupMenuTheme`：2dp 圆角、8dp 高度、`surface` 底色。
/// MD3 的菜单面是 **`surfaceContainer` 底色 + 2dp 高度 + 4dp 圆角 + 8dp 纵向内边距**，
/// 条目 48dp 高、左右 12dp 内边距、图标与文字间距 12dp。这些在 `MenuItemButton`
/// 里已经是默认值，只有菜单面本身要显式给一份 [md3MenuStyle]。
///
/// 同仓的 `shelf_entry_context_menu.dart` 用的仍是 `showMenu`；那一份没动 ——
/// 收藏 / 历史菜单是既成的，改它的观感不在这次的范围里。
///
/// 也**不用** `PopupMenuButton`：那个组件要的是「自己就是那个按钮」，而这里整行
/// 已经是可点的 `InkWell`，再套一层按钮会让「点一下」与「右键一下」落到两个
/// 不同的响应区。
///
/// # 触发方式：桌面右键 + 触摸长按
///
/// 两个手势都挂，不按平台分叉。理由：桌面端长按弹菜单无害，而**按
/// `defaultTargetPlatform` 分叉会在「带触摸屏的桌面」上错** —— 平台说 desktop、
/// 用户却用触控笔长按，于是菜单永远出不来。
class FileManagerEntryContextMenuRegion extends StatelessWidget {
  const FileManagerEntryContextMenuRegion({
    super.key,
    required this.child,
    required this.inputBuilder,
    required this.onAction,
    this.onBeforeOpen,
    this.enabled = true,
  });

  final Widget child;

  /// 造出这一次菜单要用的输入。
  ///
  /// **必须是 O(1) 的**：`menuChildren` 是 `MenuAnchor` 的普通字段，随这一行
  /// 一起重建（构造的是 widget 对象，不是布局）。所以这里只许读卡片手里
  /// **已有的**缓存（最近一次快照 + 选中态投影），不许查一次库、发一次桥调用。
  final FileManagerEntryMenuInput Function() inputBuilder;

  /// 用户选了一个动作。选中后菜单已经关掉了，这里只负责执行。
  final void Function(BuildContext context, FileManagerEntryAction action)
  onAction;

  /// **菜单弹出来之前**要做的事，会等它做完再弹。
  ///
  /// 存在的理由只有一个：右键一个**没被选中**的行时，选中态要先收敛到它，
  /// 否则菜单会以「这 3 项」为主语，而用户一项都没选过。这一步要走一次桥调用，
  /// 所以必须是异步的。
  ///
  /// 时序是安全的：`await` 之后才 `open()`，而菜单面的第一次构建必然晚于
  /// `open()` —— 于是它看到的一定是收敛之后的选中态，不会闪一下旧文案。
  final Future<void> Function()? onBeforeOpen;

  /// 关掉时整块直通 —— 连手势都不挂（挂着手势会让长按变得「有反应」，
  /// 而它明明什么都不该发生）。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return _FileManagerEntryMenuAnchor(
      inputBuilder: inputBuilder,
      onAction: onAction,
      onBeforeOpen: onBeforeOpen,
      child: child,
    );
  }
}

/// `MenuAnchor` 需要 `MenuController`，而 `MenuController` 只能在 State 里持有一个
/// （它在 `attach` 之前调 `open()` 会断言失败）。所以外壳是 Stateless、内核是 Stateful。
class _FileManagerEntryMenuAnchor extends StatefulWidget {
  const _FileManagerEntryMenuAnchor({
    required this.child,
    required this.inputBuilder,
    required this.onAction,
    this.onBeforeOpen,
  });

  final Widget child;
  final FileManagerEntryMenuInput Function() inputBuilder;
  final void Function(BuildContext context, FileManagerEntryAction action)
  onAction;
  final Future<void> Function()? onBeforeOpen;

  @override
  State<_FileManagerEntryMenuAnchor> createState() =>
      _FileManagerEntryMenuAnchorState();
}

class _FileManagerEntryMenuAnchorState
    extends State<_FileManagerEntryMenuAnchor> {
  final MenuController _controller = MenuController();

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  Future<void> _openAt(Offset localPosition) async {
    final before = widget.onBeforeOpen;
    if (before != null) {
      await before();
      // 等这一次桥调用的过程里卡片可能已经被换掉了（切布局、关面板）。
      if (!mounted) return;
    }
    // MD3 的惯例是菜单左上角落在指针处。`MenuAnchor` 的 `position` 用的是
    // 锚点自己的坐标系，所以直接用 `localPosition`，不要换算全局坐标。
    _controller.open(position: localPosition);
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _controller,
      style: md3MenuStyle(context),
      menuChildren: _buildItems(context),
      child: GestureDetector(
        // `deferToChild`：手势只在这一行本身吃掉了事件时才认，不抢上层滚动的。
        behavior: HitTestBehavior.deferToChild,
        onSecondaryTapUp: (details) => _openAt(details.localPosition),
        onLongPressStart: (details) => _openAt(details.localPosition),
        child: widget.child,
      ),
    );
  }

  List<Widget> _buildItems(BuildContext context) {
    final input = widget.inputBuilder();
    final items = buildFileManagerEntryMenuItems(input);
    final widgets = <Widget>[];
    for (var index = 0; index < items.length; index += 1) {
      // 分组：MD3 说菜单里相关动作要成组，组间用分隔线。前两组（打开 / 剪贴板+编辑）
      // 与危险组之间必须隔开 —— 挨在一起最容易点错。
      if (index > 0 && items[index].dangerous && !items[index - 1].dangerous) {
        widgets.add(const Divider(height: 9, thickness: 1));
      }
      widgets.add(_buttonFor(context, items[index], input));
    }
    return widgets;
  }

  Widget _buttonFor(
    BuildContext context,
    FileManagerEntryMenuItemSpec spec,
    FileManagerEntryMenuInput input,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final color = spec.dangerous ? scheme.error : null;
    return MenuItemButton(
      // `onPressed: null` 就是 MD3 的禁用态（置灰、不可聚焦、点击不响应）。
      // 菜单项**永远在场**，只是有的不可点。
      onPressed: spec.enabled
          ? () => widget.onAction(context, spec.action)
          : null,
      // MD3 的单行菜单项：24dp 前置图标、48dp 行高、12dp 内边距，
      // `MenuItemButton` 已经是这套默认值，这里只给颜色。
      leadingIcon: Icon(
        fileManagerEntryActionIcon(spec.action),
        size: 24,
        color: color,
      ),
      child: Text(
        fileManagerEntryActionLabel(spec.action, input: input),
        style: TextStyle(color: color),
      ),
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
        child: Icon(Icons.check_rounded, size: 12, color: scheme.onPrimary),
      ),
    );
  }
}

/// MD3 的菜单面规格。
///
/// 抽成函数而不是散在 widget 里：文件管理器里会用到菜单的不止这一处
/// （目录列的右键、工具栏菜单），规格只该有一份。
MenuStyle md3MenuStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return MenuStyle(
    // MD3: 菜单面用 surfaceContainer，不是 surface。
    backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
    elevation: const WidgetStatePropertyAll(2),
    // MD3: 4dp 圆角。
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
    // MD3: 菜单上下各 8dp 内边距。
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8)),
    // MD3: 菜单最小 112dp、最大 280dp 宽。
    minimumSize: const WidgetStatePropertyAll(Size(112, 0)),
    maximumSize: const WidgetStatePropertyAll(Size(280, double.infinity)),
    alignment: AlignmentDirectional.topStart,
  );
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

IconData fileManagerEntryActionIcon(FileManagerEntryAction action) {
  switch (action) {
    case FileManagerEntryAction.open:
      return Icons.open_in_new_rounded;
    case FileManagerEntryAction.openInNewTab:
      return Icons.tab_rounded;
    case FileManagerEntryAction.copy:
      return Icons.content_copy_rounded;
    case FileManagerEntryAction.cut:
      return Icons.content_cut_rounded;
    case FileManagerEntryAction.paste:
      return Icons.content_paste_rounded;
    case FileManagerEntryAction.copyPath:
      return Icons.link_rounded;
    case FileManagerEntryAction.rename:
      return Icons.drive_file_rename_outline_rounded;
    case FileManagerEntryAction.createFolder:
      return Icons.create_new_folder_outlined;
    case FileManagerEntryAction.trash:
      return Icons.delete_outline_rounded;
    case FileManagerEntryAction.deletePermanently:
      return Icons.delete_forever_rounded;
  }
}
