import 'package:flutter/services.dart'
    show HapticFeedback, KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_blob.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/widgets/motion/action_bubble.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 「切换提示」卡片 —— neoview「控制」面板的 `SwitchToastCard` 的 Flutter 重建。
///
/// 上游卡片四节里的「提示悬浮窗」（X/Y 摆位、透明度、液态玻璃）**不在这里**：
/// Rossi 的提示条外观统一由「设置 → 提示样式」的九宫格负责，两处摆位会打架。
/// 保留的是这张卡的实质：**触发条件 + 两本模板 + 变量胶囊（点击直接插入） + 测试提示**。
///
/// 输入框沿用上游 `DraftTextarea` 的语义：失焦才提交、`Esc` 取消回滚，
/// 同时支持点击下方 M3E 模板变量胶囊直接插入到当前聚焦（或最近激活）的模板输入框。
class SwitchToastCard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final bool isStandalone;

  const SwitchToastCard({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.isStandalone = false,
  });

  @override
  State<SwitchToastCard> createState() => _SwitchToastCardState();
}

class _SwitchToastCardState extends State<SwitchToastCard> {
  static List<(String, String, Glyph)> get _bookVariables => [
    ('{{book.displayName}}', t.workspace.bookDisplayName, AppGlyphs.book),
    (
      '{{book.currentPageDisplay}}',
      t.workspace.currentPageNumber,
      AppGlyphs.bookmark,
    ),
    ('{{book.totalPages}}', t.workspace.totalPagesLabel, AppGlyphs.layers),
    (
      '{{book.progressPercent}}',
      t.workspace.readingProgressPercent,
      AppGlyphs.pieChart,
    ),
    ('{{book.path}}', t.workspace.bookPathLocalOnly, AppGlyphs.folder),
  ];

  static List<(String, String, Glyph)> get _pageVariables => [
    (
      '{{page.indexDisplay}}',
      t.workspace.currentPageNumber,
      AppGlyphs.linearScale,
    ),
    ('{{page.name}}', t.workspace.pageFileName, AppGlyphs.article),
    ('{{page.path}}', t.workspace.pagePath, AppGlyphs.folderCopy),
  ];

  final GlobalKey<_DraftFieldState> _boundaryFieldKey =
      GlobalKey<_DraftFieldState>();

