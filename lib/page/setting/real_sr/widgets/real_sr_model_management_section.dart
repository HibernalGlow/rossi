import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/real_sr/service/android_sr_engine.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';

/// 桌面 NCNN 的模型管理三行：下载 / 手动下载 / 导入。
///
/// 从 `RealSrSettingPage` 里提出来，是因为工作台那张超分卡要能**就地**把模型下完 ——
/// 卡片弹不掉任何路由，给它一条「去设置页」等于没有出口。
///
/// [grouped] 决定外壳：设置页用 `Divider` + 段落标题那套整页排版，
/// 卡片用 [SettingsSection] + [SettingsCardGroup]。内容一个字没差。
class RealSrModelManagementSection extends StatefulWidget {
  const RealSrModelManagementSection({super.key, this.grouped = false});

  /// `true` = 卡片外壳（分组卡 + 小标题）；`false` = 设置页外壳。
  final bool grouped;

  @override
  State<RealSrModelManagementSection> createState() =>
      _RealSrModelManagementSectionState();
}

class _RealSrModelManagementSectionState
    extends State<RealSrModelManagementSection> {
  bool _loading = true;
  bool _isAvailable = false;

  /// 可用性问不出来（路径拿不到 / native 报错）：这一节整块不画。
  bool _failed = false;
  bool _downloading = false;
  bool _importing = false;
  double _downloadProgress = 0;
  SuperResolutionEngine _engine = defaultEngine;
  AndroidSuperResolutionEngine _androidEngine =
      defaultAndroidSuperResolutionEngine;

  /// 「模型管理」三行要不要画。
  ///
  /// Apple 没有 NCNN 这条引擎，永远不画；Windows / Linux 只在选中桌面 NCNN 时画 ——
  /// 切到 mImage ONNX 之后，模型的下载/导入由 ONNX 面板自己管，这里再摆一份就会
  /// 出现「按了下载却去拉 7z」的错路。
  /// Android 只在 QNN NPU 引擎下画：Vulkan 引擎的 NCNN 模型是全自动下载的，
  /// 没有「管理」可言；QNN 的 DLC 包需要显式下载/导入。
  bool get _applies {
    if (Platform.isAndroid) {
      return _androidEngine == AndroidSuperResolutionEngine.qnnNpu;
    }
    return supportsDesktopNcnn && _engine != SuperResolutionEngine.mimageOnnx;
  }

  @override
  void initState() {
    super.initState();
    RealSrSettings.modelChanges.addListener(_refreshAvailability);
    _refreshAvailability();
  }

  @override
  void dispose() {
    RealSrSettings.modelChanges.removeListener(_refreshAvailability);
    super.dispose();
  }

  /// 切引擎会走 `modelChanges` 通知到这里：可用性与「该画哪几块」都随引擎变，
  /// 所以两处一起刷。
  Future<void> _refreshAvailability() async {
    // 拿不到就整块不画，而不是把异常抛给面板：`isAvailable` 要问磁盘与 native，
    // 这一节住在卡片里，炸一次就是整条右泳道红一条。
    Object? failure;
    List<Object?> results = const [];
    try {
      results = await Future.wait([
        RealSrSuperResolution.isAvailable,
        RealSrSettings.loadEngine(),
        if (Platform.isAndroid) RealSrSettings.loadAndroidEngine(),
      ]);
    } catch (e) {
      failure = e;
    }
    if (!mounted) return;
    setState(() {
      if (failure == null) {
        _isAvailable = results[0] as bool;
        _engine = results[1] as SuperResolutionEngine;
        if (Platform.isAndroid) {
          _androidEngine = results[2] as AndroidSuperResolutionEngine;
        }
      } else {
        _failed = true;
      }
      _loading = false;
    });
  }

  Future<void> _downloadModel() async {
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
    });

    try {
      await RealSrSuperResolution.downloadModel(
        force: _isAvailable,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _downloadProgress = received / total);
        },
      );
    } catch (e, s) {
      logger.e('模型下载失败', error: e, stackTrace: s);
      showErrorToast('${t.realSr.modelDownloadFailed}: $e');
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
        await _refreshAvailability();
      }
    }
  }

  Future<void> _deleteModel() async {
    final confirmed = await showPopupPanel<bool>(
      context: context,
      presentation: PopupPresentation.modal,
      builder: (context) => PopupPanel(
        title: Text(t.realSr.deleteModel),
        content: Text(t.realSr.deleteModelConfirm),
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

    if (confirmed != true || !mounted) return;

    try {
      await RealSrSuperResolution.deleteModel();
      showSuccessToast(t.realSr.modelDeleted);
    } catch (e, s) {
      logger.e('模型删除失败', error: e, stackTrace: s);
      showErrorToast('${t.realSr.modelDeleteFailed}: $e');
    } finally {
      if (mounted) await _refreshAvailability();
    }
  }

  Future<void> _openManualDownloadUrl() async {
    final url = RealSrSuperResolution.manualDownloadUrl;
    if (url == null) {
      showErrorToast(t.realSr.manualDownloadUnsupported);
      return;
    }
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      showErrorToast(t.realSr.openDownloadUrlFailed);
    }
  }

  Future<void> _importModel() async {
    // iOS 没有系统声明的 7z UTI，使用通用数据类型后由导入逻辑校验 7z 魔数。
    final typeGroup = Platform.isIOS
        ? const XTypeGroup(label: '7z')
        : const XTypeGroup(label: '7z', extensions: ['7z']);
    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: [typeGroup]);
    } catch (e) {
      showErrorToast('${t.realSr.modelImportFailed}: $e');
      return;
    }
    if (file == null) return;

    setState(() => _importing = true);
    try {
      await RealSrSuperResolution.importModelArchive(file.path);
      if (mounted) showSuccessToast(t.realSr.modelImportSuccess);
    } catch (e, s) {
      logger.e('模型导入失败', error: e, stackTrace: s);
      if (mounted) {
        showErrorToast('${t.realSr.modelImportFailed}: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _importing = false);
        await _refreshAvailability();
      }
    }
  }

  List<Widget> _tiles() {
    return [_modelTile(), _manualDownloadTile(), _importTile()];
  }

  Widget _modelTile() {
    if (_downloading) {
      return ListTile(
        leading: const GlyphIcon(AppGlyphs.downloading),
        title: Text(t.realSr.downloadingModel),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _downloadProgress),
            const SizedBox(height: 4),
            Text('${(_downloadProgress * 100).toStringAsFixed(1)}%'),
          ],
        ),
      );
    }

    if (_isAvailable) {
      return ListTile(
        leading: GlyphIcon(
          AppGlyphs.checkCircle,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(t.realSr.modelReady),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: _deleteModel,
              child: Text(t.realSr.deleteModel),
            ),
            TextButton(
              onPressed: _downloadModel,
              child: Text(t.realSr.redownload),
            ),
          ],
        ),
      );
    }

    return ListTile(
      leading: const GlyphIcon(AppGlyphs.error),
      title: Text(t.realSr.modelNotDownloaded),
      subtitle: Text(t.realSr.modelNotDownloadedSubtitle),
      trailing: ElevatedButton(
        onPressed: _downloadModel,
        child: Text(t.realSr.downloadModel),
      ),
    );
  }

  Widget _manualDownloadTile() {
    final url = RealSrSuperResolution.manualDownloadUrl;
    if (url == null) {
      return ListTile(
        leading: const GlyphIcon(AppGlyphs.openExternal),
        title: Text(t.realSr.manualDownload),
        subtitle: Text(t.realSr.manualDownloadUnsupported),
      );
    }
    return ListTile(
      leading: const GlyphIcon(AppGlyphs.openExternal),
      title: Text(t.realSr.manualDownload),
      subtitle: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: TextButton(
        onPressed: _openManualDownloadUrl,
        child: Text(t.realSr.openDownloadUrl),
      ),
    );
  }

  Widget _importTile() {
    return ListTile(
      leading: const GlyphIcon(AppGlyphs.folder),
      title: Text(t.realSr.importModel),
      subtitle: Text(t.realSr.importModelSubtitle),
      trailing: _importing
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              onPressed: _importModel,
              child: Text(t.realSr.importModelAction),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _failed || !_applies) return const SizedBox.shrink();

    if (!widget.grouped) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 0.3),
          settingSectionTitle(context, t.realSr.modelManagementSection),
          ..._tiles(),
        ],
      );
    }

    return SettingsSection(
      title: t.realSr.modelManagementSection,
      icon: AppGlyphs.box,
      children: [SettingsCardGroup(children: _tiles())],
    );
  }
}
