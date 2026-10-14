import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zephyr/page/setting/real_sr/service/mimage_onnx_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/page/setting/real_sr/widgets/super_resolution_log_controls.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 阅读器和全局设置共用的模型配置，关闭超分时也能选择、下载模型。
class MImageModelSettings extends StatefulWidget {
  const MImageModelSettings({super.key, this.showLogControls = true});

  final bool showLogControls;

  @override
  State<MImageModelSettings> createState() => _MImageModelSettingsState();
}

class _MImageModelSettingsState extends State<MImageModelSettings> {
  MImageOnnxModel _model = MImageOnnxModelConfig.defaultModel;
  bool _loading = true;
  bool _busy = false;
  bool _available = false;
  double? _progress;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    RealSrSettings.modelChanges.addListener(_reload);
    _load();
  }

  void _reload() => _load();

  @override
  void dispose() {
    RealSrSettings.modelChanges.removeListener(_reload);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final model = await RealSrSettings.loadMImageModel();
      final available = await RealSrSuperResolution.isMImageModelAvailable(
        model,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _model = model;
        _available = available;
        _loading = false;
      });
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      await operation();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final file = await openFile(
      acceptedTypeGroups: [
        Platform.isIOS
            ? XTypeGroup(label: t.realSr.onnxModel)
            : XTypeGroup(label: t.realSr.onnxModel, extensions: ['onnx']),
      ],
    );
    if (file != null) {
      await RealSrSuperResolution.importMImageModel(file.path, _model);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.realSr.customModel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          DropdownButton<MImageOnnxModel>(
            key: const ValueKey('mimage-model-selector'),
            value: _model,
            isExpanded: true,
            itemHeight: null,
            items: [
              for (final model in MImageOnnxModel.values)
                DropdownMenuItem(
                  value: model,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(model.label),
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (model) {
                    if (model != null) {
                      _run(() => RealSrSettings.saveMImageModel(model));
                    }
                  },
          ),
          const SizedBox(height: 8),
          Text(t.realSr.modelScaleNote(scale: _model.scale)),
          const SizedBox(height: 6),
          Text(
            _model.supportsDenoise
                ? t.realSr.modelDenoiseCugan
                : t.realSr.modelDenoiseFixed,
          ),
          const SizedBox(height: 6),
          Text(t.realSr.modelRuntime(runtime: mImageRuntimeLabel)),
          const SizedBox(height: 12),
          Text(
            _available ? t.realSr.modelInstalled : t.realSr.modelNotInstalled,
            style: TextStyle(
              color: _available ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            _model.fileName,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => RealSrSuperResolution.downloadModel(
                          mImageModel: _model,
                          force: _available,
                          onProgress: (received, total) {
                            if (mounted && total > 0) {
                              setState(() => _progress = received / total);
                            }
                          },
                        ),
                      ),
                icon: const GlyphIcon(AppGlyphs.download),
                label: Text(
                  _available
                      ? t.realSr.redownloadCurrentModel
                      : t.realSr.downloadCurrentModel,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(_import),
                icon: const GlyphIcon(AppGlyphs.folder),
                label: Text(t.realSr.importLocalOnnx),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final uri = Uri.parse(
                          '${MImageOnnxModelConfig.baseUrl}/${_model.fileName}',
                        );
                        if (!await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        )) {
                          throw StateError('无法打开下载链接');
                        }
                      }),
                child: Text(t.realSr.downloadInBrowser),
              ),
              if (_available)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final confirmed = await showPopupPanel<bool>(
                            context: context,
                            presentation: PopupPresentation.modal,
                            builder: (context) => PopupPanel(
                              title: Text(t.realSr.deleteCurrentModel),
                              content: Text(
                                t.realSr.deleteModelConfirmNamed(
                                  name: _model.label,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(t.common.cancel),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(t.common.delete),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && mounted) {
                            await _run(
                              () => RealSrSuperResolution.deleteModel(_model),
                            );
                          }
                        },
                  child: Text(t.realSr.deleteCurrentModel),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.realSr.importLocalHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (widget.showLogControls) const SuperResolutionLogControls(),
          if (_busy) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress?.clamp(0, 1)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              t.realSr.actionFailedDetail(error: _error!),
              style: TextStyle(color: colors.error),
            ),
          ],
        ],
      ),
    );
  }
}
