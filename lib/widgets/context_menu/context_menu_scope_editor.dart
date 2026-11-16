/// 单个菜单的编辑器：四段拖拽（顶部 / 列表 / 更多 / 底部）+ 隐藏池。
///
/// 与导航栏那份自定义弹窗（`navigation_customization_dialog.dart`）同一套手法：
/// `CustomScrollView` + `SliverReorderableList`，`onReorderItem` 的 newIndex
/// 已经是「摘掉之后」的位置，不再手动 `-1`；拖拽代理自己包一层 `Material`，
/// 否则行里的 `ListTile` 在 Overlay 里会抛「No Material widget found」。
///
/// 每次改动**立即写全局设置**（与导航弹窗「无需再点保存」一致）：`_persistAndEmit`
/// 在状态相等时直接 return，所以点来点去不会反复写库。
library;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/model/context_menu/context_menu.dart';
import 'package:zephyr/widgets/common_popup.dart';

class ContextMenuScopeEditor extends StatelessWidget {
  const ContextMenuScopeEditor({
    super.key,
    required this.definition,
    required this.labelOf,
    this.glyphOf,
  });

  final ContextMenuDefinition definition;

  /// 这一项叫什么（设置界面用；真实菜单的文案可能随条目状态变）。
  final String Function(ContextMenuEntryDefinition entry) labelOf;

  /// 这一项画什么图标。有就给行首画出来，便于在编辑态里认出是哪一项。
  final Glyph? Function(ContextMenuEntryDefinition entry)? glyphOf;

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final layout = cubit.state.contextMenuSetting.scopes[definition.scope];
    final plan = resolveContextMenu(definition: definition, layout: layout);
    final materialized = materializeContextMenuLayout(definition, layout);

    final topEntries = <ContextMenuPlannedEntry>[
      ...plan.topStrip,
      ...plan.topRows,
    ];
    final placed = <String>{
      for (final entry in <ContextMenuPlannedEntry>[
        ...topEntries,
        ...plan.list,
        ...plan.collapsed,
        ...plan.bottomStrip,
        ...plan.bottomRows,
      ])
        entry.entry.id,
    };
    final hiddenIds = <String>[
      for (final id in materialized.order)
        if (!placed.contains(id)) id,
    ];

    return CustomScrollView(
      // 卡片按内容长高（短菜单不撑成一大块），超过上限才在内部滚动。
      shrinkWrap: true,
      slivers: <Widget>[
        _sectionHeader(context, t.contextMenu.topSection),
        _reorderableSection(
          context,
          topEntries,
          ContextMenuBucket.top,
          empty: t.contextMenu.pinNone,
        ),
        _sectionHeader(context, t.contextMenu.listSection),
        _reorderableSection(context, plan.list, ContextMenuBucket.list),
        _sectionHeader(context, t.contextMenu.collapsedSection),
        _reorderableSection(
          context,
          plan.collapsed,
          ContextMenuBucket.collapsed,
          empty: t.contextMenu.emptyHidden,
        ),
        _sectionHeader(context, t.contextMenu.bottomSection),
        _reorderableSection(
          context,
          <ContextMenuPlannedEntry>[...plan.bottomStrip, ...plan.bottomRows],
          ContextMenuBucket.bottom,
          empty: t.contextMenu.pinNone,
        ),
        _sectionHeader(context, t.contextMenu.hiddenSection),
        if (hiddenIds.isEmpty)
          _emptyRow(context, t.contextMenu.emptyHidden)
        else
          SliverList.builder(
            itemCount: hiddenIds.length,
            itemBuilder: (context, index) {
              final entry = definition.entryById(hiddenIds[index]);
              if (entry == null) return const SizedBox.shrink();
              return _row(
                context,
                entry: entry,
                visibility: ContextMenuVisibility.hidden,
                pin: ContextMenuPin.none,
                iconOnly: false,
              );
            },
          ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _emptyRow(BuildContext context, String text) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _reorderableSection(
    BuildContext context,
    List<ContextMenuPlannedEntry> entries,
    ContextMenuBucket bucket, {
    String? empty,
  }) {
    if (entries.isEmpty && empty != null) {
      return _emptyRow(context, empty);
    }
    return SliverReorderableList(
      itemCount: entries.length,
      onReorderItem: (oldIndex, newIndex) =>
          _reorder(context, bucket, oldIndex, newIndex),
      proxyDecorator: _dragProxyDecorator,
      itemBuilder: (context, index) {
        final planned = entries[index];
        return _row(
          context,
          key: ValueKey(
            '${definition.scope}/${bucket.name}/${planned.entry.id}',
          ),
          entry: planned.entry,
          visibility: planned.visibility,
          pin: planned.pin,
          iconOnly: planned.iconOnly,
          index: index,
          bucket: bucket,
          count: entries.length,
        );
      },
    );
  }

  static Widget _dragProxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final scheme = Theme.of(context).colorScheme;
        final value = Curves.easeInOut.transform(animation.value);
        return Material(
          elevation: value * 6,
          shadowColor: scheme.shadow,
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          child: child,
        );
      },
    );
  }

