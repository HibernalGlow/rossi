import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';

// 信息卡的「外壳 + 小组件」是一套：卡片只需要 import 本文件就能同时拿到
// InfoRow / InfoFacts 与 ExpressiveStatTile 等通用件。
export 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';

/// 信息面板卡片的公共零碎：一行「键 : 值」与几个诚实的格式化函数。
///
/// 五张信息卡（书籍 / 图像 / 存储 / 时间 / 预加载）都是同一个形状 ——
/// 若干行键值对 —— 所以外壳只在这里出现一次；卡片各自只写自己那点数据。
///
/// 版式对齐洞察面板：卡顶放几颗 `ExpressiveStatTile`（值得被读出来的数），
/// 剩下的次要事实收进 [InfoFacts] 这块下沉底板里的 [InfoRow]。

/// 一行「键 : 值」。值可选中（复制路径 / ID 不用截屏）。
///
/// 在 [InfoFacts] 里用时不要再给背景（底板已经提供分层）；单独用时
/// 传 [boxed]，它会自己画一颗 Expressive 格子。
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    this.value,
    this.valueWidget,
    this.emphasis = false,
    this.icon,
  });

  final String label;

  /// 纯文本值；`null` 显示成 `—`（「没有这项信息」与「空字符串」不混）。
  final String? value;

  /// 需要富样式（颜色 / 行内徽章）时用这个代替 [value]。
  final Widget? valueWidget;

  final bool emphasis;

  /// 行首那颗字形（可选）。洞察那边每格都有图标座，这里同口径。
  final Glyph? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelText = Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: emphasis
            ? scheme.onPrimaryContainer.withValues(alpha: .85)
            : scheme.onSurfaceVariant,
        letterSpacing: .3,
      ),
    );
    final content =
        valueWidget ??
        SelectionArea(
          child: Text(
            value ?? '—',
            style: theme.textTheme.bodySmall?.copyWith(
              color: emphasis ? scheme.onPrimaryContainer : scheme.onSurface,
              fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
    final leading = icon == null
        ? const SizedBox.shrink()
        : ExpressiveIconBadge(
            icon: icon!,
            size: 24,
            color: emphasis
                ? scheme.primary.withValues(alpha: .2)
                : scheme.primary.withValues(alpha: .12),
            foreground: emphasis ? scheme.onPrimaryContainer : scheme.primary,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 路径和日期在窄卡里独占一行，跟随卡片宽度而非整个窗口。
          if (constraints.maxWidth < 260 ||
              MediaQuery.textScalerOf(context).scale(12) > 18) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[leading, const SizedBox(width: 8)],
                    Expanded(child: labelText),
                  ],
                ),
                const SizedBox(height: 3),
                content,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[leading, const SizedBox(width: 8)],
              SizedBox(width: 80, child: labelText),
              const SizedBox(width: 8),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}

/// 信息小组件的事实区：宽卡分两列，窄卡纵向排列，长路径保留全文。
///
/// 底板是一层**下沉**的 Expressive 容器（比卡片本身浅一档）配大圆角，
/// 于是行与行之间不需要各自的边框 —— 分层靠容器色，不靠描边。
class InfoFacts extends StatelessWidget {
  const InfoFacts({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns =
          constraints.maxWidth >= 560 &&
          MediaQuery.textScalerOf(context).scale(12) <= 18;
      return ExpressiveTile(
        tone: ExpressiveTone.sunken,
        radius: expressiveCornerLg,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: LayoutBuilder(
          builder: (context, inner) => Wrap(
            spacing: 16,
            runSpacing: 0,
            children: [
              for (final child in children)
                SizedBox(
                  width: twoColumns
                      ? (inner.maxWidth - 16) / 2
                      : inner.maxWidth,
                  child: child,
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// 卡片标题行右侧的计数 / 状态。
///
/// Expressive 里这类次要信息走一颗状态胶囊：颜色承载「就绪 / 进行中 / 失败」，
/// 数字仍然用 tabular figures 对齐。[emphasize] 给「当前处于某种状态」
/// 这类需要一眼看到的词（如 GPU 就绪）。
class InfoCardCounter extends StatelessWidget {
  const InfoCardCounter(this.text, {super.key, this.emphasize = false});

  final String text;
  final bool emphasize;

  @override
  Widget build(BuildContext context) => ExpressiveStatusPill(
    text: text,
    compact: true,
    dot: false,
    tone: emphasize ? ExpressiveTone.primary : ExpressiveTone.neutral,
  );
}

/// 空态占位（没有阅读会话 / 这项信息与当前来源无关）。
class InfoEmpty extends StatelessWidget {
  const InfoEmpty({
    super.key,
    required this.icon,
    required this.text,
    this.hint,
    this.fields,
  });

  final Glyph icon;
  final String text;

  /// 「打开之后这里会出现什么」——一句话，避免只说「暂无」。
  final String? hint;

  /// 这张卡**量哪几项**。给了就按小组件的版式先摆出这些格子（值全是 `—`），
  /// 于是空卡与满卡是同一个形状。
  ///
  /// 为什么值得摆：截图里右侧那四张卡就是空态，一行灰字飘在一个大空盒里，
  /// 读起来像「这块面板没做完」而不是「还没开书」。格子摆出来之后，
  /// 用户一眼知道开书之后这里会有哪几项、占多大地方。
  /// 字段名是卡片自己写死的静态项，**不是**编出来的数据。
  /// `(字段名, 行首字形)` —— 字形与填上之后的那一行**同一个**，
  /// 否则空卡与满卡只是「都有格子」而不是「同一个形状」。
  final List<(String, Glyph)>? fields;

  @override
  Widget build(BuildContext context) {
    if (fields == null || fields!.isEmpty) {
      return ExpressiveEmptyState(icon: icon, text: text, hint: hint);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExpressiveEmptyState(icon: icon, text: text, hint: hint),
        const SizedBox(height: 12),
        InfoFacts(
          children: [
            for (final (label, glyph) in fields!)
              InfoRow(label: label, value: null, icon: glyph),
          ],
        ),
      ],
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

/// 大数字格里那句「多久以前」：今天看时刻，今年看月日，再远看年份。
///
/// 绝对时间戳塞进大数字格会撑爆宽度，而且读的人真正要的是远近；
/// 完整时间戳留在 [formatInfoDateTime] 那一行（作 caption 或事实行）。
String formatInfoTimeOfDay(DateTime? time) {
  if (time == null) return '—';
  final local = time.toLocal();
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(local.year, local.month, local.day)).inDays;
  String two(int v) => v.toString().padLeft(2, '0');

  if (days == 0) return '${two(local.hour)}:${two(local.minute)}';
  if (days == 1) return '昨天';
  if (days < 7) return '$days 天前';
  if (local.year == now.year) return '${two(local.month)}-${two(local.day)}';
  return '${local.year}';
}

/// 从文件名 / 路径取扩展名并大写（`jpg` / `JPG` 都显示成 `JPG`）。
String formatInfoExt(String pathOrName) {
  final ext = p.extension(pathOrName).replaceFirst('.', '');
  return ext.isEmpty ? '—' : ext.toUpperCase();
}
