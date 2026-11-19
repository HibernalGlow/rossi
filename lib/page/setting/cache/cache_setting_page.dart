import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/util/manage_cache.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';

const Map<int, String> _cacheLimitLabels = {
  536870912: '512 MB',
  1073741824: '1 GB',
  2147483648: '2 GB',
  4294967296: '4 GB',
  8589934592: '8 GB',
  17179869184: '16 GB',
};

final List<int> _cacheLimitOptions = _cacheLimitLabels.keys.toList()..sort();

const List<int> _readerImageSizeOptions = [
  536870912,
  1073741824,
  2147483648,
  4294967296,
  8589934592,
  0,
];

const List<int> _readerImageMaxAgeOptions = [1, 3, 7, 14, 30, 0];
const List<int> _comicPagesMaxAgeOptions = [3, 7, 14, 30, 90, 0];

@RoutePage()
class CacheSettingPage extends StatefulWidget {
  const CacheSettingPage({super.key});

  @override
  State<CacheSettingPage> createState() => _CacheSettingPageState();
}

class _CacheSettingPageState extends State<CacheSettingPage> {
  CacheCategorySizes? _sizes;
  bool _calculating = false;

  @override
  void initState() {
    super.initState();
    _calculateCacheSize();
  }

  Future<void> _calculateCacheSize() async {
    if (_calculating) return;
    setState(() => _calculating = true);

    try {
      final sizes = await calculateCacheCategorySizes();
      if (!mounted) return;
      setState(() {
        _sizes = sizes;
        _calculating = false;
      });
    } catch (e, st) {
      logger.e(e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _sizes = null;
        _calculating = false;
      });
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return t.cache.calculateFailed;
    if (bytes == 0) return '0 B';

    const gb = 1 << 30;
    const mb = 1 << 20;
    const kb = 1 << 10;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    } else if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    } else if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(1)} KB';
    } else {
      return '$bytes B';
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String content,
  }) async {
    final confirmed = await showPopupPanel<bool>(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (context) => PopupPanel(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.common.ok),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _handleClearAll() async {
    final confirmed = await _confirmAction(
      title: t.cache.clearCache,
      content: t.cache.clearCacheConfirm,
    );
    if (!confirmed) return;

    try {
      final cachePath = await getCachePath();
      await clearCache(cachePath);
      showSuccessToast(t.cache.cleared);
      _calculateCacheSize();
    } catch (e, st) {
      logger.e(e, stackTrace: st);
      showSuccessToast(t.cache.clearFailed);
    }
  }

  Future<void> _handleClearReaderImageProcessing() async {
    final confirmed = await _confirmAction(
      title: t.cache.readerImageProcessing,
      content: t.cache.clearReaderImageProcessingConfirm,
    );
    if (!confirmed) return;

    try {
      await clearReaderImageProcessingCache();
      showSuccessToast(t.cache.cleared);
      _calculateCacheSize();
    } catch (e, st) {
      logger.e(e, stackTrace: st);
      showSuccessToast(t.cache.clearFailed);
    }
  }

  Future<void> _handleClearComicPages() async {
    final confirmed = await _confirmAction(
      title: t.cache.comicPages,
      content: t.cache.clearComicPagesConfirm,
    );
    if (!confirmed) return;

    try {
      await clearComicPagesCache();
      showSuccessToast(t.cache.cleared);
      _calculateCacheSize();
    } catch (e, st) {
      logger.e(e, stackTrace: st);
      showSuccessToast(t.cache.clearFailed);
    }
  }

  Future<void> _handleClearThumbnails() async {
    final confirmed = await _confirmAction(
      title: t.cache.thumbnailsAndCatalogs,
      content: t.cache.clearThumbnailsConfirm,
    );
    if (!confirmed) return;

    try {
      await clearMImageCatalogCache();
      showSuccessToast(t.cache.cleared);
      _calculateCacheSize();
    } catch (e, st) {
      logger.e(e, stackTrace: st);
      showSuccessToast(t.cache.clearFailed);
    }
  }

  Future<void> _handleClearVideoPosters() async {
    final confirmed = await _confirmAction(
      title: t.cache.videoPosters,
      content: t.cache.clearVideoPostersConfirm,
    );
    if (!confirmed) return;

    try {
      await clearVideoPostersCache();
      showSuccessToast(t.cache.cleared);
      _calculateCacheSize();
    } catch (e, st) {
      logger.e(e, stackTrace: st);
      showSuccessToast(t.cache.clearFailed);
    }
  }

  Map<int, String> _buildReaderImageSizeLabels() {
    return {
      for (final option in _readerImageSizeOptions)
        option: option == 0
            ? t.cache.unlimited
            : _cacheLimitLabels[option] ?? _formatSize(option),
    };
  }

  Map<int, String> _buildMaxAgeLabels(List<int> options) {
    return {
      for (final days in options)
        days: days == 0 ? t.cache.unlimited : t.cache.days(days: days),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;
    final cacheSetting = state.cacheSetting;

    final readerImageSizeLabels = _buildReaderImageSizeLabels();
    final readerImageMaxAgeLabels = _buildMaxAgeLabels(
      _readerImageMaxAgeOptions,
    );
    final comicPagesMaxAgeLabels = _buildMaxAgeLabels(_comicPagesMaxAgeOptions);

    return SettingPageShell(
      title: t.cache.title,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          // 1. 当前缓存总体状态与一键清理
          SettingSectionCard(
            title: t.cache.currentCache,
            icon: AppGlyphs.storage,
            children: [
              ListTile(
                leading: const GlyphIcon(AppGlyphs.storage),
                title: Text(t.cache.totalCache),
                subtitle: Text(
                  _calculating
                      ? t.cache.calculating
                      : _formatSize(_sizes?.totalBytes),
                ),
                trailing: _calculating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const GlyphIcon(AppGlyphs.refresh, size: 20),
                        tooltip: t.cache.recalculate,
                        onPressed: _calculateCacheSize,
                      ),
              ),
              ListTile(
                leading: const GlyphIcon(AppGlyphs.broom),
                title: Text(t.cache.clearAll),
                subtitle: Text(t.cache.manualClearSubtitle),
                trailing: FilledButton.tonalIcon(
                  onPressed: _handleClearAll,
                  icon: const GlyphIcon(AppGlyphs.delete, size: 18),
                  label: Text(t.cache.clear),
                ),
              ),
            ],
          ),

          // 2. 缓存分类明细及按类手动清理
          SettingSectionCard(
            title: t.cache.categoryBreakdown,
            icon: AppGlyphs.category,
            children: [
              ListTile(
                leading: const GlyphIcon(AppGlyphs.wand),
                title: Text(t.cache.readerImageProcessing),
                subtitle: Text(
                  '${_calculating ? t.cache.calculating : _formatSize(_sizes?.readerImageProcessingBytes)} · ${t.cache.readerImageProcessingSubtitle}',
                ),
                trailing: FilledButton.tonalIcon(
                  onPressed: _handleClearReaderImageProcessing,
                  icon: const GlyphIcon(AppGlyphs.delete, size: 18),
                  label: Text(t.cache.clear),
                ),
              ),
              ListTile(
                leading: const GlyphIcon(AppGlyphs.openBook),
                title: Text(t.cache.comicPages),
                subtitle: Text(
                  '${_calculating ? t.cache.calculating : _formatSize(_sizes?.comicPagesBytes)} · ${t.cache.comicPagesSubtitle}',
                ),
                trailing: FilledButton.tonalIcon(
                  onPressed: _handleClearComicPages,
                  icon: const GlyphIcon(AppGlyphs.delete, size: 18),
                  label: Text(t.cache.clear),
                ),
              ),
              ListTile(
                leading: const GlyphIcon(AppGlyphs.archive),
                title: Text(t.cache.thumbnailsAndCatalogs),
                subtitle: Text(
                  '${_calculating ? t.cache.calculating : _formatSize(_sizes?.mimageCatalogBytes)} · ${t.cache.thumbnailsAndCatalogsSubtitle}',
                ),
                trailing: FilledButton.tonalIcon(
                  onPressed: _handleClearThumbnails,
                  icon: const GlyphIcon(AppGlyphs.delete, size: 18),
                  label: Text(t.cache.clear),
                ),
              ),
              ListTile(
                leading: const GlyphIcon(AppGlyphs.playCircle),
                title: Text(t.cache.videoPosters),
                subtitle: Text(
                  '${_calculating ? t.cache.calculating : _formatSize(_sizes?.videoPostersBytes)} · ${t.cache.videoPostersSubtitle}',
                ),
                trailing: FilledButton.tonalIcon(
                  onPressed: _handleClearVideoPosters,
                  icon: const GlyphIcon(AppGlyphs.delete, size: 18),
                  label: Text(t.cache.clear),
                ),
              ),
            ],
          ),

          // 3. 图片处理缓存专用自动清理设置（reader_image_processing）
          SettingSectionCard(
            title: t.cache.readerImageProcessingAutoClean,
            icon: AppGlyphs.wand,
            children: [
              SettingGroup.switchTile(
                leading: const GlyphIcon(AppGlyphs.wand),
                title: Text(t.cache.readerImageProcessingAutoClean),
                subtitle: Text(t.cache.readerImageProcessingAutoCleanSubtitle),
                value: cacheSetting.autoCleanReaderImageProcessing,
                onChanged: (bool value) {
                  cubit.updateCacheSetting(
                    (current) =>
                        current.copyWith(autoCleanReaderImageProcessing: value),
                  );
                },
              ),
              if (cacheSetting.autoCleanReaderImageProcessing) ...[
                ListTile(
                  leading: const GlyphIcon(AppGlyphs.clock),
                  title: Text(t.cache.maxAge),
                  subtitle: Text(t.cache.maxAgeSubtitle),
                  trailing: Builder(
                    builder: (context) {
                      final effectiveMaxAge =
                          _readerImageMaxAgeOptions.contains(
                            cacheSetting.readerImageProcessingMaxAgeDays,
                          )
                          ? cacheSetting.readerImageProcessingMaxAgeDays
                          : 7;
                      return FluentDropdown<int>(
                        value: effectiveMaxAge,
                        displayValue:
                            readerImageMaxAgeLabels[effectiveMaxAge] ??
                            t.cache.days(days: effectiveMaxAge),
                        items: readerImageMaxAgeLabels,
                        onChanged: (int value) {
                          cubit.updateCacheSetting(
                            (current) => current.copyWith(
                              readerImageProcessingMaxAgeDays: value,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                ListTile(
                  leading: const GlyphIcon(AppGlyphs.dataUsage),
                  title: Text(t.cache.sizeLimitReaderImage),
                  subtitle: Text(t.cache.sizeLimitReaderImageSubtitle),
                  trailing: Builder(
                    builder: (context) {
                      final effectiveSizeLimit =
                          _readerImageSizeOptions.contains(
                            cacheSetting.readerImageProcessingSizeLimit,
                          )
                          ? cacheSetting.readerImageProcessingSizeLimit
                          : 2147483648;
                      return FluentDropdown<int>(
                        value: effectiveSizeLimit,
                        displayValue:
                            readerImageSizeLabels[effectiveSizeLimit] ??
                            _formatSize(effectiveSizeLimit),
                        items: readerImageSizeLabels,
                        onChanged: (int value) {
                          cubit.updateCacheSetting(
                            (current) => current.copyWith(
                              readerImageProcessingSizeLimit: value,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),

          // 4. 全局自动清理与其它缓存自动清理策略
          SettingSectionCard(
            title: t.cache.autoCleanSettings,
            icon: AppGlyphs.broom,
            children: [
              SettingGroup.switchTile(
                leading: const GlyphIcon(AppGlyphs.broom),
                title: Text(t.cache.autoClean),
                subtitle: Text(t.cache.autoCleanSubtitle),
                value: cacheSetting.autoCleanCache,
                onChanged: (bool value) {
                  cubit.updateCacheSetting(
                    (current) => current.copyWith(autoCleanCache: value),
                  );
                },
              ),
              ListTile(
                leading: const GlyphIcon(AppGlyphs.dataUsage),
                title: Text(t.cache.sizeLimit),
                subtitle: Text(t.cache.sizeLimitSubtitle),
                trailing: Builder(
                  builder: (context) {
                    final effectiveCacheLimit =
                        _cacheLimitOptions.contains(cacheSetting.cacheSizeLimit)
                        ? cacheSetting.cacheSizeLimit
                        : 1073741824;
                    return FluentDropdown<int>(
                      value: effectiveCacheLimit,
                      displayValue: _cacheLimitLabels[effectiveCacheLimit]!,
                      items: _cacheLimitLabels,
                      onChanged: (int value) {
                        cubit.updateCacheSetting(
                          (current) => current.copyWith(cacheSizeLimit: value),
                        );
                      },
                    );
                  },
                ),
              ),
              SettingGroup.switchTile(
                leading: const GlyphIcon(AppGlyphs.refresh),
                title: Text(t.cache.autoCleanOnStartup),
                subtitle: Text(t.cache.autoCleanOnStartupSubtitle),
                value: cacheSetting.autoCleanOnStartup,
                onChanged: (bool value) {
                  cubit.updateCacheSetting(
                    (current) => current.copyWith(autoCleanOnStartup: value),
                  );
                },
              ),
              SettingGroup.switchTile(
                leading: const GlyphIcon(AppGlyphs.openBook),
                title: Text(t.cache.comicPagesAutoClean),
                subtitle: Text(t.cache.comicPagesAutoCleanSubtitle),
                value: cacheSetting.autoCleanComicPages,
                onChanged: (bool value) {
                  cubit.updateCacheSetting(
                    (current) => current.copyWith(autoCleanComicPages: value),
                  );
                },
              ),
              if (cacheSetting.autoCleanComicPages)
                ListTile(
                  leading: const GlyphIcon(AppGlyphs.clock),
                  title: Text(t.cache.maxAge),
                  subtitle: Text(t.cache.comicPagesMaxAgeSubtitle),
                  trailing: Builder(
                    builder: (context) {
                      final effectiveMaxAge =
                          _comicPagesMaxAgeOptions.contains(
                            cacheSetting.comicPagesMaxAgeDays,
                          )
                          ? cacheSetting.comicPagesMaxAgeDays
                          : 30;
                      return FluentDropdown<int>(
                        value: effectiveMaxAge,
                        displayValue:
                            comicPagesMaxAgeLabels[effectiveMaxAge] ??
                            t.cache.days(days: effectiveMaxAge),
                        items: comicPagesMaxAgeLabels,
                        onChanged: (int value) {
                          cubit.updateCacheSetting(
                            (current) =>
                                current.copyWith(comicPagesMaxAgeDays: value),
                          );
                        },
                      );
                    },
                  ),
                ),
              SettingGroup.switchTile(
                leading: const GlyphIcon(AppGlyphs.archive),
                title: Text(t.cache.thumbnailsAutoClean),
                subtitle: Text(t.cache.thumbnailsAutoCleanSubtitle),
                value: cacheSetting.autoCleanThumbnails,
                onChanged: (bool value) {
                  cubit.updateCacheSetting(
                    (current) => current.copyWith(autoCleanThumbnails: value),
                  );
                },
              ),
              SettingGroup.switchTile(
                leading: const GlyphIcon(AppGlyphs.playCircle),
                title: Text(t.cache.videoPostersAutoClean),
                subtitle: Text(t.cache.videoPostersAutoCleanSubtitle),
                value: cacheSetting.autoCleanVideoPosters,
                onChanged: (bool value) {
                  cubit.updateCacheSetting(
                    (current) => current.copyWith(autoCleanVideoPosters: value),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
