import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/type/breadcrumb_style.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/navigation/path_breadcrumb.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

/// 直接预览生产组件，两种样式使用同一条示例路径。
class BreadcrumbStylePicker extends StatelessWidget {
  const BreadcrumbStylePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.animate = true,
  });

  final BreadcrumbStyle value;
  final ValueChanged<BreadcrumbStyle> onChanged;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.settings.breadcrumbStyle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final style in BreadcrumbStyle.values) ...[
            Semantics(
              selected: value == style,
              child: ActionBubbleTarget(
                enabled: animate,
                corner: 20,
                child: ElasticPress(
                  enabled: animate && !MediaQuery.disableAnimationsOf(context),
                  child: Material(
                    color: value == style
                        ? scheme.secondaryContainer
                        : scheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: value == style
                            ? scheme.primary
                            : scheme.outlineVariant,
                      ),
                    ),
                    child: InkWell(
                      key: ValueKey('breadcrumb-style:${style.name}'),
                      borderRadius: BorderRadius.circular(20),
                      splashFactory: NoSplash.splashFactory,
                      overlayColor: const WidgetStatePropertyAll(
                        Colors.transparent,
                      ),
                      onTap: () => onChanged(style),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    style == BreadcrumbStyle.restrained
                                        ? t.settings.breadcrumbRestrained
                                        : t.settings.breadcrumbExpressive,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                                if (value == style)
                                  const GlyphIcon(
                                    AppGlyphs.checkCircle,
                                    size: 22,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              style == BreadcrumbStyle.restrained
                                  ? t.settings.breadcrumbRestrainedHint
                                  : t.settings.breadcrumbExpressiveHint,
                            ),
                            const SizedBox(height: 12),
                            ExcludeSemantics(
                              child: IgnorePointer(
                                child: PathBreadcrumb(
                                  style: style,
                                  animate: false,
                                  entries: const [
                                    PathCrumb(
                                      id: '/',
                                      label: '/',
                                      isRoot: true,
                                    ),
                                    PathCrumb(id: '/Comics', label: 'Comics'),
                                    PathCrumb(
                                      id: '/Comics/Arknights',
                                      label: 'Arknights',
                                    ),
                                    PathCrumb(
                                      id: '/Comics/Arknights/Endfield',
                                      label: 'Endfield',
                                      isCurrent: true,
                                    ),
                                  ],
                                  overflowLabel: t.settings.breadcrumbAncestors,
                                  onSelected: (_) {},
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
