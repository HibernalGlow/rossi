import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';
import 'package:zephyr/page/setting/ocr/ocr_settings_body.dart';
import 'package:zephyr/service/ocr/ocr_log.dart';
import 'package:zephyr/service/ocr/ocr_model_downloader.dart';
import 'package:zephyr/service/ocr/ocr_models.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/service/ocr/ocr_translate_engine.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_cache.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/widgets/app_log_dialog.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';

/// 阅读时真会去拨的那几颗翻译开关，加一颗按页自动译 —— 面板与卡片共用的一份实现。
///
/// # 端点地址与 API Key 走 [onOpenFullSettings] 这一条缝
///
/// 那几样是「装机时填一次」的配置，而且是长文本与密钥。阅读设置面板里**不摆**，
/// 只给一条跳到完整设置页的出口（这就是 [onOpenFullSettings] 的用途）；
/// 工作台卡片没有「跳出去」这个动作可依赖 —— 它弹不掉任何路由，
/// 所以传 null 时改成就地展开 [OcrSettingsBody]，在卡片里直接调完。
///
/// # 这一节在移动端不出现
///
/// 见 `ocrSupportedHere`：Android / iOS 是 ADR-0018 §决定 6 的**排除项**，
/// 不是待办 —— 那两端的 `ort` 没注册加速器 EP，识别模型还是 fp32 的 441 MB。
class TranslateSettingsSection extends StatefulWidget {
  const TranslateSettingsSection({super.key, this.onOpenFullSettings});

  /// 非 null = 画一条「去完整设置页」的出口并调它；null = 就地展开完整设置。
  final VoidCallback? onOpenFullSettings;

  @override
  State<TranslateSettingsSection> createState() =>
      TranslateSettingsSectionState();
}

class TranslateSettingsSectionState extends State<TranslateSettingsSection> {
  bool _loading = true;
  bool _fullExpanded = false;
  OcrTranslationConfig _draft = const OcrTranslationConfig(
    baseUrl: '',
    model: '',
  );
  String _ep = OcrSettings.defaultEp;
  bool _autoTranslate = false;
  List<String> _readyWeights = const <String>[];
  List<String> _missingWeights = const <String>[];
  int _cacheCount = 0;
  double _progress = 0;
  bool _downloading = false;

