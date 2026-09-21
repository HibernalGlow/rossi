import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, KeyDownEvent;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/widgets/toast.dart';

/// 「切换提示」卡片 —— neoview「控制」面板的 `SwitchToastCard` 的 Flutter 重建。
///
/// 上游卡片四节里的「提示悬浮窗」（X/Y 摆位、透明度、液态玻璃）**不在这里**：
/// Rossi 的提示条外观统一由「设置 → 提示样式」的九宫格负责，两处摆位会打架。
/// 保留的是这张卡的实质：**触发条件 + 两本模板 + 变量表 + 测试提示**。
///
/// 输入框沿用上游 `DraftTextarea` 的语义：失焦才提交、`Esc` 取消回滚，
/// 于是「正在编辑」不会被外部（同一设置页另一处）的重建打断。
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
  static const List<(String, String)> _bookVariables = [
    ('{{book.displayName}}', '书籍显示名'),
    ('{{book.currentPageDisplay}}', '当前页码'),
    ('{{book.totalPages}}', '总页数'),
    ('{{book.progressPercent}}', '阅读进度（%）'),
    ('{{book.path}}', '书籍路径（本地来源才有值）'),
  ];

  static const List<(String, String)> _pageVariables = [
    ('{{page.indexDisplay}}', '当前页码'),
    ('{{page.name}}', '页面文件名'),
    ('{{page.path}}', '页面路径'),
  ];

  @override
  Widget build(BuildContext context) {
    final setting = context
        .watch<GlobalSettingCubit>()
        .state
        .switchToastSetting;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '位置与外观在「设置 → 提示样式」里调整。',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            FilledButton.tonal(
              onPressed: () => showInfoToast(
                '这是一条切换提示的预览',
                title: '切换提示测试',
                context: context,
              ),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('显示测试提示', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _Section(
          title: '触发条件',
          icon: Icons.notifications_active_rounded,
          children: [
            _toggle(
              '切换书籍时显示提示',
              setting.enableBook,
              (v) => context
                  .read<GlobalSettingCubit>()
                  .updateSwitchToastSetting((c) => c.copyWith(enableBook: v)),
            ),
            _toggle(
              '切换页面时显示提示',
              setting.enablePage,
              (v) => context
                  .read<GlobalSettingCubit>()
                  .updateSwitchToastSetting((c) => c.copyWith(enablePage: v)),
            ),
          ],
        ),
        _TemplateSection(
          title: '书籍提示模板',
          icon: Icons.menu_book_rounded,
          titleLabel: '书籍标题模板',
          titleValue: setting.bookTitleTemplate,
          titlePlaceholder: '例如：已切换到 {{book.displayName}}',
          onTitleCommit: (v) =>
              context.read<GlobalSettingCubit>().updateSwitchToastSetting(
                (c) => c.copyWith(bookTitleTemplate: v),
              ),
          descriptionLabel: '书籍描述模板',
          descriptionValue: setting.bookDescriptionTemplate,
          descriptionPlaceholder: '例如：路径：{{book.path}}',
          onDescriptionCommit: (v) =>
              context.read<GlobalSettingCubit>().updateSwitchToastSetting(
                (c) => c.copyWith(bookDescriptionTemplate: v),
              ),
          variables: _bookVariables,
        ),
        _TemplateSection(
          title: '页面提示模板',
          icon: Icons.image_rounded,
          titleLabel: '页面标题模板',
          titleValue: setting.pageTitleTemplate,
          titlePlaceholder: '例如：第 {{page.indexDisplay}} 页',
          onTitleCommit: (v) =>
              context.read<GlobalSettingCubit>().updateSwitchToastSetting(
                (c) => c.copyWith(pageTitleTemplate: v),
              ),
          descriptionLabel: '页面描述模板',
          descriptionValue: setting.pageDescriptionTemplate,
          descriptionPlaceholder: '例如：{{page.name}}',
          onDescriptionCommit: (v) =>
              context.read<GlobalSettingCubit>().updateSwitchToastSetting(
                (c) => c.copyWith(pageDescriptionTemplate: v),
              ),
          variables: _pageVariables,
          footer: const Text(
            '页面模板同样可以使用 {{book.*}} 变量。',
            style: TextStyle(fontSize: 10),
          ),
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
      title: '切换提示',
      icon: Icons.notifications_active_rounded,
      isExpanded: widget.isExpanded,
      onToggle: widget.onToggle,
      onMoveUp: widget.onMoveUp,
      onMoveDown: widget.onMoveDown,
      onHide: widget.onHide,
      child: content,
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          ...children,
        ],
      ),
    );
  }
}

class _TemplateSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String titleLabel;
  final String titleValue;
  final String titlePlaceholder;
  final ValueChanged<String> onTitleCommit;
  final String descriptionLabel;
  final String descriptionValue;
  final String descriptionPlaceholder;
  final ValueChanged<String> onDescriptionCommit;
  final List<(String, String)> variables;
  final Widget? footer;

  const _TemplateSection({
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
  Widget build(BuildContext context) {
    return _Section(
      title: title,
      icon: icon,
      children: [
        _DraftField(
          // 外部值换了一本卡（重置布局）时重建控制器，避免残留上一本的草稿。
          key: ValueKey('title-$titleValue'),
          label: titleLabel,
          value: titleValue,
          placeholder: titlePlaceholder,
          onCommit: onTitleCommit,
        ),
        const SizedBox(height: 6),
        _DraftField(
          key: ValueKey('desc-$descriptionValue'),
          label: descriptionLabel,
          value: descriptionValue,
          placeholder: descriptionPlaceholder,
          onCommit: onDescriptionCommit,
        ),
        const SizedBox(height: 6),
        _VariableTable(variables: variables),
        if (footer != null) ...[const SizedBox(height: 4), footer!],
      ],
    );
  }
}

/// 失焦提交、`Esc` 回滚的单行草稿输入。
class _DraftField extends StatefulWidget {
  final String label;
  final String value;
  final String placeholder;
  final ValueChanged<String> onCommit;

  const _DraftField({
    super.key,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onCommit,
  });

  @override
  State<_DraftField> createState() => _DraftFieldState();
}

class _DraftFieldState extends State<_DraftField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final next = _controller.text;
    if (next != widget.value) widget.onCommit(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 10,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
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
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.placeholder,
              hintStyle: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
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

class _VariableTable extends StatelessWidget {
  final List<(String, String)> variables;

  const _VariableTable({required this.variables});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.4);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (variable, description) in variables)
            Row(
              children: [
                SizedBox(
                  width: 132,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: Text(
                      variable,
                      style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: Text(
                      description,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
