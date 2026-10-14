import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/super_resolution_section.dart';
import 'package:zephyr/page/setting/real_sr/service/denoise_model_download.dart';
import 'package:zephyr/page/setting/real_sr/service/image_denoise_model.dart';
import 'package:zephyr/page/setting/real_sr/service/image_denoise_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/widgets/image_processing/denoise_model_card.dart';
import 'package:zephyr/page/setting/real_sr/widgets/image_processing/processing_example.dart';
import 'package:zephyr/page/setting/real_sr/widgets/image_processing/processing_settings_card.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';

class ImageDenoiseSection extends StatefulWidget {
  const ImageDenoiseSection({
    super.key,
    this.globalOnly = false,
    this.modelDownload,
  });
  final DenoiseModelDownload? modelDownload;
  final bool globalOnly;
  @override
  State<ImageDenoiseSection> createState() => _ImageDenoiseSectionState();
}

class _ImageDenoiseSectionState extends State<ImageDenoiseSection> {
  DenoiseModelDownload get _downloads =>
      widget.modelDownload ?? ImageDenoiseModel.downloads;
  bool _global = false;
  bool _book = false;
  bool _loading = true;
  ImageDenoiseOptions _options = const ImageDenoiseOptions();
  int _revision = 0;
  String? get _bookKey => widget.globalOnly ? null : activeReaderBookKey();

  @override
  void initState() {
    super.initState();
    ImageDenoiseSettings.changes.addListener(_reload);
    ReaderSessionCoordinator.instance.addListener(_reload);
    _reload();
    if (supportsMImageOnnx) unawaited(_downloads.refresh());
  }

  void _reload() => unawaited(_load());
  Future<void> _load() async {
    final revision = ++_revision;
    final key = _bookKey;
    final global = await ImageDenoiseSettings.globalEnabled();
    final book = await ImageDenoiseSettings.enabledFor(key);
    final options = await ImageDenoiseSettings.loadOptions();
    if (!mounted || revision != _revision || key != _bookKey) return;
    setState(() {
      _global = global;
      _book = book;
      _options = options;
      _loading = false;
    });
  }

  @override
  void dispose() {
    ImageDenoiseSettings.changes.removeListener(_reload);
    ReaderSessionCoordinator.instance.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProcessingSettingsCard(
    title: 'AI JPEG 降噪',
    icon: Icons.auto_fix_high,
    description: '在线和本地漫画共用；保持原分辨率，降噪后再超分',
    status: !supportsMImageOnnx
        ? '当前平台暂无 RealPLKSR 推理后端'
        : _loading
        ? '读取设置…'
        : (_bookKey == null ? _global : _book)
        ? '已开启 · RealPLKSR 1×'
        : '已关闭 · 原图保持不变',
    children: [
      ProcessingExample(
        kind: ProcessingExampleKind.denoise,
        enabled: !_loading && (_bookKey == null ? _global : _book),
        reloadOn: _downloads,
      ),
      if (supportsMImageOnnx) ...[
        if (!widget.globalOnly)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: ExpressiveShapeBadge(
              icon: AppGlyphs.book,
              shape: ExpressiveButtonShape.clover4Leaf,
              size: 36,
              glyphSize: 18,
              tone: ExpressiveTone.primary,
              active: _book,
            ),
            title: const Text(
              '本书启用 JPEG 降噪',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              _bookKey == null ? '打开在线或本地漫画后可单独设置' : '只影响当前漫画；超分由它自己的开关决定',
            ),
            value: _book,
            onChanged: _loading || _bookKey == null
                ? null
                : (v) {
                    HapticFeedback.lightImpact();
                    unawaited(ImageDenoiseSettings.saveFor(_bookKey, v));
                  },
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: ExpressiveShapeBadge(
            icon: AppGlyphs.wand,
            shape: ExpressiveButtonShape.sunny,
            size: 36,
            glyphSize: 18,
            tone: ExpressiveTone.secondary,
            active: _global,
          ),
          title: const Text(
            '所有漫画默认启用降噪',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          value: _global,
          onChanged: _loading
              ? null
              : (v) {
                  HapticFeedback.lightImpact();
                  unawaited(ImageDenoiseSettings.saveGlobal(v));
                },
        ),
        DenoiseModelCard(download: _downloads),
        ProcessingAdvancedDisclosure(
          title: '降噪高级设置',
          child: Column(
            children: [
              SettingsDropdownTile<int>(
                title: '降噪分块大小',
                subtitle: '与超分独立。较小的分块降低推理内存占用；固定输入模型按模型尺寸处理',
                icon: AppGlyphs.gridPlus,
                badgeShape: ExpressiveButtonShape.cookie6Sided,
                badgeTone: ExpressiveTone.tertiary,
                value: _options.tileSize,
                values: ImageDenoiseOptions.tileSizes,
                labelOf: (v) => v == 0 ? '自动' : '$v × $v',
                onChanged: (v) {
                  HapticFeedback.lightImpact();
                  unawaited(
                    ImageDenoiseSettings.saveOptions(
                      _options.copyWith(tileSize: v),
                    ),
                  );
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: ExpressiveShapeBadge(
                  icon: AppGlyphs.photos,
                  shape: ExpressiveButtonShape.puffyDiamond,
                  size: 36,
                  glyphSize: 18,
                  tone: ExpressiveTone.tertiary,
                  active: _options.jpegOnly,
                ),
                title: const Text(
                  '仅处理 JPEG 页面',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('按文件头识别。PNG、WebP 等页面保留原样'),
                value: _options.jpegOnly,
                onChanged: (v) {
                  HapticFeedback.lightImpact();
                  unawaited(
                    ImageDenoiseSettings.saveOptions(
                      _options.copyWith(jpegOnly: v),
                    ),
                  );
                },
              ),
              const Text('动画页面不参与处理。模型效果强度固定；原图、降噪和超分结果分别缓存。'),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: processingActionStyle(),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('恢复默认参数'),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    unawaited(
                      ImageDenoiseSettings.saveOptions(
                        const ImageDenoiseOptions(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}
