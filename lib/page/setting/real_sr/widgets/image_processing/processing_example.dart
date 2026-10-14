import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

enum ProcessingExampleKind { autoTrim, denoise }

/// 内置静态示例，不依赖模型下载、当前页面或图片处理开关。
class ProcessingExample extends StatelessWidget {
  const ProcessingExample({super.key, required this.kind});

  final ProcessingExampleKind kind;

  String get _title => switch (kind) {
    ProcessingExampleKind.autoTrim => '裁边示例',
    ProcessingExampleKind.denoise => '降噪示例',
  };

  String get _description => switch (kind) {
    ProcessingExampleKind.autoTrim => '去掉四周余白，让漫画内容更大。示意图不随参数变化。',
    ProcessingExampleKind.denoise =>
      '同一 JPEG 局部经 RealPLKSR 1× 实际处理，分辨率保持不变。效果随原图而变化。',
  };

  String get _prefix => switch (kind) {
    ProcessingExampleKind.autoTrim => 'trim',
    ProcessingExampleKind.denoise => 'denoise',
  };

  String get _beforeLabel => switch (kind) {
    ProcessingExampleKind.autoTrim => '原始页面',
    ProcessingExampleKind.denoise => 'JPEG 压缩图',
  };

  String get _afterLabel => switch (kind) {
    ProcessingExampleKind.autoTrim => '裁边显示',
    ProcessingExampleKind.denoise => '1× 降噪后',
  };

  Widget _pair(BuildContext context, {bool enlarged = false}) {
    Widget panel(bool after) {
      final colors = Theme.of(context).colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: kind == ProcessingExampleKind.autoTrim ? .8 : 1,
              child: Image.asset(
                'asset/image/processing_examples/${_prefix}_${after ? 'after' : 'before'}.png',
                fit: BoxFit.contain,
                filterQuality: kind == ProcessingExampleKind.autoTrim
                    ? FilterQuality.medium
                    : FilterQuality.none,
                excludeFromSemantics: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: after
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
            ),
            child: Text(
              after ? _afterLabel : _beforeLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: after ? colors.onPrimaryContainer : colors.onSurface,
              ),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 大图在手机上纵向排列，避免放大入口仍然只显示小缩略图。
        if (enlarged && constraints.maxWidth < 480) {
          return Column(
            children: [panel(false), const SizedBox(height: 16), panel(true)],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: panel(false)),
            const SizedBox(width: 12),
            Expanded(child: panel(true)),
          ],
        );
      },
    );
  }

  void _showEnlarged(BuildContext context) {
    HapticFeedback.lightImpact();
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      tooltip: '关闭示例',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _pair(context, enlarged: true),
                const SizedBox(height: 16),
                Text(
                  _description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      button: true,
      label: '$_title。$_beforeLabel与$_afterLabel对比。点击查看大图。$_description',
      excludeSemantics: true,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showEnlarged(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const Icon(Icons.zoom_in, size: 20),
                  ],
                ),
                const SizedBox(height: 12),
                _pair(context),
                const SizedBox(height: 10),
                Text(
                  _description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
