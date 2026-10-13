import 'package:auto_route/annotations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:zephyr/util/font/font_profile.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/search/search_history_field.dart';
import 'package:zephyr/widgets/search/search_history_store.dart';

@RoutePage()
class FontSettingPage extends StatefulWidget {
  const FontSettingPage({super.key});

  @override
  State<FontSettingPage> createState() => _FontSettingPageState();
}

class _FontSettingPageState extends State<FontSettingPage> {
  static const _weights = <int>[100, 200, 300, 400, 500, 600, 700, 800, 900];
  static final _sampleText = t.fontSetting.sampleText;

  bool _overridesExpanded = false;

  Future<void> _pickMode(String mode) async {
    await FontProfileController.instance.setMode(mode);
  }

  Future<void> _pickSystemFamily() async {
    final controller = FontProfileController.instance;
    final selected = await showPopupPanel<String>(
      presentation: PopupPresentation.relative,
      context: context,
      builder: (_) =>
          _SystemFamilyPickerDialog(initial: controller.systemFamily),
    );
    if (selected == null || selected == controller.systemFamily) return;
    await controller.setSystemFamily(selected);
    showSuccessToast(t.fontSetting.saved);
  }

  Future<void> _pickDefault() async {
    final file = await _pickFontFile();
    if (file == null) return;
    await _saveDefault(file.path);
  }

  Future<void> _saveDefault(String filePath) async {
    final ok = await FontProfileController.instance.setDefaultPath(filePath);
    if (!ok) {
      showErrorToast(t.fontSetting.loadFailed);
      return;
    }
    showSuccessToast(
      filePath.isEmpty ? t.fontSetting.cleared : t.fontSetting.saved,
    );
  }

  Future<void> _pickWeight(int weight) async {
    final file = await _pickFontFile();
    if (file == null) return;
    await _saveWeight(weight, file.path);
  }

  Future<void> _saveWeight(int weight, String filePath) async {
    final ok = await FontProfileController.instance.setOverridePath(
      weight,
      filePath,
    );
    if (!ok) {
      showErrorToast(t.fontSetting.loadFailed);
      return;
    }
    showSuccessToast(
      filePath.isEmpty ? t.fontSetting.cleared : t.fontSetting.saved,
    );
  }

  Future<XFile?> _pickFontFile() async {
    const typeGroup = XTypeGroup(
      label: 'font',
      extensions: ['ttf', 'otf', 'ttc'],
      uniformTypeIdentifiers: ['public.font'],
    );
    return openFile(acceptedTypeGroups: [typeGroup]);
  }

  Future<void> _clearAll() async {
    await FontProfileController.instance.clearAll();
    showSuccessToast(t.fontSetting.allCleared);
  }

