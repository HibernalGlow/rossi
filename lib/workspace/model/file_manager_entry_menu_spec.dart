// 文件管理器**条目右键菜单**的动作规格 —— 纯 Dart，不 import Flutter。
//
// 判据：`dart run test/workspace/file_manager_entry_menu_check.dart`
//
// 为什么抽出来：这份判断决定「右键点一个文件有哪些项、哪一项是灰的、哪一项要二次确认」，
// 而它错的方式**全是静默的** —— 少一项、把不能用的项画成可用、不可撤销的删除
// 混在普通动作里。界面上不报错，只是「点了没反应」，或者「一下子删没了」。
//
// 对照 neoview：
//   `src/nodes/neoview/features/panels/cards/folder/FolderContextMenuItems.tsx`
//   （动作联合类型 + 菜单项定义）与 `FolderContextActions.tsx`（`run()` 分发）。
// 差别有一处是刻意的：neo 的「回收站 / 永久删除」是**两个平级菜单项**，
// 这里也是 —— 但确认策略对齐的是 neo 的**默认配置**
// （`ReaderFolderConfirmationConfig{trash:false, permanentDelete:true}`），
// 即「回收站不弹确认、永久删除弹」。
//
// ignore_for_file: avoid_print

/// 菜单里的一个动作。UI 层负责把它翻译成图标 + 文案。
enum FileManagerEntryAction {
  /// 打开：目录进入、归档/图片交给 Reader。
  open,

  /// 在新页签打开（目录才有意义）。
  openInNewTab,

  /// 复制到内部剪贴板（两步式的第一步）。
  copy,

  /// 剪切到内部剪贴板（粘贴时走移动）。
  cut,

  /// 把剪贴板里的内容粘到**这一项**（必须是目录）。
  paste,

  /// 把这一项的路径复制到系统剪贴板。
  copyPath,

  rename,

  /// 在这一项（目录）里新建文件夹。
  createFolder,

  /// 移到回收站。**可撤销**（在支持的平台上）。
  trash,

  /// 永久删除。**不可撤销**，因此必须二次确认。
  deletePermanently,
}

/// 一个菜单项规格：只说「是哪个动作、能不能点、要不要确认」。
///
/// 不含图标与文案 —— 那两样要 Flutter 的 `IconData` 与 slang 的 `t`，
/// 放进来这份文件就不能被 `dart run` 直接跑了。
class FileManagerEntryMenuItemSpec {
  final FileManagerEntryAction action;

  /// 不可用（画成灰的、点了不响应）。**置灰不隐藏** —— 隐藏等于让人以为没这功能。
  final bool enabled;

  /// 需要**二次确认**。定义收紧到「不可撤销的破坏」这一件事上。
  ///
  /// 与 [dangerous] 分开，是有依据的、也是与 `flutter-list-entry-context-menu`
  /// 那份技能里「一个布尔同时驱动危险色与确认」的唯一偏离：
  /// 那条规则的理由是「只上色等于没保护」，而**回收站的保护不是确认框，是撤销通道**。
  /// 硬把两者并成一个布尔只有两种结果：要么「移到回收站」每次都弹一个用户明知
  /// 能撤销的确认框（neoview 默认就不弹），要么「永久删除」少了确认。
  /// 不变式由判据钉着：[destructive] 为真时 [dangerous] 必须为真。
  final bool destructive;

  /// 用危险色画。= 破坏性动作（含可撤销的那种）。
  final bool dangerous;

  const FileManagerEntryMenuItemSpec({
    required this.action,
    this.enabled = true,
    this.destructive = false,
    this.dangerous = false,
  }) : assert(!destructive || dangerous, '要确认的动作必须同时是危险色');

  @override
  String toString() =>
      '${action.name}(enabled=$enabled, destructive=$destructive, dangerous=$dangerous)';
}

/// 造菜单需要的全部输入 —— **没有一件是从 widget 里现推的**，
/// 调用方必须自己把答案查好了再传进来（尤其是 [canPaste] 要看剪贴板）。
class FileManagerEntryMenuInput {
  /// 右键那一项是不是目录。
  final bool isDirectory;

  /// 当前选中了多少项。`0` 表示没进多选（只是右键了一行）。
  final int selectionCount;

