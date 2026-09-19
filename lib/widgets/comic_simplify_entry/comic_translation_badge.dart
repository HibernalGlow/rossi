import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/util/comic/chinese_translation_matcher.dart';

/// 卡片封面左上角的**语言 / 汉化**角标。
///
/// 判定是纯函数（[ChineseTranslationMatcher]），这里只负责把
/// [ChineseTranslationKind] 画成一个词。悬停提示里会带上命中来源，
/// 因为各家插件的标签词汇不一样（见 [ChineseTranslationMatcher] 的注释）。
///
/// 与「喜欢画师」角标同形状、同位置族（左上角纵向排列），
/// 保证扫一列卡片时不会两处来回看。
class ComicTranslationBadge extends StatelessWidget {
  const ComicTranslationBadge({
    super.key,
    required this.match,
    this.compact = false,
  });

  final ChineseTranslationMatch match;

  /// 窄卡片上用更小的字号与内边距。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!match.hasBadge) {
      return const SizedBox.shrink();
    }

    final (String label, Color background) = switch (match.kind) {
      ChineseTranslationKind.translated => (
        t.comicEntry.translationBadgeTranslated,
        const Color(0xFF10B981),
      ),
      ChineseTranslationKind.chinese => (
        t.comicEntry.translationBadgeChinese,
        const Color(0xFF3B82F6),
      ),
      ChineseTranslationKind.raw => (
        t.comicEntry.translationBadgeRaw,
        const Color(0xFF64748B),
      ),
      ChineseTranslationKind.none => ('', Colors.transparent),
    };

    final keyword = match.matchedText ?? '';
    final tooltip = keyword.isEmpty
        ? label
        : match.matchedInTitle
        ? t.comicEntry.translationTooltipTitle(label: label, keyword: keyword)
        : t.comicEntry.translationTooltipTag(label: label, keyword: keyword);

    return Tooltip(
      message: tooltip,
      // triggerMode 必须是 manual：默认的 longPress 触发会跟卡片自身的长按
      // （多选 / 右键菜单）抢同一个手势。桌面悬停提示不受影响。
      triggerMode: TooltipTriggerMode.manual,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 5, vertical: 2),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 9 : 10,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
