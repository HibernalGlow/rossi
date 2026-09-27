import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/service/diagnostics/app_log.dart';

/// 弹出某一份 [AppLog] 的查看框：正文可选中、可整份复制，附带一个「打开位置」。
///
/// 为什么要抽出来：超分那份日志的对话框已经写了整套（`ValueListenable` + 倒序滚动 +
/// monospace + 复制 + 打开 + 空态文案），漫画翻译要的是同一个东西。再抄一遍就是第三份。
///
/// 文案一律由调用方给 —— 超分那页的按钮本来就是硬编码中文，翻译那页走 i18n，
/// 统一机制不该顺手改掉一个已经在用的界面。
Future<void> showAppLogDialog(
  BuildContext context, {
  required AppLog log,
  required String title,
  required String emptyText,
  required String copyLabel,
  required String openLabel,
  required String copiedToast,
  required String closeLabel,
  Future<String> Function()? openAction,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 720,
      height: MediaQuery.sizeOf(context).height * .55,
      child: ValueListenableBuilder(
        valueListenable: log.entries,
        builder: (context, entries, _) => SingleChildScrollView(
          reverse: true,
          child: SelectableText(
            entries.isEmpty ? emptyText : log.text,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: log.text));
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(copiedToast)));
          }
        },
        child: Text(copyLabel),
      ),
      TextButton(
        onPressed: () async {
          try {
            final message = await (openAction ?? log.revealFile)();
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(message)));
            }
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('$error')));
            }
          }
        },
        child: Text(openLabel),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(closeLabel),
      ),
    ],
  ),
);