  String _modeHint(String mode) {
    switch (mode) {
      case FontProfileController.modeFamily:
        return t.fontSetting.modeFamilyHint;
      case FontProfileController.modeFile:
        return t.fontSetting.modeFileHint;
      default:
        return t.fontSetting.modeSystemHint;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          t.fontSetting.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: t.fontSetting.clear,
            onPressed: _clearAll,
            icon: const GlyphIcon(AppGlyphs.reset),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: FontProfileController.instance,
        builder: (context, _) {
          final controller = FontProfileController.instance;
          // 有覆盖项时强制展开，避免用户以为设置丢了。
          final overridesExpanded =
              controller.hasOverrides || _overridesExpanded;
          final defaultPath = controller.defaultPath ?? '';
          final mode = controller.mode;
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(t.fontSetting.hint),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: FontProfileController.modeSystem,
                      label: Text(t.fontSetting.modeSystem),
                    ),
                    ButtonSegment(
                      value: FontProfileController.modeFamily,
                      label: Text(t.fontSetting.modeFamily),
                    ),
                    ButtonSegment(
                      value: FontProfileController.modeFile,
                      label: Text(t.fontSetting.modeFile),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) => _pickMode(selection.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _modeHint(mode),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (mode == FontProfileController.modeFamily)
                Builder(
                  builder: (context) {
                    final systemFamily = controller.systemFamily;
                    return ListTile(
                      leading: SizedBox(
                        width: 86,
                        child: Text(
                          t.fontSetting.modeFamily,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      title: Text(
                        systemFamily.isEmpty
                            ? t.fontSetting.familyPickPrompt
                            : systemFamily,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _sampleText,
                          style: controller.applyStyleForWeight(
                            const TextStyle(fontSize: 16),
                            400,
                          ),
                        ),
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          if (systemFamily.isNotEmpty)
                            IconButton(
                              tooltip: t.fontSetting.clearFile,
                              onPressed: () async {
                                await controller.setSystemFamily('');
                                showSuccessToast(t.fontSetting.cleared);
                              },
                              icon: const GlyphIcon(AppGlyphs.close),
                            ),
                          IconButton(
                            tooltip: t.fontSetting.familyPickPrompt,
                            onPressed: _pickSystemFamily,
                            icon: const GlyphIcon(AppGlyphs.layoutList),
                          ),
                        ],
                      ),
                      onTap: _pickSystemFamily,
                    );
                  },
                ),
              if (mode == FontProfileController.modeFile)
                _FontTile(
                  label: t.fontSetting.defaultFont,
                  description: null,
                  filePath: defaultPath,
                  sampleText: _sampleText,
                  previewStyle: controller.applyStyleForWeight(
                    const TextStyle(fontSize: 16),
                    400,
                  ),
                  onPick: _pickDefault,
                  onClear: defaultPath.isEmpty ? null : () => _saveDefault(''),
                ),
              const Divider(height: 24, indent: 16, endIndent: 16),
              ListTile(
                leading: SizedBox(
                  width: 86,
                  child: Text(
                    t.fontSetting.overrides,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                title: Text(
                  t.fontSetting.overridesHint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: GlyphIcon(
                  overridesExpanded
                      ? AppGlyphs.chevronUp
                      : AppGlyphs.chevronDown,
                ),
                onTap: () =>
                    setState(() => _overridesExpanded = !_overridesExpanded),
              ),
              if (overridesExpanded)
                ..._weights.map((weight) {
                  final filePath = controller.pathForWeight(weight) ?? '';
                  return _FontTile(
                    label: 'w$weight\n${fontWeightLabels[weight]!}',
                    description: null,
                    filePath: filePath,
                    sampleText: _sampleText,
                    previewStyle: controller.applyStyleForWeight(
                      TextStyle(
                        fontSize: 16,
                        fontWeight: _toFontWeight(weight),
                      ),
                      weight,
                    ),
                    onPick: () => _pickWeight(weight),
                    onClear: filePath.isEmpty
                        ? null
                        : () => _saveWeight(weight, ''),
                  );
                }),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  FontWeight _toFontWeight(int weight) {
    return FontWeight.values
            .where((value) => value.value == weight)
            .firstOrNull ??
        FontWeight.w400;
  }
}

class _FontTile extends StatelessWidget {
  const _FontTile({
    required this.label,
    required this.description,
    required this.filePath,
    required this.sampleText,
    required this.previewStyle,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final String? description;
  final String filePath;
  final String sampleText;
  final TextStyle? previewStyle;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: SizedBox(
        width: 86,
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(
        filePath.isEmpty
            ? t.fontSetting.noFileSelected
            : path.basename(filePath),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description != null && description!.isNotEmpty)
              Text(description!, style: theme.textTheme.bodySmall),
            if (filePath.isNotEmpty)
              Text(
                filePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            Text(sampleText, style: previewStyle),
          ],
        ),
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          if (onClear != null)
            IconButton(
              tooltip: t.fontSetting.clearFile,
              onPressed: onClear,
              icon: const GlyphIcon(AppGlyphs.close),
            ),
          IconButton(
            tooltip: t.fontSetting.selectFile,
            onPressed: onPick,
            icon: const GlyphIcon(AppGlyphs.folder),
          ),
        ],
      ),
    );
  }
}

/// 系统字体家族选择弹窗：枚举结果可搜索，找不到时可用输入的名称手动兜底。
class _SystemFamilyPickerDialog extends StatefulWidget {
  const _SystemFamilyPickerDialog({required this.initial});

  final String initial;

  @override
  State<_SystemFamilyPickerDialog> createState() =>
      _SystemFamilyPickerDialogState();
}

class _SystemFamilyPickerDialogState extends State<_SystemFamilyPickerDialog> {
  late final Future<List<String>> _familiesFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _familiesFuture = FontProfileController.instance.listSystemFontFamilies();
  }

  @override
  Widget build(BuildContext context) {
    return PopupPanel(
      title: Text(
        t.fontSetting.familyPickerTitle,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          children: [
            SearchHistoryField(
              history: SearchHistoryStore.local('font-family'),
              autofocus: true,
              decoration: InputDecoration(
                hintText: t.fontSetting.familySearchHint,
                prefixIcon: const GlyphIcon(AppGlyphs.search),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildList()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
      ],
    );
  }

  Widget _buildList() {
    return FutureBuilder<List<String>>(
      future: _familiesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(child: Text(t.fontSetting.familyLoading));
        }
        final families = snapshot.data ?? const <String>[];
        final query = _query.toLowerCase();
        final filtered = query.isEmpty
            ? families
            : families
                  .where((family) => family.toLowerCase().contains(query))
                  .toList(growable: false);
        final manualEntry = query.isNotEmpty;
        final showEmptyState = filtered.isEmpty && !manualEntry;
        return Column(
          children: [
            if (manualEntry)
              ListTile(
                dense: true,
                leading: const GlyphIcon(AppGlyphs.edit),
                title: Text(
                  t.fontSetting.familyManualUse(name: _query),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(context).pop(_query),
              ),
            Expanded(
              child: showEmptyState
                  ? Center(child: Text(t.fontSetting.familyEmpty))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final family = filtered[index];
                        final selected = family == widget.initial;
                        return ListTile(
                          dense: true,
                          title: Text(
                            family,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            t.fontSetting.sampleText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: family, fontSize: 12),
                          ),
                          trailing: selected
                              ? const GlyphIcon(AppGlyphs.check)
                              : null,
                          onTap: () => Navigator.of(context).pop(family),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
