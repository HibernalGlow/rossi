import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_log.dart';
import 'package:zephyr/widgets/app_log_dialog.dart';

class SuperResolutionLogControls extends StatelessWidget {
  const SuperResolutionLogControls({super.key});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: SuperResolutionLog.text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('超分日志已复制')));
    }
  }

  Future<void> _openFolder(BuildContext context) async {
    try {
      final message = await SuperResolutionLog.openOutputFolder();
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
  }

  void _showLog(BuildContext context) => showAppLogDialog(
    context,
    log: SuperResolutionLog.log,
    title: '超分日志',
    emptyText: '尚无超分日志。启用超分后，推理和替换过程会记录在这里。',
    copyLabel: '复制日志',
    copiedToast: '超分日志已复制',
    // 这个按钮开的是**最近产物**所在目录，不是日志文件 —— 超分的用法是
    // 「刚超分完那张图在哪」，所以把去向整个交给 SuperResolutionLog 自己决定。
    openLabel: '打开图片文件夹',
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
            icon: const Icon(Icons.article_outlined),
            label: const Text('查看超分日志'),
          ),
          TextButton.icon(
            onPressed: () => _copy(context),
            icon: const Icon(Icons.copy_outlined),
            label: const Text('复制日志'),
          ),
          TextButton.icon(
            onPressed: () => _openFolder(context),
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('打开图片文件夹'),
          ),
        ],
      ),
      const SizedBox(height: 4),
      const Text('定位最近生成的超分图；尚未生成时打开超分缓存目录。', style: TextStyle(fontSize: 12)),
    ],
  );
}
