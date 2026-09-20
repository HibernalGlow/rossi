import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

/// 信息面板卡片的公共零碎：一行「键 : 值」与几个诚实的格式化函数。
///
/// 五张信息卡（书籍 / 图像 / 存储 / 时间 / 预加载）都是同一个形状 ——
/// 若干行键值对 —— 所以外壳只在这里出现一次；卡片各自只写自己那点数据。

/// 一行「键 : 值」。值可选中（复制路径 / ID 不用截屏）。
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    this.value,
    this.valueWidget,
    this.emphasis = false,
  });

  final String label;

  /// 纯文本值；`null` 显示成 `—`（「没有这项信息」与「空字符串」不混）。
  final String? value;

  /// 需要富样式（颜色 / 行内徽章）时用这个代替 [value]。
  final Widget? valueWidget;

  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            // 用 SelectionArea 包 Text 而不是 SelectableText：后者会按 maxLines
            // 预留整块高度，于是一行键值占了四行，面板被撑得七零八落。
            child:
                valueWidget ??
                SelectionArea(
                  child: Text(
                    value ?? '—',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: emphasis ? FontWeight.w500 : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    maxLines: 4,
                    // 路径与 ID 宁可换行也不要省略号 —— 截掉一半的抄不出来。
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

/// 卡片标题行右侧的计数 / 状态。
///
/// MD3 里这类次要信息走 `labelSmall` + `onSurfaceVariant`，主色留给真正可点的东西；
/// [emphasize] 只给「当前处于某种状态」这类需要一眼看到的词（如 GPU 就绪）。
class InfoCardCounter extends StatelessWidget {
  const InfoCardCounter(this.text, {super.key, this.emphasize = false});

  final String text;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: emphasize
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// 空态占位（没有阅读会话 / 这项信息与当前来源无关）。
class InfoEmpty extends StatelessWidget {
  const InfoEmpty({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `1.2 MB`；`null` / 0 显示成 `—`（**没有量到**与**真的是 0 字节**都算不了数）。
String formatInfoBytes(BigInt? bytes) {
  if (bytes == null || bytes <= BigInt.zero) return '—';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < suffixes.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${suffixes[index]}';
}

/// `2026-09-20 13:04:05`；`null` 显示成 `—`（Linux 上很多文件系统没有创建时间）。
String formatInfoDateTime(DateTime? time) {
  if (time == null) return '—';
  final local = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

/// 从文件名 / 路径取扩展名并大写（`jpg` / `JPG` 都显示成 `JPG`）。
String formatInfoExt(String pathOrName) {
  final ext = p.extension(pathOrName).replaceFirst('.', '');
  return ext.isEmpty ? '—' : ext.toUpperCase();
}
