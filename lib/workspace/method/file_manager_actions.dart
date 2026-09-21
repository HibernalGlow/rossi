import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/src/rust/api/file_ops.dart';
import 'package:zephyr/workspace/model/file_manager_entry_menu_spec.dart';
import 'package:zephyr/widgets/toast.dart';

/// 文件管理器右键菜单里那些动作的**问与答**。
///
/// 三件事各归各家，这个文件只做中间那一件：
///
/// - **有哪些项、哪一项可用、点一下算哪种手势** —— 纯函数，见
///   `lib/workspace/model/file_manager_entry_menu_spec.dart`（判据
///   `dart run test/workspace/file_manager_entry_menu_check.dart`）；
/// - **问用户要参数、把结果说给他听** —— 本文件；
/// - **把动作发给核心（要会话 id、忙状态、陈旧守卫）** —— 留在卡片里，
///   因为那三样都只有卡片有。
///
/// 为什么不在这里调桥：桥调用必须和卡片的 `_busy` / 请求序号待在一起。放在这里
/// 就得把「会话忙不忙」也传进来，于是这一层同时知道对话框和并发控制两件事 ——
/// `shelf_entry_actions.dart` 之所以能自己调桥，是因为那边没有这道闸。

// ── 问参数 ──────────────────────────────────────────────────────────────────

/// 一次「已经问清楚了、可以直接发给核心」的动作。
///
/// 由 [planFileManagerEntryAction] 产出。拿到它说明用户已经答完了所有问题
/// （新名字填过了、确认点过了），剩下的只是发出去。
class FileManagerActionCall {
  const FileManagerActionCall(this.action, {this.path, this.newName});

  final FileManagerEntryAction action;

  /// 作用在哪一项上（重命名 / 新建文件夹的落点）。
  final String? path;

  /// 新名字。只有重命名与新建文件夹有。
  final String? newName;
}