  /// 目标语言常用档。存进来的值不在这里时也会被并进下拉 ——
  /// 否则用户填过的语言在列表里找不到，一改就等于悄悄换掉了。
  static const List<String> _commonTargetLanguages = <String>[
    'zh-Hans',
    'zh-Hant',
    'en',
    'ja',
    'ko',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // 完整设置页那边改了同一份配置，这一节得跟着变，别两处各说各话。
    OcrSettings.changes.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    OcrSettings.changes.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final draft = await OcrSettings.loadDraft();
      final ep = await OcrSettings.loadEp();
      final auto = await OcrSettings.loadAutoTranslatePage();
      final (ready, missing) = await OcrModels.status();
      final count = await TranslatedPageCache.pageCount();
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _ep = ep;
        _autoTranslate = auto;
        _readyWeights = ready;
        _missingWeights = missing;
        _cacheCount = count;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 改**一个**字段也要整份写回：[OcrSettings.saveConfig] 存的是整个配置对象，
  /// 只带改动那一项会把接口地址、模型名、Key、术语表一起清空。
  Future<void> _patch({
    String? targetLanguage,
    OcrTranslateEngine? engine,
  }) async {
    final next = _draft.copyWith(
      targetLanguage: targetLanguage ?? _draft.targetLanguage,
      engine: engine ?? _draft.engine,
    );
    setState(() => _draft = next);
    await OcrSettings.saveConfig(next);
  }

  Future<void> _setAutoTranslate(bool value) async {
    setState(() => _autoTranslate = value);
    await OcrSettings.saveAutoTranslatePage(value);
  }

  Future<void> _setEp(String value) async {
    setState(() => _ep = value);
    await OcrSettings.saveEp(value);
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    OcrLog.add(
      '阅读器设置里开始下载权重：'
      '${_missingWeights.isEmpty ? "（没有缺失项，直接过）" : "缺 ${_missingWeights.join('、')}"}',
    );
    try {
      await OcrModelDownloader.ensure(
        onProgress: (received, total, file) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = received / total);
        },
      );
      OcrLog.add('权重下载完成');
      if (mounted) showSuccessToast(t.ocr.downloadDone);
    } catch (e) {
      OcrLog.add('权重下载失败', error: e);
      if (mounted) showErrorToast('${t.ocr.downloadFailed}: $e');
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
        await _load();
      }
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showPopupPanel<bool>(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (context) => PopupPanel(
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

  String _engineLabel(OcrTranslateEngine engine) => OcrSettings.engineChoices
      .firstWhere(
        (c) => c.$1 == engine,
        orElse: () => (OcrSettings.defaultEngine, engine.id),
      )
      .$2;

  String _epLabel(String ep) => OcrSettings.epChoices
      .firstWhere((c) => c.$1 == ep, orElse: () => OcrSettings.epChoices.first)
      .$2;

  /// 出口那一行：面板里是「跳去完整设置页」，卡片里是「就地展开」。
  Widget _fullSettingsRow({required bool endpointMissing}) {
    final colorScheme = context.theme.colorScheme;
    final inline = widget.onOpenFullSettings == null;
    final expanded = inline && _fullExpanded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          leading: GlyphIcon(
            endpointMissing ? AppGlyphs.error : AppGlyphs.sliders,
            color: endpointMissing ? colorScheme.error : colorScheme.primary,
          ),
          title: Text(
            t.ocr.endpointSection,
            style: context.theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            endpointMissing
                ? '${t.ocr.notConfigured} · ${t.ocr.baseUrlHint}'
                : '${_draft.baseUrl.isEmpty ? t.ocr.baseUrlNone : _draft.baseUrl}\n'
                      '${_draft.model}',
            style: context.theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: GlyphIcon(
            inline
                ? (expanded
                      ? AppGlyphs.chevronUp
                      : AppGlyphs.chevronDown)
                : AppGlyphs.chevronForward,
          ),
          onTap: inline
              ? () => setState(() => _fullExpanded = !expanded)
              : widget.onOpenFullSettings,
        ),
        if (inline)
          SettingsAnimatedCollapse(
            showDivider: false,
            isExpanded: expanded,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: OcrSettingsBody(scrollable: false),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    // 端侧那档不要端点，所以「缺配置」只在需要端点的档上才成立。
    final endpointMissing =
        _draft.engine.requiresEndpoint &&
        (_draft.baseUrl.trim().isEmpty || _draft.model.trim().isEmpty);
    final weightReady = _missingWeights.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          title: t.ocr.title,
          icon: AppGlyphs.translate,
          children: [
            SettingsCardGroup(
              children: [
                // 翻到新的一页就自动出译文页。默认关：一页要十几秒，
                // 打开等于把「往后每一页都得等」变成默认状态。
                SettingsSwitchTile(
                  title: t.ocr.autoTranslatePage,
                  subtitle: t.ocr.autoTranslatePageSubtitle,
                  value: _autoTranslate,
                  onChanged: _setAutoTranslate,
                ),
                SettingsDropdownTile<OcrTranslateEngine>(
                  title: t.ocr.engine,
                  subtitle: t.ocr.engineSubtitle,
                  value: _draft.engine,
                  values: [
                    for (final choice in OcrSettings.engineChoices)
                      if (choice.$1.availableHere) choice.$1,
                  ],
                  labelOf: _engineLabel,
                  onChanged: (engine) => _patch(engine: engine),
                ),
                SettingsDropdownTile<String>(
                  title: t.ocr.targetLanguage,
                  value: _draft.targetLanguage,
                  values: <String>{
                    _draft.targetLanguage,
                    for (final code in _commonTargetLanguages) code,
                  }.toList(),
                  onChanged: (value) => _patch(targetLanguage: value),
                ),
                SettingsDropdownTile<String>(
                  title: t.ocr.ep,
                  subtitle: t.ocr.epSubtitle,
                  value: _ep,
                  values: [
                    for (final choice in OcrSettings.epChoices) choice.$1,
                  ],
                  labelOf: _epLabel,
                  onChanged: _setEp,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        SettingsSection(
          title: t.ocr.modelSection,
          icon: AppGlyphs.download,
          children: [
            SettingsCardGroup(
              children: [
                SettingsActionTile(
                  title: weightReady
                      ? t.ocr.weightsReady(count: _readyWeights.length)
                      : t.ocr.weightsMissing(
                          missing: _missingWeights.join('、'),
                        ),
                  subtitle: t.ocr.clearCacheSubtitle,
                  enabled: !_downloading,
                  trailing: _downloading
                      ? SizedBox(
                          width: 96,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: _progress <= 0 ? null : _progress,
                              minHeight: 4,
                            ),
                          ),
                        )
                      : TextButton(
                          onPressed: _download,
                          child: Text(t.ocr.download),
                        ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        SettingsSection(
          title: t.ocr.cacheSection,
          icon: AppGlyphs.box,
          children: [
            SettingsCardGroup(
              children: [
                SettingsActionTile(
                  title: _cacheCount > 0
                      ? t.ocr.cacheCount(count: _cacheCount)
                      : t.ocr.cacheEmpty,
                  subtitle: t.ocr.clearCacheSubtitle,
                  enabled: _cacheCount > 0,
                  trailing: TextButton(
                    onPressed: _cacheCount > 0 ? _clearCache : null,
                    child: Text(t.ocr.clearCache),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        SettingsSection(
          title: t.ocr.logSection,
          icon: AppGlyphs.article,
          children: [
            SettingsCardGroup(
              children: [
                SettingsActionTile(
                  title: t.ocr.viewLog,
                  subtitle: t.ocr.logHint,
                  trailing: TextButton(
                    onPressed: () => showAppLogDialog(
                      context,
                      log: OcrLog.log,
                      title: t.ocr.logDialogTitle,
                      emptyText: t.ocr.logEmpty,
                      copyLabel: t.ocr.copyLog,
                      copiedToast: t.ocr.logCopied,
                      openLabel: t.ocr.openLogLocation,
                      closeLabel: t.common.close,
                    ),
                    child: Text(t.ocr.viewLog),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        _fullSettingsRow(endpointMissing: endpointMissing),
      ],
    );
  }
}