  /// 右键的那一项**在不在选中集合里**。
  ///
  /// 用它决定菜单是「对这一个」还是「对选中的这一批」：在选中集合里右键
  /// = 对整批操作，在集合外右键 = 对这一个（UI 会顺手把选中态收敛到它）。
  final bool inSelection;

  /// 这一项能不能打开（目录、归档、图片、视频都能；不认识的格式不能）。
  final bool canOpen;

  /// 当前目录能不能新建文件夹（只读挂载 / 权限不足时为假）。
  final bool canCreateFolder;

  /// 剪贴板里有没有东西。
  final bool canPaste;

  /// 「移到回收站」在这个平台上能不能撤销。**macOS 为 false**（没有程序化恢复接口）。
  final bool trashRestoreSupported;

  const FileManagerEntryMenuInput({
    required this.isDirectory,
    this.selectionCount = 0,
    this.inSelection = false,
    this.canOpen = true,
    this.canCreateFolder = true,
    this.canPaste = false,
    this.trashRestoreSupported = false,
  });

  /// 这一批操作到底作用在几项上。
  int get effectiveCount =>
      inSelection && selectionCount > 0 ? selectionCount : 1;

  /// 是不是「对一批」操作。
  bool get batch => effectiveCount > 1;
}

/// 按当前局面造出完整菜单。
///
/// 次序：**打开 → 剪贴板 → 编辑 → 危险**。危险组永远在最后（手指/指针滑一下
/// 不容易点到），且组内「永久删除」排在「移到回收站」之后。
List<FileManagerEntryMenuItemSpec> buildFileManagerEntryMenuItems(
  FileManagerEntryMenuInput input,
) {
  final batch = input.batch;
  return <FileManagerEntryMenuItemSpec>[
    // ── 打开 ──
    // 多选时打开没有定义（一次打开 12 本？），所以置灰而不是隐藏。
    FileManagerEntryMenuItemSpec(
      action: FileManagerEntryAction.open,
      enabled: !batch && input.canOpen,
    ),
    FileManagerEntryMenuItemSpec(
      action: FileManagerEntryAction.openInNewTab,
      enabled: !batch && input.isDirectory,
    ),

    // ── 剪贴板 ──
    const FileManagerEntryMenuItemSpec(action: FileManagerEntryAction.copy),
    const FileManagerEntryMenuItemSpec(action: FileManagerEntryAction.cut),
    FileManagerEntryMenuItemSpec(
      action: FileManagerEntryAction.paste,
      // 粘贴必须落到一个目录上；落在文件上没有定义。
      enabled: input.canPaste && !batch && input.isDirectory,
    ),

    // ── 编辑 ──
    FileManagerEntryMenuItemSpec(
      action: FileManagerEntryAction.rename,
      // 批量改名没有定义（重名怎么办、按什么规则），置灰。
      enabled: !batch,
    ),
    FileManagerEntryMenuItemSpec(
      action: FileManagerEntryAction.createFolder,
      // 只有目录里能新建；也只在单选时有意义（多选时它属于「哪一项」不清楚）。
      enabled: !batch && input.isDirectory && input.canCreateFolder,
    ),
    const FileManagerEntryMenuItemSpec(action: FileManagerEntryAction.copyPath),

    // ── 危险 ──
    FileManagerEntryMenuItemSpec(
      action: FileManagerEntryAction.trash,
      dangerous: true,
      // 不弹确认：它可撤销，保护由撤销提示条承担（对齐 neoview 的默认配置）。
      // 平台不支持撤销时（macOS）由文案层提示「无法恢复」，**不**在这里改成确认 ——
      // 那会让同一个菜单项在不同平台上语义不同，判据也就没法写。
    ),
    const FileManagerEntryMenuItemSpec(
      action: FileManagerEntryAction.deletePermanently,
      destructive: true,
      dangerous: true,
    ),
  ];
}

/// 这个动作要不要弹二次确认。
///
/// 只在**不可撤销**时为真。`trash` 返回 `false` 不是漏了 —— 它有撤销通道。
bool requiresConfirmation(FileManagerEntryAction action) =>
    action == FileManagerEntryAction.deletePermanently;

// ── 点一下到底是「打开」还是「选上」 ────────────────────────────────────────

/// 单击一个条目有三种含义。分开写出来是因为**它们的优先级会打架**：
/// 同时按住 Ctrl 与 Shift 时以哪一个为准、桌面上「单击即打开」与
/// 「单击即选中」这两种习惯怎么共存。
enum FileManagerEntryTapGesture {
  /// 打开（进入目录 / 交给 Reader）。
  open,