  Widget _row(
    BuildContext context, {
    Key? key,
    required ContextMenuEntryDefinition entry,
    required ContextMenuVisibility visibility,
    required ContextMenuPin pin,
    required bool iconOnly,
    int? index,
    ContextMenuBucket? bucket,
    int? count,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final hidden = visibility == ContextMenuVisibility.hidden;
    final glyph = glyphOf?.call(entry);

    final content = Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        leading: glyph == null ? null : GlyphIcon(glyph, size: 20),
        title: Text(
          labelOf(entry),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _stateLabel(visibility, pin, iconOnly),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hidden)
              IconButton(
                tooltip: t.contextMenu.restore,
                visualDensity: VisualDensity.compact,
                onPressed: () => _setVisibility(
                  context,
                  entry.id,
                  ContextMenuVisibility.normal,
                ),
                icon: const GlyphIcon(AppGlyphs.eye, size: 18),
              ),
            if (entry.persistent)
              _optionsMenu(
                context,
                entry,
                visibility,
                pin,
                iconOnly,
                index: index,
                bucket: bucket,
                count: count,
              ),
            if (index != null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: GlyphIcon(AppGlyphs.dragHandle, size: 18),
              ),
          ],
        ),
      ),
    );

    if (index == null) {
      return KeyedSubtree(
        key: key ?? ValueKey('hidden/${entry.id}'),
        child: content,
      );
    }

    // 整行都能拖，不再只认那颗小手柄：手柄仍画着当提示，但
    // `ImmediateMultiDragGestureRecognizer` 在指针没位移时不会吃掉点击，
    // 所以行里的「⋯」按钮照常可用。
    return ReorderableDragStartListener(
      key: key ?? ValueKey('${definition.scope}/${entry.id}'),
      index: index,
      child: content,
    );
  }

  Widget _optionsMenu(
    BuildContext context,
    ContextMenuEntryDefinition entry,
    ContextMenuVisibility visibility,
    ContextMenuPin pin,
    bool iconOnly, {
    int? index,
    ContextMenuBucket? bucket,
    int? count,
  }) {
    final capabilities = entry.capabilities;
    final canMoveUp = index != null && bucket != null && index > 0;
    final canMoveDown =
        index != null && bucket != null && count != null && index < count - 1;
    return CommonPopupBox<void>(
      targetBuilder: (open) => IconButton(
        tooltip: t.common.edit,
        visualDensity: VisualDensity.compact,
        onPressed: open,
        icon: const GlyphIcon(AppGlyphs.more, size: 18),
      ),
      popupBuilder: (_) => CommonPopupMenu(
        items: <CommonPopupMenuItem>[
          CommonPopupMenuItem(
            label: t.contextMenu.normal,
            glyph: AppGlyphs.eye,
            checked: visibility == ContextMenuVisibility.normal,
            onPressed: () =>
                _setVisibility(context, entry.id, ContextMenuVisibility.normal),
          ),
          CommonPopupMenuItem(
            label: t.contextMenu.collapsed,
            glyph: AppGlyphs.fold,
            checked: visibility == ContextMenuVisibility.collapsed,
            onPressed: capabilities.canCollapse
                ? () => _setVisibility(
                    context,
                    entry.id,
                    ContextMenuVisibility.collapsed,
                  )
                : null,
          ),
          CommonPopupMenuItem(
            label: t.contextMenu.hidden,
            glyph: AppGlyphs.eyeOff,
            checked: visibility == ContextMenuVisibility.hidden,
            onPressed: capabilities.canHide
                ? () => _setVisibility(
                    context,
                    entry.id,
                    ContextMenuVisibility.hidden,
                  )
                : null,
          ),
          const CommonPopupMenuItem.divider(),
          CommonPopupMenuItem(
            label: t.contextMenu.pinTop,
            glyph: AppGlyphs.vAlignTop,
            checked: pin == ContextMenuPin.top,
            onPressed: capabilities.canPin
                ? () => _setPin(context, entry.id, ContextMenuPin.top)
                : null,
          ),
          CommonPopupMenuItem(
            label: t.contextMenu.pinBottom,
            glyph: AppGlyphs.vAlignBottom,
            checked: pin == ContextMenuPin.bottom,
            onPressed: capabilities.canPin
                ? () => _setPin(context, entry.id, ContextMenuPin.bottom)
                : null,
          ),
          CommonPopupMenuItem(
            label: t.contextMenu.pinNone,
            glyph: AppGlyphs.unfold,
            checked: pin == ContextMenuPin.none,
            onPressed: capabilities.canPin
                ? () => _setPin(context, entry.id, ContextMenuPin.none)
                : null,
          ),
          if (pin != ContextMenuPin.none) ...[
            const CommonPopupMenuItem.divider(),
            CommonPopupMenuItem(
              label: t.contextMenu.iconOnly,
              glyph: AppGlyphs.checkBox,
              checked: iconOnly,
              onPressed: capabilities.canIconOnly
                  ? () => _setIconOnly(context, entry.id, !iconOnly)
                  : null,
            ),
          ],
          // 拖拽之外的兜底：两端就灰掉。鼠标拖不顺手（或触控板点不准）时
          // 这两个仍然能把顺序调好。
          if (index != null && bucket != null) ...[
            const CommonPopupMenuItem.divider(),
            CommonPopupMenuItem(
              label: t.contextMenu.moveUp,
              glyph: AppGlyphs.arrowUp,
              onPressed: canMoveUp
                  ? () => _reorder(context, bucket, index, index - 1)
                  : null,
            ),
            CommonPopupMenuItem(
              label: t.contextMenu.moveDown,
              glyph: AppGlyphs.arrowDown,
              onPressed: canMoveDown
                  ? () => _reorder(context, bucket, index, index + 1)
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  String _stateLabel(
    ContextMenuVisibility visibility,
    ContextMenuPin pin,
    bool iconOnly,
  ) {
    if (visibility == ContextMenuVisibility.hidden) return t.contextMenu.hidden;
    if (pin == ContextMenuPin.top) {
      return iconOnly
          ? '${t.contextMenu.pinTop} · ${t.contextMenu.iconOnly}'
          : t.contextMenu.pinTop;
    }
    if (pin == ContextMenuPin.bottom) {
      return iconOnly
          ? '${t.contextMenu.pinBottom} · ${t.contextMenu.iconOnly}'
          : t.contextMenu.pinBottom;
    }
    if (visibility == ContextMenuVisibility.collapsed) {
      return t.contextMenu.collapsed;
    }
    return t.contextMenu.normal;
  }

  void _update(
    BuildContext context,
    ContextMenuScopeLayout Function(ContextMenuScopeLayout current) update,
  ) {
    final cubit = context.read<GlobalSettingCubit>();
    cubit.updateContextMenuSetting((settings) {
      final current =
          settings.scopes[definition.scope] ?? const ContextMenuScopeLayout();
      final next = update(current);
      final scopes = Map<String, ContextMenuScopeLayout>.of(settings.scopes);
      if (next.isPristine) {
        scopes.remove(definition.scope);
      } else {
        scopes[definition.scope] = next;
      }
      return settings.copyWith(scopes: scopes);
    });
  }

  void _setVisibility(
    BuildContext context,
    String id,
    ContextMenuVisibility value,
  ) => _update(
    context,
    (current) => setContextMenuVisibility(definition, current, id, value),
  );

  void _setPin(BuildContext context, String id, ContextMenuPin value) =>
      _update(
        context,
        (current) => setContextMenuPin(definition, current, id, value),
      );

  void _setIconOnly(BuildContext context, String id, bool value) => _update(
    context,
    (current) => setContextMenuIconOnly(definition, current, id, value),
  );

  void _reorder(
    BuildContext context,
    ContextMenuBucket bucket,
    int oldIndex,
    int newIndex,
  ) => _update(
    context,
    (current) => reorderContextMenuBucket(
      definition: definition,
      layout: current,
      bucket: bucket,
      oldIndex: oldIndex,
      newIndex: newIndex,
    ),
  );
}
