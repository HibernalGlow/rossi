import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/real_sr/service/android_qnn_engine.dart';
import 'package:zephyr/page/setting/real_sr/service/android_qnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/android_sr_engine.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';

/// Android 超分引擎选择与 QNN NPU 模型准备状态。
///
/// - 引擎：Vulkan CLI（默认）/ QNN NPU（实验阶段；仅受支持的骁龙 HTP）。
/// - 选 QNN 时展示：HTP 架构探测结果、模型选择、上下文准备状态与重试。
/// - 模型下载 / 导入走底部统一的「模型管理」区（引擎感知，选 QNN 时
///   下载的是 `realsr-qnn-android.7z`）。
class AndroidEngineSettings extends StatefulWidget {
  const AndroidEngineSettings({super.key});

  @override
  State<AndroidEngineSettings> createState() => _AndroidEngineSettingsState();
}

class _AndroidEngineSettingsState extends State<AndroidEngineSettings> {
  AndroidSuperResolutionEngine _engine = defaultAndroidSuperResolutionEngine;
  AndroidQnnModel _qnnModel = AndroidQnnModelConfig.defaultModel;

  /// null = 探测中；true/false = QNN 是否可用。
  bool? _qnnSupported;
  int? _htpArchitecture;
  Map<String, AndroidQnnModelStatus> _statuses = {};
  bool _preparing = false;
  String? _prepareError;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    RealSrSettings.modelChanges.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    RealSrSettings.modelChanges.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    final engine = await RealSrSettings.loadAndroidEngine();
    final model = await RealSrSettings.loadAndroidQnnModel();
    final probe = await AndroidQnnEngine.probe();
    final statuses = await _quietStatus();
    if (!mounted || generation != _generation) return;
    setState(() {
      _engine = engine;
      _qnnModel = model;
      _qnnSupported = probe?.supported;
      _htpArchitecture = probe?.architecture;
      _statuses = statuses;
    });
  }

  /// 状态查询失败不值得打断整个面板（原生侧未注册时会 MissingPluginException）。
  Future<Map<String, AndroidQnnModelStatus>> _quietStatus() async {
    try {
      return await AndroidQnnEngine.status();
    } catch (_) {
      return {};
    }
  }

  Future<void> _setEngine(AndroidSuperResolutionEngine value) async {
    await RealSrSettings.saveAndroidEngine(value);
    // saveAndroidEngine 已发 modelChanges → _reload 会跟着刷；
    // 这里只更新本地回显，避免下拉闪烁。
    setState(() => _engine = value);
  }

  Future<void> _setQnnModel(AndroidQnnModel value) async {
    await RealSrSettings.saveAndroidQnnModel(value);
    setState(() => _qnnModel = value);
    await _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final statuses = await _quietStatus();
    if (mounted) setState(() => _statuses = statuses);
  }

  /// 手动触发上下文编译（下载好的 DLC → 设备端 QNN context）。
  Future<void> _prepareModel({bool retry = false}) async {
    if (_preparing) return;
    setState(() {
      _preparing = true;
      _prepareError = null;
    });
    try {
      final error = await AndroidQnnEngine.prepare(
        model: _qnnModel,
        retry: retry,
      );
      if (error != null && mounted) {
        setState(() => _prepareError = error);
      }
    } catch (e) {
      if (mounted) setState(() => _prepareError = '$e');
    } finally {
      if (mounted) setState(() => _preparing = false);
      await _refreshStatus();
    }
  }

  Widget _buildProbeLine() {
    if (_qnnSupported == null) {
      return ListTile(
        leading: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text(t.realSr.qnnProbing),
      );
    }
    if (_qnnSupported == true) {
      return ListTile(
        leading: const GlyphIcon(AppGlyphs.checkCircle),
        title: Text(t.realSr.qnnSupported(arch: 'v${_htpArchitecture ?? '?'}')),
        subtitle: Text(t.realSr.qnnSupportedSubtitle),
      );
    }
    return ListTile(
      leading: const GlyphIcon(AppGlyphs.info),
      title: Text(t.realSr.qnnUnsupported),
      subtitle: Text(
        _htpArchitecture != null
            ? t.realSr.qnnUnsupportedArchSubtitle(arch: 'v$_htpArchitecture')
            : t.realSr.qnnUnsupportedSubtitle,
      ),
    );
  }

  Widget _buildQnnSection() {
    final status = _statuses[_qnnModel.id];
    final state = status?.state ?? 'idle';
    final modelReady = state == 'ready';
    return Column(
      children: [
        _buildProbeLine(),
        if (_qnnSupported == true)
          ListTile(
            leading: const GlyphIcon(AppGlyphs.memory),
            title: Text(t.realSr.qnnModel),
            subtitle: Text(t.realSr.qnnModelSubtitle),
            trailing: FluentDropdown<AndroidQnnModel>(
              value: _qnnModel,
              displayValue: _qnnModel.label,
              items: {
                for (final model in AndroidQnnModel.values) model: model.label,
              },
              onChanged: _setQnnModel,
            ),
          ),
        ListTile(
          leading: GlyphIcon(
            modelReady
                ? AppGlyphs.checkCircle
                : state == 'failed'
                ? AppGlyphs.block
                : AppGlyphs.settings,
          ),
          title: Text(switch (state) {
            'preparing' => t.realSr.qnnPreparing,
            'ready' => t.realSr.qnnReady,
            'failed' => t.realSr.qnnFailed,
            _ => t.realSr.qnnIdle,
          }),
          subtitle: state == 'failed' && (status?.error?.isNotEmpty ?? false)
              ? Text(status!.error!)
              : state == 'idle'
              ? Text(t.realSr.qnnIdleSubtitle)
              : null,
          trailing: state == 'failed'
              ? TextButton(
                  onPressed: _preparing
                      ? null
                      : () => _prepareModel(retry: true),
                  child: Text(t.realSr.qnnRetry),
                )
              : state == 'idle'
              ? TextButton(
                  onPressed: _preparing ? null : () => _prepareModel(),
                  child: Text(t.realSr.qnnPrepare),
                )
              : _preparing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const GlyphIcon(AppGlyphs.memory),
          title: Text(t.realSr.androidEngine),
          subtitle: Text(t.realSr.androidEngineSubtitle),
          trailing: FluentDropdown<AndroidSuperResolutionEngine>(
            value: _engine,
            displayValue: _engine.label,
            items: {
              for (final engine in AndroidSuperResolutionEngine.values)
                engine: engine.label,
            },
            onChanged: _setEngine,
          ),
        ),
        ListTile(
          leading: const GlyphIcon(AppGlyphs.info),
          title: Text(_engine.subtitle),
          subtitle: Text(
            _engine == AndroidSuperResolutionEngine.qnnNpu
                ? t.realSr.androidEngineQnnExperimental
                : t.realSr.androidSuperResolutionSubtitle,
          ),
        ),
        if (_engine == AndroidSuperResolutionEngine.qnnNpu) _buildQnnSection(),
      ],
    );
  }
}
