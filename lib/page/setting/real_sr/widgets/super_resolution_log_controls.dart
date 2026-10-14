import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_log.dart';
import 'package:zephyr/widgets/app_log_dialog.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

class SuperResolutionLogControls extends StatelessWidget {
  const SuperResolutionLogControls({super.key});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: SuperResolutionLog.text));
    if (context.mounted) {
      showSuccessToast(t.realSr.upscaleLogCopied, context: context);
    }
  }

  Future<void> _openFolder(BuildContext context) async {
    try {
      final message = await SuperResolutionLog.openOutputFolder();
      if (context.mounted) {
        showInfoToast(message, context: context);
      }
    } catch (error) {
      if (context.mounted) {
        showErrorToast('$error', context: context);
      }
    }
  }

  void _showLog(BuildContext context) => showAppLogDialog(
    context,
    log: SuperResolutionLog.log,
    title: t.realSr.upscaleLog,
    emptyText: t.realSr.logEmptyText,
    copyLabel: t.realSr.copyLog,
    copiedToast: t.realSr.upscaleLogCopied,
    // 这个按钮开的是**最近产物**所在目录，不是日志文件 —— 超分的用法是
    // 「刚超分完那张图在哪」，所以把去向整个交给 SuperResolutionLog 自己决定。
    openLabel: t.realSr.openImageFolder,
    openAction: SuperResolutionLog.openOutputFolder,
    closeLabel: '关闭',
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          OutlinedButton.icon(
            onPressed: () => _showLog(context),
            icon: const GlyphIcon(AppGlyphs.article),
            label: Text(t.realSr.viewUpscaleLog),
          ),
          TextButton.icon(
            onPressed: () => _copy(context),
            icon: const GlyphIcon(AppGlyphs.copy),
            label: const Text('复制日志'),
          ),
          TextButton.icon(
            onPressed: () => _openFolder(context),
            icon: const GlyphIcon(AppGlyphs.folder),
            label: Text(t.realSr.openImageFolder),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(t.realSr.openImageFolderHint, style: TextStyle(fontSize: 12)),
    ],
  );
}
