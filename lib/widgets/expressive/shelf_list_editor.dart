import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

/// 书签列表与文件夹共用的轻量表单；输入无效时留在弹层内解释原因。
class ShelfListEditor extends StatefulWidget {
  const ShelfListEditor({
    super.key,
    required this.title,
    required this.label,
    required this.description,
    required this.onSave,
    this.initialName = '',
    this.onDelete,
  });
  final String title;
  final String label;
  final String description;
  final String initialName;
  final ValueChanged<String> onSave;
  final VoidCallback? onDelete;

  @override
  State<ShelfListEditor> createState() => _ShelfListEditorState();
}

class _ShelfListEditorState extends State<ShelfListEditor> {
  late final _controller = TextEditingController(text: widget.initialName);
  final _formKey = GlobalKey<FormState>();

  void _save() {
    if (_formKey.currentState!.validate()) {
      widget.onSave(_controller.text.trim());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopupPanel(
      scrollable: true,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(
              color: scheme.tertiaryContainer,
              shape: AppShape.all(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GlyphIcon(
                AppGlyphs.folderPlus,
                size: 24,
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: widget.label,
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: scheme.primary, width: 2),
                ),
                errorMaxLines: 2,
              ),
              validator: (value) {
                final name = value?.trim() ?? '';
                if (name.isEmpty) return t.common.pleaseEnterName;
                if (name.contains('/') || name.contains('\\')) {
                  return t.common.nameNoSlash;
                }
                return null;
              },
              onFieldSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.onDelete != null)
          ElasticButton(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: scheme.error,
                shape: AppShape.all(14),
                minimumSize: const Size(0, 48),
              ),
              onPressed: widget.onDelete,
              icon: const GlyphIcon(AppGlyphs.delete, size: 20),
              label: Text(t.common.deleteListLabel),
            ),
          ),
        ElasticButton(
          child: TextButton(
            style: TextButton.styleFrom(
              shape: AppShape.all(14),
              minimumSize: const Size(0, 48),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.common.cancel),
          ),
        ),
        ElasticButton(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              shape: AppShape.all(14),
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            onPressed: _save,
            icon: const GlyphIcon(AppGlyphs.check, size: 20),
            label: Text(t.common.save),
          ),
        ),
      ],
    );
  }
}
