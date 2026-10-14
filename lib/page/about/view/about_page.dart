import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zephyr/config/global/global.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/network/utils/github_proxy.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/service/update/check_update.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';

// --- 项目标识 ---
// 本仓自己的仓库（origin），与上游 [kUpstreamRepo] 分开维护：
// 项目地址 / Issues / 贡献者都指向前者，致谢卡片指向后者。
const String kProjectRepo = 'HibernalGlow/rossi';
const String kUpstreamRepo = 'deretame/Breeze';
const String kProjectRepoUrl = 'https://github.com/$kProjectRepo';
const String kUpstreamRepoUrl = 'https://github.com/$kUpstreamRepo';
const String kProjectIssuesUrl = '$kProjectRepoUrl/issues';
const String kProjectLicenseUrl = '$kProjectRepoUrl/blob/main/LICENSE';

typedef AboutVersionLoader = Future<String> Function();
typedef AboutContributorsLoader = Future<List<Map<String, dynamic>>> Function();
typedef AboutUrlLauncher = Future<void> Function(String url);

@RoutePage()
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  /// 测试注入钩子：保持 `const AboutPage({super.key})` 无额外构造参数，
  /// 避免 `auto_route_generator` 把 `AboutRoute` 改成非 const 构造。
  @visibleForTesting
  static AboutVersionLoader? debugVersionLoader;

  @visibleForTesting
  static AboutContributorsLoader? debugContributorsLoader;

  @visibleForTesting
  static AboutUrlLauncher? debugUrlLauncher;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _appVersion = t.about.loading;
  List<Map<String, dynamic>> _contributors = const [];
  bool _contributorsLoading = true;
  String? _contributorsError;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final versionLoader = AboutPage.debugVersionLoader ?? getAppVersion;
    versionLoader().then((version) {
      if (!mounted) return;
      setState(() => _appVersion = version);
    });
    await _fetchContributors();
  }

  Future<void> _fetchContributors() async {
    final customLoader = AboutPage.debugContributorsLoader;
    if (customLoader != null) {
      try {
        final data = await customLoader();
        if (!mounted) return;
        setState(() {
          _contributors = data;
          _contributorsLoading = false;
          _contributorsError = null;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _contributorsError = t.about.fetchFailed;
          _contributorsLoading = false;
        });
      }
      return;
    }

    // 单元/组件测试默认不走真实外网请求，避免无 Rust 桥或离线环境下悬挂。
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      if (!mounted) return;
      setState(() {
        _contributors = const [];
        _contributorsLoading = false;
        _contributorsError = null;
      });
      return;
    }

    const repoPath = '/repos/$kProjectRepo/contributors';
    final urls = [
      ...mirrorBaseUrls.map((base) => '${base}https://api.github.com$repoPath'),
      'https://api.github.com$repoPath',
    ];
    try {
      for (final url in urls) {
        try {
          final response = await fetch(
            url,
            headers: const {
              'User-Agent': 'Rossi',
              'Accept': 'application/vnd.github+json',
            },
            query: const {'per_page': 20},
          );
          if (response.ok && mounted) {
            final data = response.json;
            setState(() {
              _contributors = List<Map<String, dynamic>>.from(
                data is List ? data : const [],
              );
              _contributorsLoading = false;
              _contributorsError = null;
            });
            return;
          }
        } catch (_) {
          continue;
        }
      }
      if (mounted) {
        setState(() {
          _contributorsError = t.about.fetchFailed;
          _contributorsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _contributorsError = t.about.networkError;
          _contributorsLoading = false;
        });
      }
    }
  }

  Future<void> _openUrl(String url) async {
    HapticFeedback.lightImpact();
    final customLauncher = AboutPage.debugUrlLauncher;
    if (customLauncher != null) {
      await customLauncher(url);
      return;
    }
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      logger.e('无法打开链接: $url');
    }
  }

  void _openDisclaimer() {
    HapticFeedback.lightImpact();
    _showDisclaimerDialog();
  }

  @override
  Widget build(BuildContext context) {
    return SettingPageShell(
      title: t.about.title,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          _buildHeroCard(context),
          const SizedBox(height: 20),
          SettingGroup(
            sectionId: 'about.links',
            children: [
              _buildLinkTile(
                context,
                key: const ValueKey('about-link:project'),
                icon: AppGlyphs.rocket,
                tone: ExpressiveTone.primary,
                sided: M3EShapeKind.cookie4Sided,
                title: t.about.projectAddress,
                description: t.about.projectAddressDesc,
                linkText: t.about.projectLink,
                onTap: () => _openUrl(kProjectRepoUrl),
              ),
              _buildLinkTile(
                context,
                key: const ValueKey('about-link:feedback'),
                icon: AppGlyphs.bug,
                tone: ExpressiveTone.secondary,
                sided: M3EShapeKind.cookie6Sided,
                title: t.about.feedback,
                description: t.about.feedbackDesc,
                linkText: t.about.feedbackLink,
                onTap: () => _openUrl(kProjectIssuesUrl),
              ),
              _buildLinkTile(
                context,
                key: const ValueKey('about-link:upstream'),
                icon: AppGlyphs.compass,
                tone: ExpressiveTone.tertiary,
                sided: M3EShapeKind.cookie4Sided,
                title: t.about.upstream,
                description: t.about.upstreamDesc,
                linkText: t.about.upstreamLink,
                onTap: () => _openUrl(kUpstreamRepoUrl),
              ),
            ],
          ),
          _buildContributorsGroup(context),
          SettingGroup(
            sectionId: 'about.legal',
            children: [
              _buildLinkTile(
                context,
                key: const ValueKey('about-link:license'),
                icon: AppGlyphs.gavel,
                tone: ExpressiveTone.primary,
                sided: M3EShapeKind.cookie6Sided,
                title: t.about.license,
                description: t.about.licenseDesc,
                linkText: t.about.licenseLink,
                onTap: () => _openUrl(kProjectLicenseUrl),
              ),
              _buildDisclaimerTile(context),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 顶部 MD3 Expressive 品牌横幅：
  /// 采用 `surfaceContainerLow` 语义容器与非对称圆角（`expressiveCornerLg`），
  /// 搭配基于 `poc/mask-upright.svg` 动态着色的 [BrandAppIcon]（`primaryContainer` 底板 + `primary` 面具），
  /// 不再使用静态位图、硬编码荧光蓝或重阴影，随全局种子色与明暗主题自适应。
  Widget _buildHeroCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final animate =
        !eInkInstantRoutes && !MediaQuery.disableAnimationsOf(context);

    return Container(
      key: const ValueKey('about-hero-card'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: expressiveCornerLg,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.32),
          width: 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
          final compact = constraints.maxWidth < 420 * scale.clamp(1.0, 1.5);

          final avatar = ElasticPress(
            enabled: animate,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                BrandAppIcon(
                  key: const ValueKey('about-brand-icon'),
                  size: 84,
                  foregroundColor: scheme.primary,
                  backgroundColor: scheme.primaryContainer,
                  borderColor: scheme.primary.withValues(alpha: 0.28),
                ),
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: M3EShapeContainer(
                    kind: M3EShapeKind.cookie6Sided,
                    width: 28,
                    height: 28,
                    color: scheme.primary,
                    child: Center(
                      child: GlyphIcon(
                        AppGlyphs.sparkle,
                        size: 15,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );

          final info = Column(
            crossAxisAlignment: compact
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                appDisplayName,
                textAlign: compact ? TextAlign.center : TextAlign.start,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t.about.tagline,
                textAlign: compact ? TextAlign.center : TextAlign.start,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: compact ? WrapAlignment.center : WrapAlignment.start,
                children: [
                  Container(
                    key: const ValueKey('about-version-pill'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: ShapeDecoration(
                      color: scheme.primary,
                      shape: const StadiumBorder(),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GlyphIcon(
                          AppGlyphs.info,
                          size: 14,
                          color: scheme.onPrimary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            t.about.version(version: _appVersion),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: ShapeDecoration(
                      color: scheme.secondaryContainer,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      'MPL-2.0',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [avatar, const SizedBox(height: 16), info],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              avatar,
              const SizedBox(width: 22),
              Expanded(child: info),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLinkTile(
    BuildContext context, {
    required Key key,
    required Glyph icon,
    required ExpressiveTone tone,
    required M3EShapeKind sided,
    required String title,
    required String description,
    required String linkText,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      key: key,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      leading: ExpressiveIconBadge(
        icon: icon,
        size: 44,
        glyphSize: 22,
        tone: tone,
        sided: sided,
      ),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              linkText,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      trailing: GlyphIcon(
        AppGlyphs.openExternal,
        size: 20,
        color: scheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }

  Widget _buildDisclaimerTile(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      key: const ValueKey('about-link:disclaimer'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      leading: const ExpressiveIconBadge(
        icon: AppGlyphs.shield,
        size: 44,
        glyphSize: 22,
        tone: ExpressiveTone.secondary,
        sided: M3EShapeKind.cookie4Sided,
      ),
      title: Text(
        t.about.disclaimer,
        style: theme.textTheme.titleMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          t.about.disclaimerTitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ),
      trailing: GlyphIcon(
        AppGlyphs.chevronForward,
        size: 20,
        color: scheme.onSurfaceVariant,
      ),
      onTap: _openDisclaimer,
    );
  }

  Widget _buildContributorsGroup(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SettingGroup(
      sectionId: 'about.contributors',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const ExpressiveIconBadge(
                    icon: AppGlyphs.heart,
                    size: 40,
                    glyphSize: 20,
                    tone: ExpressiveTone.primary,
                    sided: M3EShapeKind.cookie6Sided,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      t.about.contributors,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ExpressiveStatusPill(
                    text: t.about.contributorsCount(
                      count: _contributors.length,
                    ),
                    tone: ExpressiveTone.secondary,
                    dot: false,
                    icon: AppGlyphs.account,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_contributorsLoading)
                ExpressiveStatusPill(
                  text: t.about.loading,
                  tone: ExpressiveTone.secondary,
                  icon: AppGlyphs.hourglass,
                  dot: false,
                )
              else if (_contributorsError != null)
                Row(
                  children: [
                    Expanded(
                      child: ExpressiveEmptyState(
                        icon: AppGlyphs.wifiOff,
                        text: _contributorsError!,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElasticButton(
                      enabled:
                          !eInkInstantRoutes &&
                          !MediaQuery.disableAnimationsOf(context),
                      child: FilledButton.tonal(
                        key: const ValueKey('about-contributors-retry'),
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _contributorsLoading = true;
                            _contributorsError = null;
                          });
                          _fetchContributors();
                        },
                        child: Text(t.common.retry),
                      ),
                    ),
                  ],
                )
              else if (_contributors.isEmpty)
                ExpressiveEmptyState(
                  icon: AppGlyphs.account,
                  text: t.common.empty,
                )
              else
                ActionBubbleRegion(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final contributor in _contributors)
                        _buildContributorChip(
                          context,
                          avatarUrl:
                              (contributor['avatar_url'] as String?) ?? '',
                          login: (contributor['login'] as String?) ?? '',
                          contributions:
                              (contributor['contributions'] as int?) ?? 0,
                          htmlUrl: (contributor['html_url'] as String?) ?? '',
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContributorChip(
    BuildContext context, {
    required String avatarUrl,
    required String login,
    required int contributions,
    required String htmlUrl,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tooltipText = t.about.contributionsTooltip(
      login: login,
      count: contributions,
    );

    return Tooltip(
      message: tooltipText,
      child: ExpressiveTile(
        key: ValueKey('about-contributor:$login'),
        tone: ExpressiveTone.neutral,
        radius: expressiveCornerSm,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        semanticLabel: tooltipText,
        onTap: htmlUrl.isEmpty ? null : () => _openUrl(htmlUrl),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: avatarUrl.isEmpty
                  ? Center(
                      child: GlyphIcon(
                        AppGlyphs.account,
                        size: 16,
                        color: scheme.onPrimaryContainer,
                      ),
                    )
                  : Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Center(
                        child: GlyphIcon(
                          AppGlyphs.account,
                          size: 16,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                login,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: ShapeDecoration(
                color: scheme.secondaryContainer,
                shape: const StadiumBorder(),
              ),
              child: Text(
                '$contributions',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 免责声明弹层：走全仓统一的 `showPopupPanel` + `PopupPanel`（`CommonPopupSurface`），
  /// 不再使用硬编码深紫底色、青色荧光边框或 `Divider`。
  void _showDisclaimerDialog() {
    final items = <(String, String)>[
      (t.about.disclaimerItem1Title, t.about.disclaimerItem1Content),
      (t.about.disclaimerItem2Title, t.about.disclaimerItem2Content),
      (t.about.disclaimerItem3Title, t.about.disclaimerItem3Content),
      (t.about.disclaimerItem4Title, t.about.disclaimerItem4Content),
      (t.about.disclaimerItem5Title, t.about.disclaimerItem5Content),
      (t.about.disclaimerItem6Title, t.about.disclaimerItem6Content),
      (t.about.disclaimerItem7Title, t.about.disclaimerItem7Content),
      (t.about.disclaimerItem8Title, t.about.disclaimerItem8Content),
    ];

    showPopupPanel<void>(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;

        return PopupPanel(
          title: Row(
            children: [
              const ExpressiveIconBadge(
                icon: AppGlyphs.shield,
                size: 32,
                glyphSize: 18,
                tone: ExpressiveTone.primary,
                sided: M3EShapeKind.cookie4Sided,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t.about.disclaimer,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: t.common.close,
                icon: GlyphIcon(
                  AppGlyphs.close,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 440),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExpressiveTile(
                    tone: ExpressiveTone.primary,
                    radius: expressiveCornerMd,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Text(
                      t.about.disclaimerTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final (itemTitle, itemContent) in items) ...[
                    _DisclaimerItem(title: itemTitle, content: itemContent),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 4),
                  ExpressiveTile(
                    tone: ExpressiveTone.warning,
                    radius: expressiveCornerMd,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            GlyphIcon(
                              AppGlyphs.warning,
                              size: 18,
                              color: scheme.onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                t.about.disclaimerImportant,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: scheme.onErrorContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t.about.disclaimerImportantContent,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            ElasticButton(
              enabled:
                  !eInkInstantRoutes && !MediaQuery.disableAnimationsOf(ctx),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(t.common.gotIt),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DisclaimerItem extends StatelessWidget {
  const _DisclaimerItem({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ExpressiveTile(
      tone: ExpressiveTone.sunken,
      radius: expressiveCornerSm,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
