import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/config/global/global.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/util/permission.dart';
import 'package:zephyr/widgets/toast.dart';

/// 书签 / 历史面板共用的导入导出管路：权限 → 选位置 → 读写文件 → 说结果。
///
/// 抽成一份的理由不是「两处代码像」，而是**这两处的坑是同一批**：Android 写
/// 用户目录要先拿到「所有文件访问」权限、iOS 的 `file_selector` 没有
/// `getDirectoryPath` 只能写缓存再甩给分享面板、用户中途取消目录选择不能算失败。
/// 各写一遍的结局就是其中一边漏掉一条，而且漏的那条只在真机上暴露。
///
/// 忙状态由调用方持有（那是卡片自己的 `setState`），这里只通过 [onBusyChanged] 请求。

/// 整个文件读不了才抛这个（单条坏条目是「跳过并说原因」，不走这里）。
class ShelfFormatException implements Exception {
  const ShelfFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一份「看了就知道要动多少条」的导入计划。
///
/// 书签与历史各自的计划类型字段不一样（复活 / 覆盖 / 因为更旧而跳过），但用户在
/// 点「导入」之前需要看到的东西是同一件：**结论 + 为什么跳过**。所以这里只收
/// 一句结论、要写的条数、跳过原因，外加一个把写入真正执行出去的 [apply]。
class ShelfImportPlan {
  const ShelfImportPlan({
    required this.summary,
    required this.writeCount,
    required this.apply,
    this.rejectedLines = const [],
    this.note = '只合并，不会删除或覆盖已有的记录。',
  });

  /// 给用户看的一句话结论（`新增 3 条 · 跳过 1 条`）。
  final String summary;

  /// 真正会写库的条数。为 0 时「导入」按钮是灰的 —— 没有要写的东西。
  final int writeCount;

  /// 逐条跳过原因（`第 2 条 — 缺少标题`）。
  final List<String> rejectedLines;

  /// 为什么这份导入不会伤人。两侧口径不同，所以让调用方自己给。
  final String note;

  /// 落库。只在用户确认之后被调用一次。
  final void Function() apply;
}

/// 导出：选目录 → 写 JSON → 报路径。
Future<void> exportShelfDocument({
  required BuildContext context,
  required String label,
  required String fileStem,
  required int count,
  required String Function() encode,
  required void Function(bool busy) onBusyChanged,
}) async {
  // Android 写用户目录要「所有文件访问」权限，否则 Permission denied。
  final granted = await requestExportPermission();
  if (!granted) {
    if (context.mounted) showErrorToast(t.comicInfo.exportPermissionDenied);
    return;
  }
  if (count == 0) {
    if (context.mounted) showWarningToast('$label还是空的，没有可导出的内容');
    return;
  }
  final fileName =
      '$appDisplayName-$fileStem-${DateTime.now().millisecondsSinceEpoch}.json';
  final String target;
  if (Platform.isIOS) {
    // iOS 的 file_selector 没有 getDirectoryPath，先写缓存再走分享面板。
    target = p.join(await getCachePath(), fileName);
  } else {
    final dir = await getDirectoryPath();
    if (dir == null || dir.trim().isEmpty || !context.mounted) return;
    target = p.join(dir, fileName);
  }

  onBusyChanged(true);
  try {
    await File(target).writeAsString(encode());
    if (!context.mounted) return;
    if (Platform.isIOS) {
      showSuccessToast('已写入缓存，请在分享面板里保存');
      await OpenFile.open(target);
    } else {
      showSuccessToast('已导出 $count 条$label\n$target');
    }
  } on Object catch (e, s) {
    logger.e('导出$label失败', error: e, stackTrace: s);
    if (context.mounted) showErrorToast('导出$label失败：$e');
  } finally {
    if (context.mounted) onBusyChanged(false);
  }
}

/// 导入：选文件 → 出计划 → 让用户过目 → 落库。
///
/// 分成「先出计划再落库」而不是点一下文件对话框就闷头改库：用户至少要看见
/// 「要动多少条、哪几条被跳过、为什么」。
Future<void> importShelfDocument({
  required BuildContext context,
  required String label,
  required String fileLabel,
  required Future<ShelfImportPlan> Function(String path) planFrom,
  required void Function(bool busy) onBusyChanged,
}) async {
  final picked = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(
        label: fileLabel,
        extensions: const ['json'],
        mimeTypes: const ['application/json'],
      ),
    ],
  );
  final path = picked?.path;
  if (path == null) return;

  onBusyChanged(true);
  try {
    final plan = await planFrom(path);
    if (!context.mounted) return;
    final confirmed = await _confirmImport(context, label: label, plan: plan);
    if (!confirmed || !context.mounted) return;
    plan.apply();
    showSuccessToast(plan.summary, context: context);
  } on ShelfFormatException catch (e) {
    if (context.mounted) showErrorToast('读不了这个文件：${e.message}');
  } on Object catch (e, s) {
    logger.e('导入$label失败', error: e, stackTrace: s);
    if (context.mounted) showErrorToast('导入$label失败：$e');
  } finally {
    if (context.mounted) onBusyChanged(false);
  }
}

Future<bool> _confirmImport(
  BuildContext context, {
  required String label,
  required ShelfImportPlan plan,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('导入$label'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(plan.summary),
          const SizedBox(height: 8),
          Text(plan.note),
          if (plan.rejectedLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            // 只列前 5 条：一份坏文件能跳过几十条，全列出来这个对话框就没边了。
            Text('跳过的条目：\n${plan.rejectedLines.take(5).join('\n')}'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => dialogContext.pop(false),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          // 一条都不用写时灰掉：让「点了但什么都没发生」这件事不发生。
          onPressed: plan.writeCount == 0
              ? null
              : () => dialogContext.pop(true),
          child: const Text('导入'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