  static int _activeTriggerCount(SwitchToastSettingState s) =>
      (s.enableBook ? 1 : 0) +
      (s.enablePage ? 1 : 0) +
      (s.enableBoundaryToast ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final setting = context
        .watch<GlobalSettingCubit>()
        .state
        .switchToastSetting;
    final activeCount = _activeTriggerCount(setting);

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExpressiveHeroBanner(
          seed: expressiveBlobSeed('switch_toast_hero'),
          icon: AppGlyphs.customize,
          shape: ExpressiveButtonShape.softBurst,
          tone: activeCount > 0
              ? ExpressiveTone.secondary
              : ExpressiveTone.neutral,
          active: activeCount > 0,
          title: t.workspace.readingToastOverlay,
          subtitle: t.workspace.toastStyleInSettings,
          pills: [
            ExpressiveStatusPill(
              text: activeCount == 0
                  ? t.workspace.triggersAllOff
                  : t.workspace.switchToastActiveOf3(activeCount: activeCount),
              icon: activeCount == 0 ? AppGlyphs.bellOff : AppGlyphs.bell,
              dot: false,
              compact: true,
              tone: activeCount > 0
                  ? ExpressiveTone.primary
                  : ExpressiveTone.neutral,
            ),
            if (setting.enableBook)
              ExpressiveStatusPill(
                text: t.workspace.bookSwitchToast,
                icon: AppGlyphs.book,
                dot: false,
                compact: true,
                tone: ExpressiveTone.primary,
              ),
            if (setting.enablePage)
              ExpressiveStatusPill(
                text: t.workspace.pageTurnToast,
                icon: AppGlyphs.photos,
                dot: false,
                compact: true,
                tone: ExpressiveTone.secondary,
              ),
            if (setting.enableBoundaryToast)
              ExpressiveStatusPill(
                text: t.workspace.lastPageToast,
                icon: AppGlyphs.locate,
                dot: false,
                compact: true,
                tone: ExpressiveTone.tertiary,
              ),
          ],
          trailing: FilledButton.tonalIcon(
            onPressed: () {
              HapticFeedback.lightImpact();
              showInfoToast(
                t.workspace.thisIsSwitchToastPreview,
                title: t.workspace.switchToastTest,
                context: context,
              );
            },
            icon: const GlyphIcon(AppGlyphs.play, size: 14),
            label: const Text('显示测试提示', style: TextStyle(fontSize: 11)),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: const StadiumBorder(),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _Section(
          title: t.workspace.triggerCondition,
          icon: AppGlyphs.bell,
          children: [
            ExpressiveTileGrid(
              minTileWidth: 170,
              spacing: 8,
              children: [
                ExpressiveToggleTile(
                  title: t.workspace.toastOnBookSwitch,
                  subtitle: t.workspace.toastOnOpenOrSwitch,
                  icon: AppGlyphs.book,
                  shape: ExpressiveButtonShape.clover4Leaf,
                  activeTone: ExpressiveTone.primary,
                  value: setting.enableBook,
                  onChanged: (v) => context
                      .read<GlobalSettingCubit>()
                      .updateSwitchToastSetting(
                        (c) => c.copyWith(enableBook: v),
                      ),
                ),
                ExpressiveToggleTile(
                  title: t.workspace.toastOnPageSwitch,
                  subtitle: t.workspace.pageToastShowsNumber,
                  icon: AppGlyphs.photos,
                  shape: ExpressiveButtonShape.sunny,
                  activeTone: ExpressiveTone.secondary,
                  value: setting.enablePage,
                  onChanged: (v) => context
                      .read<GlobalSettingCubit>()
                      .updateSwitchToastSetting(
                        (c) => c.copyWith(enablePage: v),
                      ),
                ),
                ExpressiveToggleTile(
                  title: t.workspace.toastOnLastPage,
                  subtitle: t.workspace.toastAtChapterEnd,
                  icon: AppGlyphs.locate,
                  shape: ExpressiveButtonShape.puffyDiamond,
                  activeTone: ExpressiveTone.tertiary,
                  value: setting.enableBoundaryToast,
                  onChanged: (v) => context
                      .read<GlobalSettingCubit>()
                      .updateSwitchToastSetting(
                        (c) => c.copyWith(enableBoundaryToast: v),
                      ),
                ),
              ],
            ),
          ],
        ),
        _TemplateSection(
          seed: expressiveBlobSeed('book_template_section'),
          tone: ExpressiveTone.primary,
          title: t.workspace.bookToastTemplate,
          icon: AppGlyphs.book,
          titleLabel: t.workspace.bookTitleTemplate,
          titleValue: setting.bookTitleTemplate,
          titlePlaceholder: t.workspace.egSwitchedToBook,
          onTitleCommit: (v) =>
              context.read<GlobalSettingCubit>().updateSwitchToastSetting(
                (c) => c.copyWith(bookTitleTemplate: v),
              ),
          descriptionLabel: t.workspace.bookDescriptionTemplate,
          descriptionValue: setting.bookDescriptionTemplate,
          descriptionPlaceholder: t.workspace.egBookPath,
          onDescriptionCommit: (v) =>
              context.read<GlobalSettingCubit>().updateSwitchToastSetting(
                (c) => c.copyWith(bookDescriptionTemplate: v),
              ),
          variables: _bookVariables,
        ),
        _TemplateSection(
          seed: expressiveBlobSeed('page_template_section'),
          tone: ExpressiveTone.tertiary,
          title: t.workspace.pageToastTemplate,
          icon: AppGlyphs.photos,
          titleLabel: t.workspace.pageTitleTemplate,
          titleValue: setting.pageTitleTemplate,
          titlePlaceholder: t.workspace.egPageIndex,
          onTitleCommit: (v) =>
              context.read<GlobalSettingCubit>().updateSwitchToastSetting(
                (c) => c.copyWith(pageTitleTemplate: v),
              ),
          descriptionLabel: t.workspace.pageDescriptionTemplate,
          descriptionValue: setting.pageDescriptionTemplate,
          descriptionPlaceholder: t.workspace.egPageName,
          onDescriptionCommit: (v) =>
              context.read<GlobalSettingCubit>().updateSwitchToastSetting(
                (c) => c.copyWith(pageDescriptionTemplate: v),
              ),
          variables: _pageVariables,
          footer: Row(
            children: [
              GlyphIcon(
                AppGlyphs.sparkle,
                size: 13,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  t.workspace.pageTemplateBookVars,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        _Section(
          title: t.workspace.boundaryToastText,
          icon: AppGlyphs.chevronForward,
          children: [
            ExpressivePatchBackdrop(
              seed: expressiveBlobSeed('boundary_toast_section'),
              tone: ExpressiveTone.sunken,
              active: setting.enableBoundaryToast,
              intensity: 0.85,
              borderRadius: expressiveCornerMd,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DraftField(
                    key: _boundaryFieldKey,
                    label: t.workspace.lastPageToastText,
                    icon: AppGlyphs.locate,
                    value: setting.lastPageMessage,
                    placeholder: t.workspace.egLastPage,
                    onCommit: (v) => context
                        .read<GlobalSettingCubit>()
                        .updateSwitchToastSetting(
                          (c) => c.copyWith(lastPageMessage: v),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (preset, glyph) in [
                        (t.workspace.isLastPage, AppGlyphs.checkCircle),
                        (
                          t.workspace.chapterDonePreparingNext,
                          AppGlyphs.openBook,
                        ),
                        (t.workspace.reachedLastPage, AppGlyphs.sparkle),
                      ])
                        _VariableCapsule(
                          variable: preset,
                          description: t.workspace.clickToFill,
                          icon: glyph,
                          tone: ExpressiveTone.secondary,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _boundaryFieldKey.currentState?.replaceText(preset);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );

    if (widget.isStandalone) {
      content = SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: content,
      );
      return Material(type: MaterialType.transparency, child: content);
    }

    return CollapsibleCard(
      cardId: WorkspaceCardRegistry.switchToast,
      expressive: true,
      title: t.workspace.switchToast,
      icon: AppGlyphs.bell,
      isExpanded: widget.isExpanded,
      onToggle: widget.onToggle,
      onMoveUp: widget.onMoveUp,
      onMoveDown: widget.onMoveDown,
      onHide: widget.onHide,
      trailing: ExpressiveStatusPill(
        text: activeCount == 0
            ? t.workspace.closeAllTabs
            : t.workspace.activeSwitchCount(activeCount: activeCount),
        dot: false,
        compact: true,
        tone: activeCount > 0 ? ExpressiveTone.primary : ExpressiveTone.neutral,
      ),
      child: content,
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Glyph icon;
  final List<Widget> children;
  final Widget? trailing;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => ExpressiveSection(
    title: title,
    icon: icon,
    trailing: trailing,
    children: children,
  );
}

class _TemplateSection extends StatefulWidget {
  final int seed;
  final ExpressiveTone tone;
  final String title;
  final Glyph icon;
  final String titleLabel;
  final String titleValue;
  final String titlePlaceholder;
  final ValueChanged<String> onTitleCommit;
  final String descriptionLabel;
  final String descriptionValue;
  final String descriptionPlaceholder;
  final ValueChanged<String> onDescriptionCommit;
  final List<(String, String, Glyph)> variables;
  final Widget? footer;

  const _TemplateSection({
    required this.seed,
    required this.tone,
    required this.title,
    required this.icon,
    required this.titleLabel,
    required this.titleValue,
    required this.titlePlaceholder,
    required this.onTitleCommit,
    required this.descriptionLabel,
    required this.descriptionValue,
    required this.descriptionPlaceholder,
    required this.onDescriptionCommit,
    required this.variables,
    this.footer,
  });

  @override
  State<_TemplateSection> createState() => _TemplateSectionState();
}

class _TemplateSectionState extends State<_TemplateSection> {
  final GlobalKey<_DraftFieldState> _titleKey = GlobalKey<_DraftFieldState>();
  final GlobalKey<_DraftFieldState> _descKey = GlobalKey<_DraftFieldState>();

  /// 0 = 标题模板，1 = 描述模板。点击下方变量胶囊会直接插入到该目标输入框。
  int _activeTarget = 0;

  void _insertVariable(String token) {
    HapticFeedback.lightImpact();
    final target = _activeTarget == 0
        ? _titleKey.currentState
        : _descKey.currentState;
    target?.insertText(token);
  }

  @override
  Widget build(BuildContext context) {
    final targetName = _activeTarget == 0
        ? widget.titleLabel
        : widget.descriptionLabel;

    final titleField = _DraftField(
      key: _titleKey,
      label: widget.titleLabel,
      icon: AppGlyphs.textShort,
      value: widget.titleValue,
      placeholder: widget.titlePlaceholder,
      isTarget: _activeTarget == 0,
      onFocused: () {
        if (_activeTarget != 0) setState(() => _activeTarget = 0);
      },
      onCommit: widget.onTitleCommit,
    );

    final descField = _DraftField(
      key: _descKey,
      label: widget.descriptionLabel,
      icon: AppGlyphs.subtitles,
      value: widget.descriptionValue,
      placeholder: widget.descriptionPlaceholder,
      isTarget: _activeTarget == 1,
      onFocused: () {
        if (_activeTarget != 1) setState(() => _activeTarget = 1);
      },
      onCommit: widget.onDescriptionCommit,
    );

    return _Section(
      title: widget.title,
      icon: widget.icon,
      trailing: GestureDetector(
        onTap: () => setState(() => _activeTarget = 1 - _activeTarget),
        child: ExpressiveStatusPill(
          text: t.workspace.insertTarget(name: targetName),
          icon: AppGlyphs.edit,
          dot: false,
          compact: true,
          tone: widget.tone,
        ),
      ),
      children: [
        ExpressivePatchBackdrop(
          seed: widget.seed,
          tone: ExpressiveTone.sunken,
          active: true,
          intensity: 0.9,
          borderRadius: expressiveCornerMd,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 460) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: titleField),
                        const SizedBox(width: 10),
                        Expanded(child: descField),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titleField,
                      const SizedBox(height: 8),
                      descField,
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (index, (variable, description, glyph))
                      in widget.variables.indexed)
                    _VariableCapsule(
                      variable: variable,
                      description: description,
                      icon: glyph,
                      tone: const [
                        ExpressiveTone.primary,
                        ExpressiveTone.secondary,
                        ExpressiveTone.tertiary,
                      ][index % 3],
                      onTap: () => _insertVariable(variable),
                    ),
                ],
              ),
              if (widget.footer != null) ...[
                const SizedBox(height: 8),
                widget.footer!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 失焦提交、`Esc` 回滚的单行草稿输入，支持从外部胶囊直接插入变量。
class _DraftField extends StatefulWidget {
  final String label;
  final Glyph icon;
  final String value;
  final String placeholder;
  final bool isTarget;
  final VoidCallback? onFocused;
  final ValueChanged<String> onCommit;

  const _DraftField({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.placeholder,
    required this.onCommit,
    this.isTarget = false,
    this.onFocused,
  });

  @override
  State<_DraftField> createState() => _DraftFieldState();
}

class _DraftFieldState extends State<_DraftField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focusNode = FocusNode()..addListener(_handleFocus);

  void _handleFocus() {
    if (_focusNode.hasFocus) {
      widget.onFocused?.call();
    }
  }

  @override
  void didUpdateWidget(covariant _DraftField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        !_focusNode.hasFocus &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocus);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 在当前光标位置（或末尾）直接插入变量并立即写回设置。
  void insertText(String token) {
    final text = _controller.text;
    final selection = _controller.selection;
    final int start;
    final int end;
    if (selection.isValid &&
        selection.start >= 0 &&
        selection.end <= text.length) {
      start = selection.start;
      end = selection.end;
    } else {
      start = text.length;
      end = text.length;
    }
    final next = text.replaceRange(start, end, token);
    final cursor = start + token.length;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor),
    );
    widget.onCommit(next);
  }

  /// 整段替换为预设文案并立即提交。
  void replaceText(String next) {
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    widget.onCommit(next);
  }

  void _commit() {
    final next = _controller.text;
    if (next != widget.value) widget.onCommit(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GlyphIcon(
              widget.icon,
              size: 13,
              color: widget.isTarget ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: widget.isTarget
                      ? FontWeight.w700
                      : FontWeight.w600,
                  color: widget.isTarget
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Focus(
          canRequestFocus: false,
          // 子级 TextField 处理不了的键（Esc）才冒泡到这里；不吞其它按键。
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _controller.text = widget.value;
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onTap: widget.onFocused,
            style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: .55),
              hintText: widget.placeholder,
              hintStyle: TextStyle(
                fontSize: 10.5,
                color: scheme.onSurfaceVariant.withValues(alpha: .75),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: widget.isTarget
                      ? scheme.primary.withValues(alpha: .65)
                      : scheme.outlineVariant.withValues(alpha: .45),
                  width: widget.isTarget ? 1.3 : 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: scheme.primary, width: 1.6),
              ),
            ),
            onSubmitted: (_) => _commit(),
            onTapOutside: (_) => _commit(),
          ),
        ),
      ],
    );
  }
}

/// 可点击直接插入的 **M3E 有机几何变量胶囊**。
///
/// 每个变量都有种子生成的 [ExpressiveBlobBorder] 不规则圆角轮廓 + 多态图标徽章，
/// 彻底替掉原先干巴巴的纯文本表格。
class _VariableCapsule extends StatelessWidget {
  final String variable;
  final String description;
  final Glyph icon;
  final ExpressiveTone tone;
  final VoidCallback onTap;

  const _VariableCapsule({
    required this.variable,
    required this.description,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = expressiveToneColors(scheme, tone);
    final seed = expressiveBlobSeed(variable);
    final animate =
        !eInkInstantRoutes && !MediaQuery.disableAnimationsOf(context);

    return ActionBubbleTarget(
      enabled: !eInkInstantRoutes,
      corner: 16,
      child: ElasticPress(
        enabled: animate,
        child: Material(
          color: tones.container.withValues(alpha: .78),
          shape: ExpressiveBlobBorder(
            seed: seed,
            progress: 0.25,
            safeInset: 8,
            side: BorderSide(
              color: tones.onContainer.withValues(alpha: .22),
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExpressiveShapeBadge(
                    icon: icon,
                    seed: seed,
                    size: 22,
                    glyphSize: 12,
                    tone: tone,
                    active: true,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          variable,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: tones.onContainer,
                          ),
                        ),
                        Text(
                          description,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9.5,
                            color: tones.onContainer.withValues(alpha: .82),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  GlyphIcon(
                    AppGlyphs.add,
                    size: 12,
                    color: tones.onContainer.withValues(alpha: .85),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