/// 动作作用的那一项是谁、这一批有几项。
///
/// 刻意用普通字段而不是 `FileManagerEntry`：这一层不需要知道条目的大小、
/// 修改时间、子目录名，只关心「是个目录吗、叫什么、这一批几项」。
class FileManagerEntryTarget {
  const FileManagerEntryTarget({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.count,
    required this.restoreSupported,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int count;

  /// 「移到回收站」在这个平台上能不能撤销。决定要不要弹确认（见
  /// [confirmFileManagerDestructive]）。
  final bool restoreSupported;
}

/// 把用户选的动作变成一次可以发出去的动作；返回 `null` = 用户取消了。
///
/// 需要问的参数只有两处：重命名的新名字、新建文件夹的名字；再就是**不可撤销**
/// 的删除要一次确认。其余动作原样返回，这里只是把「要不要问」这条规则收在一处。
Future<FileManagerActionCall?> planFileManagerEntryAction(
  BuildContext context, {
  required FileManagerEntryAction action,
  required FileManagerEntryTarget target,
}) async {
  // 确认放在最前面：先问「删不删」再问「叫什么」会显得顺序错乱，
  // 而反过来（先填名字再问删不删）在用户取消时会白填一遍。
  if (requiresConfirmation(action)) {
    final ok = await confirmFileManagerDestructive(
      context,
      action: action,
      target: target,
    );
    if (!ok) return null;
    // 对话框关掉之后这一层可能已经不在了（面板被拖走、卡片重建）。
    // 少了这道守卫，下面那次 `showDialog` 会挂到一个已经失效的 context 上。
    if (!context.mounted) return null;
  }

  switch (action) {
    case FileManagerEntryAction.rename:
      final name = await _promptName(
        context,
        title: '重命名',
        label: '新名称',
        initial: target.name,
        confirmLabel: '重命名',
      );
      return name == null
          ? null
          : FileManagerActionCall(action, path: target.path, newName: name);

    case FileManagerEntryAction.createFolder:
      final name = await _promptName(
        context,
        title: '新建文件夹',
        label: '文件夹名称',
        initial: _defaultFolderName,
        confirmLabel: '创建',
      );
      return name == null
          ? null
          : FileManagerActionCall(action, path: target.path, newName: name);

    case FileManagerEntryAction.open:
    case FileManagerEntryAction.openInNewTab:
    case FileManagerEntryAction.copy:
    case FileManagerEntryAction.cut:
    case FileManagerEntryAction.paste:
    case FileManagerEntryAction.copyPath:
    case FileManagerEntryAction.trash:
    case FileManagerEntryAction.deletePermanently:
      return FileManagerActionCall(action, path: target.path);
  }
}

/// 新文件夹的默认名。与核心撞名时的顺延规则（`名字 (2)`）配合使用，
/// 所以这里给一个普通名字就够了，不必在这里保证唯一。
const _defaultFolderName = '新建文件夹';

/// 不可撤销的破坏动作的二次确认。返回 `true` = 用户确认了。
///
/// 只对 [requiresConfirmation] 为真的动作有意义 —— 也就是**只有永久删除**。
/// 「移到回收站」不走这里：它有撤销通道，弹框只会变成每次删除都要多点一下
/// 的噪音（neoview 的默认配置同样不弹）。
Future<bool> confirmFileManagerDestructive(
  BuildContext context, {
  required FileManagerEntryAction action,
  required FileManagerEntryTarget target,
}) async {
  final prompt = deletePromptFor(
    action,
    count: target.count,
    restoreSupported: target.restoreSupported,
  );
  if (prompt == null) return true;

  final subject = selectionSubject(target.count);
  final body = prompt.permanent
      // 「删了就没了」这一句必须把**不可撤销**写在正文里，而不是靠按钮颜色 ——
      // 确认框最常见的错法是正文只描述事实、危险只在配色上，于是色盲用户
      // 与「一路点确定」的用户看到的是同一个框。
      ? '$subject将被永久删除，不进入回收站，也无法撤销。'
      : '$subject将被删除。${trashOutcomeHint(restoreSupported: prompt.restoreSupported)}。';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(prompt.permanent ? '永久删除？' : '删除？'),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => dialogContext.pop(false),
          child: Text(t.common.cancel),
        ),
        TextButton(
          onPressed: () => dialogContext.pop(true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          child: Text(prompt.permanent ? '永久删除' : '删除'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// 一个「填个名字」的对话框。返回 `null` = 取消。
///
/// 空名字按取消处理：核心那边空名字会失败，让用户拿到一个红条不如什么都不做 ——
/// 他清空输入框再点确定，意思就是不改了。
Future<String?> _promptName(
  BuildContext context, {
  required String title,
  required String label,
  required String initial,
  required String confirmLabel,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => _NameInputDialog(
      title: title,
      label: label,
      initial: initial,
      confirmLabel: confirmLabel,
    ),
  );
  final trimmed = name?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

class _NameInputDialog extends StatefulWidget {
  const _NameInputDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.confirmLabel,
  });

  final String title;
  final String label;
  final String initial;
  final String confirmLabel;

  @override
  State<_NameInputDialog> createState() => _NameInputDialogState();
}

class _NameInputDialogState extends State<_NameInputDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void initState() {
    super.initState();
    // 重命名时要选中主文件名（保留扩展名）—— 否则用户一打字就把 `.cbz`
    // 删掉了，而核心只会老老实实按新名字改，文件当场变得打不开。
    // 用 `TextSelection` 而不是 `..text` 赋值，光标留在末尾。
    final dot = widget.initial.lastIndexOf('.');
    _controller.selection = (dot > 0 && dot < widget.initial.length - 1)
        ? TextSelection(baseOffset: 0, extentOffset: dot)
        : TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label, isDense: true),
        onSubmitted: (value) => context.pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          onPressed: () => context.pop(_controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// ── 复制路径到系统剪贴板 ────────────────────────────────────────────────────

/// 把一批路径放进**系统**剪贴板（不是内部那个两步式剪贴板）。
///
/// 多行用换行分隔：粘进终端、粘进别的文件管理器的地址栏都能用。
Future<void> copyFileManagerPathsToClipboard(
  BuildContext context, {
  required List<String> paths,
}) async {
  final text = paths.where((path) => path.trim().isNotEmpty).join('\n');
  if (text.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  showSuccessToast(
    paths.length > 1 ? '已复制 ${paths.length} 条路径' : text,
    title: '已复制路径',
    context: context,
  );
}

// ── 说结果 ──────────────────────────────────────────────────────────────────

/// 「移到回收站」之后的提示条要说的话。
///
/// 走 [deletePromptFor] / [trashOutcomeHint] 而不是在这里另写一句：**能不能撤销**
/// 这件事只有一个判断入口，否则菜单上的后缀、确认框的正文、提示条三处会各说各的。
String fileManagerTrashOutcome({
  required int count,
  required bool restoreSupported,
}) {
  final hint = trashOutcomeHint(restoreSupported: restoreSupported);
  final subject = selectionSubject(count);
  return restoreSupported
      ? '已把$subject移到回收站，$hint'
      // 不可撤销时补一句「在哪儿」—— 用户还能自己去系统废纸篓里捞回来。
      : '已把$subject移到回收站，$hint（在系统废纸篓里）';
}

/// 「已复制 / 已剪切」之后提示条要说的话。
///
/// 明说「选个目录粘贴」：内部剪贴板是**两步式**的，第一条提示不说清下一步，
/// 用户会以为复制就是复制到系统剪贴板，然后在别处粘贴失败。
String fileManagerClipboardHint({required bool cut, required int count}) {
  final verb = cut ? '已剪切' : '已复制';
  return '$verb${selectionSubject(count)}，选个目录粘贴';
}

/// 一次批量操作的提示条该怎么弹。
///
/// 三条规矩：
/// - **全成功**才用成功样式。**一半失败也走警告** —— 一个绿条会让用户以为都成了；
/// - 摘要那句由核心给（它才知道每一条的结局），这里不重新数一遍；
/// - 失败时把**第一条第**具体原因附在后面。只说「3 项失败」等于没说，
///   而逐条弹（可能几十条）又会把提示条刷成瀑布。
void showFileManagerReport(BuildContext context, FileOpsReport report) {
  if (report.failed == 0 && report.cancelled == 0) {
    // 条数取「成功了几条」而不是「发出去几条」：两者只在有失败时才不同，
    // 而那条路径不会走到这里。
    final message = report.kind == 'trash'
        ? fileManagerTrashOutcome(
            count: report.succeeded,
            // 回执条数就是「以后能不能撤销」的答案：生成了回执才撤销得回来。
            restoreSupported: report.undoable > 0,
          )
        : report.summary;
    showSuccessToast(message, context: context);
    return;
  }

  final firstFailure = report.items
      .where((item) => item.status == FileOpsItemStatus.failed)
      .map(fileManagerItemFailureText)
      .firstOrNull;

  if (report.succeeded == 0 && report.failed == 0) {
    // 全是 cancelled：用户自己按的取消，不是错误。
    showInfoToast(report.summary, context: context);
    return;
  }

  showWarningToast(
    firstFailure == null
        ? report.summary
        : '${report.summary}　首个失败原因：$firstFailure',
    context: context,
  );
}

/// 一条失败结果说给用户听的那句话。
///
/// 优先用核心给的原文（`error`），它带了路径与 errno 描述；只有核心没给文案时
/// 才退化到错误码。**不翻译错误码** —— `EXDEV`（跨设备）这类码在这里翻成中文
/// 只会把「已经很清楚」变成「含糊」。
String fileManagerItemFailureText(FileOpsItemResult item) {
  final error = item.error;
  if (error != null && error.trim().isNotEmpty) {
    return error.trim();
  }
  final code = item.errorCode;
  if (code != null && code.trim().isNotEmpty) return code.trim();
  return item.path;
}
