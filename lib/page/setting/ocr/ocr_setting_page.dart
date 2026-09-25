import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/service/ocr/ocr_model_downloader.dart';
import 'package:zephyr/service/ocr/ocr_models.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_cache.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

/// 漫画翻译（成品页）的设置页：翻译端点、推理后端、权重下载、成品页缓存。
///
/// 权重与端点放同一页：缺任何一个都出不了成品页，分两处摆会让人以为「已经配好了」。
@RoutePage()
class OcrSettingPage extends StatefulWidget {
  const OcrSettingPage({super.key});

  @override
  State<OcrSettingPage> createState() => _OcrSettingPageState();
}

class _OcrSettingPageState extends State<OcrSettingPage> {
  bool _loading = true;
  OcrTranslationConfig _draft = const OcrTranslationConfig(
    baseUrl: '',
    model: '',
  );
  bool _configured = false;
  String _ep = OcrSettings.defaultEp;
  List<String> _missing = const [];
  int _readyCount = 0;
  int _cacheCount = 0;
  bool _downloading = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    OcrSettings.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    OcrSettings.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      OcrSettings.loadDraft(),
      OcrSettings.loadConfig(),
      OcrSettings.loadEp(),
      OcrModels.status(),
      TranslatedPageCache.pageCount(),
    ]);
    if (!mounted) return;
    final status = results[3] as (List<String>, List<String>);
    setState(() {
      _draft = results[0] as OcrTranslationConfig;
      _configured = results[1] != null;
      _ep = results[2] as String;
      _readyCount = status.$1.length;
      _missing = status.$2;
      _cacheCount = results[4] as int;
      _loading = false;
    });
  }

  Future<void> _save(OcrTranslationConfig next) async {
    await OcrSettings.saveConfig(next);
    if (!mounted) return;
    showSuccessToast(t.ocr.saved);
  }

  /// 一行一个字段：点开弹窗改，改完立刻落盘。交互与代理地址同形
  /// （`setting/global/widgets.dart:91`），不再造第二种。
  Future<void> _edit({
    required String label,
    required String hint,
    required String value,
    String? subtitle,
    bool multiline = false,
    bool obscure = false,
    required void Function(String result) apply,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        var input = value;
        return AlertDialog(
          title: Text(label),
          content: SizedBox(
            width: 420,
            child: TextFormField(
              initialValue: value,
              autofocus: true,
              maxLines: multiline ? 6 : 1,
              obscureText: obscure,
              decoration: InputDecoration(
                hintText: hint,
                helperText: subtitle,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => input = multiline ? v : v.trim(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.common.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, input),
              child: Text(t.common.ok),
            ),
          ],
        );
      },
    );
    if (result == null || result == value) return;
    apply(result);
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    try {
      await OcrModelDownloader.ensure(
        onProgress: (received, total, file) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = received / total);
        },
      );
      if (mounted) showSuccessToast(t.ocr.downloadDone);
    } catch (e, s) {
      logger.e('OCR 权重下载失败', error: e, stackTrace: s);
      if (mounted) showErrorToast('${t.ocr.downloadFailed}: $e');
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
        await _load();
      }
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.ocr.clearCache),
        content: Text(t.ocr.clearCacheSubtitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.common.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await TranslatedPageCache.clearAll();
    if (!mounted) return;
    showSuccessToast(t.ocr.cacheCleared);
    await _load();
  }

  /// 术语表不整段铺开：只显示第一条，多了省略 —— 这行的高度是固定的。
  String get _glossarySummary {
    final first = _draft.glossary
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return first.isEmpty ? '-' : first;
  }

  @override
  Widget build(BuildContext context) {
    return SettingPageShell(
      title: t.ocr.title,
      child: _loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : ListView(
              children: [
                settingSectionTitle(context, t.ocr.endpointSection),
                if (!_configured)
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(t.ocr.notConfigured),
                  ),
                _tile(
                  icon: Icons.link_outlined,
                  label: t.ocr.baseUrl,
                  value: _draft.baseUrl.isEmpty
                      ? t.ocr.baseUrlNone
                      : _draft.baseUrl,
                  onTap: () => _edit(
                    label: t.ocr.baseUrl,
                    hint: t.ocr.baseUrlHint,
                    value: _draft.baseUrl,
                    apply: (v) => _save(_draft.copyWith(baseUrl: v)),
                  ),
                ),
                _tile(
                  icon: Icons.model_training_outlined,
                  label: t.ocr.model,
                  value: _draft.model.isEmpty ? '-' : _draft.model,
                  onTap: () => _edit(
                    label: t.ocr.model,
                    hint: t.ocr.modelHint,
                    value: _draft.model,
                    apply: (v) => _save(_draft.copyWith(model: v)),
                  ),
                ),
                _tile(
                  icon: Icons.key_outlined,
                  label: t.ocr.apiKey,
                  value: _draft.apiKey.isEmpty ? '-' : '••••••',
                  subtitle: t.ocr.apiKeySubtitle,
                  onTap: () => _edit(
                    label: t.ocr.apiKey,
                    hint: 'sk-...',
                    value: _draft.apiKey,
                    subtitle: t.ocr.apiKeySubtitle,
                    obscure: true,
                    apply: (v) => _save(_draft.copyWith(apiKey: v)),
                  ),
                ),
                _tile(
                  icon: Icons.translate_outlined,
                  label: t.ocr.targetLanguage,
                  value: _draft.targetLanguage,
                  onTap: () => _edit(
                    label: t.ocr.targetLanguage,
                    hint: 'zh-Hans / en / ja',
                    value: _draft.targetLanguage,
                    apply: (v) => _save(_draft.copyWith(targetLanguage: v)),
                  ),
                ),
                _tile(
                  icon: Icons.book_outlined,
                  label: t.ocr.glossary,
                  value: _glossarySummary,
                  subtitle: t.ocr.glossarySubtitle,
                  onTap: () => _edit(
                    label: t.ocr.glossary,
                    hint: t.ocr.glossaryHint,
                    value: _draft.glossary,
                    subtitle: t.ocr.glossarySubtitle,
                    multiline: true,
                    apply: (v) => _save(_draft.copyWith(glossary: v)),
                  ),
                ),

                const SizedBox(height: 8),
                const Divider(height: 1, thickness: 0.3),
                settingSectionTitle(context, t.ocr.epSection),
                ListTile(
                  leading: const Icon(Icons.memory_outlined),
                  title: Text(t.ocr.ep),
                  subtitle: Text(t.ocr.epSubtitle),
                  trailing: FluentDropdown<String>(
                    value: _ep,
                    displayValue: _epLabel(_ep),
                    items: {for (final c in OcrSettings.epChoices) c.$1: c.$2},
                    onChanged: (ep) async {
                      await OcrSettings.saveEp(ep);
                      if (mounted) await _load();
                    },
                  ),
                ),

                const SizedBox(height: 8),
                const Divider(height: 1, thickness: 0.3),
                settingSectionTitle(context, t.ocr.modelSection),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: Text(
                    _missing.isEmpty
                        ? t.ocr.weightsReady(count: _readyCount)
                        : t.ocr.weightsMissing(missing: _missing.join('、')),
                  ),
                  subtitle: _downloading
                      ? LinearProgressIndicator(value: _progress)
                      : null,
                  trailing: TextButton(
                    onPressed: _downloading ? null : _download,
                    child: Text(
                      _downloading ? t.ocr.downloading : t.ocr.download,
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                const Divider(height: 1, thickness: 0.3),
                settingSectionTitle(context, t.ocr.cacheSection),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: Text(t.ocr.clearCache),
                  subtitle: Text(
                    _cacheCount == 0
                        ? t.ocr.cacheEmpty
                        : '${t.ocr.cacheCount(count: _cacheCount)}；${t.ocr.clearCacheSubtitle}',
                  ),
                  trailing: TextButton(
                    onPressed: _cacheCount == 0 ? null : _clearCache,
                    child: Text(t.common.delete),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.touch_app_outlined),
                  title: Text(t.ocr.readerHint),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  String _epLabel(String ep) => OcrSettings.epChoices
      .firstWhere((c) => c.$1 == ep, orElse: () => OcrSettings.epChoices.first)
      .$2;

  Widget _tile({
    required IconData icon,
    required String label,
    required String value,
    String? subtitle,
    VoidCallback? onTap,
  }) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    subtitle: Text(
      subtitle == null ? value : '$value\n$subtitle',
      maxLines: subtitle == null ? 1 : 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
