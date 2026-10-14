import 'package:zephyr/page/setting/common/setting_group.dart';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/util/manage_cache.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';

import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/icons/icons.dart';

const Map<int, String> _cacheLimitLabels = {
  536870912: '512 MB',
  1073741824: '1 GB',
  2147483648: '2 GB',
  4294967296: '4 GB',
  8589934592: '8 GB',
  17179869184: '16 GB',
};

final List<int> _cacheLimitOptions = _cacheLimitLabels.keys.toList()..sort();

@RoutePage()
class CacheSettingPage extends StatefulWidget {
  const CacheSettingPage({super.key});

  @override
  State<CacheSettingPage> createState() => _CacheSettingPageState();
}

class _CacheSettingPageState extends State<CacheSettingPage> {
  int? _cacheSizeBytes;
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
      final cachePath = await getCachePath();
      final directory = Directory(cachePath);
      if (!await directory.exists()) {
        if (!mounted) return;
        setState(() {
          _cacheSizeBytes = 0;
          _calculating = false;
        });
        return;
      }

      int totalSize = 0;
      final entities = directory.listSync(recursive: true);
      for (final entity in entities) {
        final isSentry = entity.path
            .split(Platform.pathSeparator)
            .contains('sentry');
        if (entity is File && !isSentry) {
          try {
            totalSize += await entity.length();
          } on FileSystemException {
            continue;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _cacheSizeBytes = totalSize;
        _calculating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cacheSizeBytes = null;
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

  Future<void> _handleClearCache() async {
    final confirmed = await showPopupPanel<bool>(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (context) => PopupPanel(
        title: Text(t.cache.clearCache),
        content: Text(t.cache.clearCacheConfirm),
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

    if (confirmed != true) return;

    try {
      final cachePath = await getCachePath();
      await clearCache(cachePath);
      showSuccessToast(t.cache.cleared);
      _calculateCacheSize();
    } catch (_) {
      showSuccessToast(t.cache.clearFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;

    return SettingPageShell(
      title: t.cache.title,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          SettingSectionCard(
            title: t.cache.currentCache,
            icon: AppGlyphs.storage,
            children: [
              ListTile(
                leading: const GlyphIcon(AppGlyphs.storage),
                title: Text(t.cache.cacheSize),
                subtitle: Text(
                  _calculating
                      ? t.cache.calculating
                      : _formatSize(_cacheSizeBytes),
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
                title: Text(t.cache.manualClear),
                subtitle: Text(t.cache.manualClearSubtitle),
                trailing: FilledButton.tonalIcon(
                  onPressed: _handleClearCache,
                  icon: const GlyphIcon(AppGlyphs.delete, size: 18),
                  label: Text(t.cache.clear),
                ),
              ),
            ],
          ),
          SettingSectionCard(
            title: t.cache.cacheLimit,
            icon: AppGlyphs.dataUsage,
            children: [
              ListTile(
                leading: const GlyphIcon(AppGlyphs.dataUsage),
                title: Text(t.cache.sizeLimit),
                subtitle: Text(t.cache.sizeLimitSubtitle),
                trailing: Builder(
                  builder: (context) {
                    final effectiveCacheLimit =
                        _cacheLimitOptions.contains(
                          state.cacheSetting.cacheSizeLimit,
                        )
                        ? state.cacheSetting.cacheSizeLimit
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
            ],
          ),
          SettingSectionCard(
            title: t.cache.autoClean,
            icon: AppGlyphs.broom,
            children: [
              SettingGroup.switchTile(
                leading: const GlyphIcon(AppGlyphs.broom),
                title: Text(t.cache.autoClean),
                subtitle: Text(t.cache.autoCleanSubtitle),
                value: state.cacheSetting.autoCleanCache,
                onChanged: (bool value) {
                  cubit.updateCacheSetting(
                    (current) => current.copyWith(autoCleanCache: value),
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
