import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_list/service/plugin_list_navigation_controller.dart';
import 'package:zephyr/widgets/expressive/expressive_icon_button.dart';
import 'package:zephyr/widgets/popup_panel.dart';

/// 原筛选 FAB 的通用入口。只有这一小块观察页码，正文不跟随滚动重建。
class DiscoverBrowseMenu extends StatelessWidget {
  const DiscoverBrowseMenu({
    super.key,
    required this.navigation,
    required this.onPresentation,
    this.onFilter,
    this.hasFilters = false,
  });
  final PluginListNavigationController navigation;
  final VoidCallback? onFilter;
  final Future<void> Function(BuildContext) onPresentation;
  final bool hasFilters;

  String _pageLabel() => navigation.totalPages == null
      ? t.comicList.currentPage(page: navigation.currentPage)
      : t.comicList.pageOfTotal(
          page: navigation.currentPage,
          total: navigation.totalPages!,
        );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: navigation,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (navigation.attached)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: navigation.busy ? null : () => _jump(context),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        _pageLabel(),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Badge(
          isLabelVisible: hasFilters,
          child: ExpressiveIconButton(
            glyph: AppGlyphs.more,
            tooltip: t.comicList.browseMenu,
            size: 56,
            shape: ExpressiveButtonShape.cookie6Sided,
            onPressed: () {
              HapticFeedback.lightImpact();
              _open(context);
            },
          ),
        ),
      ],
    ),
  );

  Future<void> _open(BuildContext context) async {
    final action = await showPopupPanel<String>(
      context: context,
      presentation: PopupPresentation.relative,
      builder: (popupContext) => ListenableBuilder(
        listenable: navigation,
        builder: (_, _) => PopupPanel(
          title: Text(t.comicList.browseMenu),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (navigation.attached) ...[
                Text(
                  _pageLabel(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed:
                            navigation.busy || navigation.currentPage <= 1
                            ? null
                            : () => Navigator.of(popupContext).pop('previous'),
                        icon: const GlyphIcon(AppGlyphs.chevronBack),
                        label: Text(t.comicList.previousPage),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed:
                            navigation.busy ||
                                (navigation.totalPages != null &&
                                    navigation.currentPage >=
                                        navigation.totalPages!)
                            ? null
                            : () => Navigator.of(popupContext).pop('next'),
                        icon: const GlyphIcon(AppGlyphs.chevronForward),
                        label: Text(t.comicList.nextPage),
                      ),
                    ),
                  ],
                ),
                ListTile(
                  leading: const GlyphIcon(AppGlyphs.openBook),
                  title: Text(t.comicList.jumpToPage),
                  enabled: !navigation.busy,
                  onTap: () => Navigator.of(popupContext).pop('jump'),
                ),
                ListTile(
                  leading: const GlyphIcon(AppGlyphs.history),
                  title: Text(t.comicList.restorePosition),
                  subtitle: Text(
                    navigation.savedPage == null
                        ? t.comicList.noSavedPosition
                        : t.comicList.restorePage(page: navigation.savedPage!),
                  ),
                  enabled: navigation.canRestore,
                  onTap: () => Navigator.of(popupContext).pop('restore'),
                ),
                Text(
                  t.comicList.positionSavedAutomatically,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
              ],
              if (onFilter != null)
                ListTile(
                  leading: Badge(
                    isLabelVisible: hasFilters,
                    child: const GlyphIcon(AppGlyphs.sliders),
                  ),
                  title: Text(t.comicList.filter),
                  onTap: () => Navigator.of(popupContext).pop('filter'),
                ),
              ListTile(
                leading: const GlyphIcon(AppGlyphs.gradient),
                title: Text(t.workspace.displayWallSettings),
                onTap: () => Navigator.of(popupContext).pop('presentation'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'filter':
        onFilter?.call();
      case 'presentation':
        await onPresentation(context);
      case 'jump':
        await _jump(context);
      case 'restore':
        await navigation.restore();
      case 'previous':
        await navigation.jumpToPage(navigation.currentPage - 1);
      case 'next':
        await navigation.jumpToPage(navigation.currentPage + 1);
    }
  }

  Future<void> _jump(BuildContext context) async {
    final page = await showPopupPanel<int>(
      context: context,
      presentation: PopupPresentation.relative,
      builder: (_) => _JumpPagePanel(
        current: navigation.currentPage,
        total: navigation.totalPages,
      ),
    );
    if (page != null && context.mounted) await navigation.jumpToPage(page);
  }
}

class _JumpPagePanel extends StatefulWidget {
  const _JumpPagePanel({required this.current, required this.total});
  final int current;
  final int? total;
  @override
  State<_JumpPagePanel> createState() => _JumpPagePanelState();
}

class _JumpPagePanelState extends State<_JumpPagePanel> {
  late final _input = TextEditingController(text: widget.current.toString());
  final _form = GlobalKey<FormState>();
  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.of(context).pop(int.parse(_input.text));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopupPanel(
    title: Text(t.comicList.jumpToPage),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _input,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: t.comicList.pageInput),
        onFieldSubmitted: (_) => _submit(),
        validator: (text) {
          final page = int.tryParse(text ?? '');
          if (page == null || page < 1) return t.comicList.invalidPage;
          if (widget.total != null && page > widget.total!) {
            return t.comicList.pageOutOfRange(total: widget.total!);
          }
          return null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(t.common.cancel),
      ),
      FilledButton(onPressed: _submit, child: Text(t.comicList.jumpToPage)),
    ],
  );
}