  /// 把这一项加进/移出选中集合。
  toggle,

  /// 从锚点连选到这一项。
  extend,
}

/// 「这一下点算哪种」的**唯一**判断入口。
///
/// 两个入参由界面层查好传进来（`HardwareKeyboard.instance`），不在这里读键盘 ——
/// 那样这个函数就跑不进 `dart run` 的判据里了。
///
/// 两处刻意的决定：
///
/// - **不按平台挑修饰键**。调用方把 `meta || control` 合并成一个 [toggleModifier]：
///   macOS 的习惯键是 Cmd、Windows/Linux 是 Ctrl，而两个都认的代价只是
///   「在 macOS 上按 Ctrl 也能多选」，比「按错键就没反应」好。
/// - **Ctrl 与 Shift 同时按，Shift 赢**。连选是「以某个点为起点选一片」，
///   它需要一个起点，而 [toggle] 会把起点改掉；让 [extend] 优先，
///   用户按住两个键时得到的是**范围**而不是「把起点换到这一项」。
FileManagerEntryTapGesture resolveFileManagerEntryTapGesture({
  required bool toggleModifier,
  required bool extendModifier,
}) {
  if (extendModifier) return FileManagerEntryTapGesture.extend;
  if (toggleModifier) return FileManagerEntryTapGesture.toggle;
  return FileManagerEntryTapGesture.open;
}

/// 右键（长按）一行时，选中态要不要先收敛到它。
///
/// 收敛 = 先把选中集合清掉、只选这一行。规则取自 neoview：**在选中集合里右键
/// 是对整批操作，在集合外右键是对这一个**。少了这一步，右键一个没选中的文件
/// 会看见菜单以「这 3 项」为主语 —— 而用户根本没选过哪怕一项。
///
/// 这个判断必须是纯的，因为它决定了「菜单弹出来之前要不要先等一次桥调用」，
/// 而那一步是有时序的（见 `FileManagerEntryContextMenuRegion.beforeOpen`）。
bool shouldConvergeFileManagerSelectionOnMenu({required bool inSelection}) =>
    !inSelection;

/// 二次确认要问哪一句。返回 `null` = 不需要确认。
///
/// 文案层据此选字符串；`trash` 那一档带上 `restoreSupported`，因为
/// 「可以撤销」和「删了就没了」必须问得不一样。
FileManagerDeletePrompt? deletePromptFor(
  FileManagerEntryAction action, {
  required int count,
  required bool restoreSupported,
}) {
  switch (action) {
    case FileManagerEntryAction.trash:
      return FileManagerDeletePrompt.trash(
        count: count,
        restoreSupported: restoreSupported,
      );
    case FileManagerEntryAction.deletePermanently:
      return FileManagerDeletePrompt.permanent(count: count);
    default:
      return null;
  }
}

/// 一次删除要问的那句话的**语义**（不是字符串本身）。
class FileManagerDeletePrompt {
  final bool permanent;
  final int count;
  final bool restoreSupported;

  const FileManagerDeletePrompt.trash({
    required this.count,
    required this.restoreSupported,
  }) : permanent = false;

  const FileManagerDeletePrompt.permanent({required this.count})
    : permanent = true,
      restoreSupported = false;

  @override
  bool operator ==(Object other) =>
      other is FileManagerDeletePrompt &&
      other.permanent == permanent &&
      other.count == count &&
      other.restoreSupported == restoreSupported;

  @override
  int get hashCode => Object.hash(permanent, count, restoreSupported);

  @override
  String toString() =>
      'DeletePrompt(permanent=$permanent, count=$count, restore=$restoreSupported)';
}

/// 「移到回收站」在**这个平台**上到底会不会留下可撤销的回执。
///
/// 抽成函数而不是直接用输入字段，是为了让「不可撤销」这件事只有一个判断入口：
/// 菜单的文案、确认条的文案、撤销提示条的显隐都读它。
String trashOutcomeHint({required bool restoreSupported}) =>
    restoreSupported ? '可以撤销' : '无法撤销';

/// 菜单项解析出的**批量文案主语**。多选时说「这 3 项」，单选时说「这一项」。
String selectionSubject(int count) => count > 1 ? '这 $count 项' : '这一项';
