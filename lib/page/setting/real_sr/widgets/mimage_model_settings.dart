import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zephyr/page/setting/real_sr/service/mimage_onnx_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/page/setting/real_sr/widgets/super_resolution_log_controls.dart';

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
            ? const XTypeGroup(label: 'ONNX 模型')
            : const XTypeGroup(label: 'ONNX 模型', extensions: ['onnx']),
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
          Text('自定义超分模型', style: Theme.of(context).textTheme.titleSmall),
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
          Text('倍率：原生 ${_model.scale}×（由模型决定）'),
          const SizedBox(height: 6),
          Text(
            _model.supportsDenoise
                ? '降噪：Real-CUGAN 保守修复，强度由模型固定'
                : '降噪：由模型固定，不支持单独调节强度',
          ),
          const SizedBox(height: 6),
          const Text('运行时：CoreML · Apple Neural Engine / GPU'),
          const SizedBox(height: 12),
          Text(
            _available ? '当前模型已安装' : '当前模型未安装，下载或导入后才能使用',
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
                icon: const Icon(Icons.download_outlined),
                label: Text(_available ? '重新下载当前模型' : '下载当前模型'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(_import),
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('导入本地 ONNX'),
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
                child: const Text('浏览器下载'),
              ),
              if (_available)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('删除当前模型'),
                              content: Text('删除 ${_model.label}？需要时可以重新下载。'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('删除'),
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
                  child: const Text('删除当前模型'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '本地导入请选择上方文件名对应的 mImage ONNX 模型。切换后当前页会重新生成超分图。',
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
            Text('操作失败：$_error', style: TextStyle(color: colors.error)),
          ],
        ],
      ),
    );
  }
}
