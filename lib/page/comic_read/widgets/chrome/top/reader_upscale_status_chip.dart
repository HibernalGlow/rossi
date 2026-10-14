import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_feature_button.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_book_scope.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/super_resolution_status.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 当前页超分状态与本书启停。主体切换原图对比，电源独立启停；
/// 分辨率和阶段保留在详情及悬停提示中，在线来源回退到本书开关。
class ReaderUpscaleStatusChip extends StatefulWidget {
  const ReaderUpscaleStatusChip({
    super.key,
    this.availableWidth = double.infinity,
  });

  /// 顶栏的可用宽度（逻辑像素）。决定要不要写分辨率文字。
  final double availableWidth;

  @override
  State<ReaderUpscaleStatusChip> createState() =>
      _ReaderUpscaleStatusChipState();
}

class _ReaderUpscaleStatusChipState extends State<ReaderUpscaleStatusChip> {
  GpuPresentController? _heldPresenter;
  bool? _previewBeforeHold;

  void _startHold(GpuPresentController presenter) {
    if (_heldPresenter != null ||
        !(presenter.isUpscaleEnabled || presenter.isDenoiseEnabled)) {
      return;
    }
    _heldPresenter = presenter;
    _previewBeforeHold = presenter.isOriginalPreview;
    if (!_previewBeforeHold!) unawaited(presenter.setOriginalPreview(true));
  }

  void _endHold() {
    final presenter = _heldPresenter;
    final restore = _previewBeforeHold;
    _heldPresenter = null;
    _previewBeforeHold = null;
    if (presenter != null && restore == false) {
      unawaited(presenter.setOriginalPreview(false));
    }
  }

  @override
  void dispose() {
    _endHold();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GpuPresentController? presenter = LocalReadSession.instance.presenter;
    if (presenter == null) {
      // 在线图源没有呈现器 —— 超分在取图/解码层发生，没有「当前页」可言。
      // 但按用户的口径「超分的显示与开关留在第一行」，这里仍然给一颗绑到
      // 本书覆盖的简版按钮，而不是整块不画。
      return ReaderOnlineUpscaleChip(availableWidth: widget.availableWidth);
    }
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        if (!presenter.canPresent) {
          return const SizedBox.shrink();
        }
        return _buildChip(context, presenter);
      },
    );
  }

  Widget _buildChip(BuildContext context, GpuPresentController presenter) {
    final status = presenter.currentPageUpscaleStatus;
    final enabled = presenter.isUpscaleEnabled;
    final processing = enabled || presenter.isDenoiseEnabled;
    final sizeText = superResolutionSizeText(status, widget.availableWidth);
    // 主体继续负责原图对比；独立电源按钮负责本书启停，两个目标都保持 48dp。
    return ReaderToolbarGroup(
      children: [
        ReaderToolbarFeatureButton(
          icon: switch (status.phase) {
            SuperResolutionPagePhase.originalPreview => AppGlyphs.photos,
            SuperResolutionPagePhase.failed => AppGlyphs.error,
            SuperResolutionPagePhase.unsupported => AppGlyphs.block,
            _ => AppGlyphs.sparkle,
          },
          label: status.processName,
          shape: ExpressiveButtonShape.cookie4Sided,
          detail:
              sizeText ??
              (widget.availableWidth >= 880
                  ? imageEnhancementPhaseLabel(status)
                  : null),
          tooltip: t.reader.upscaleChipTail(
            tooltip: superResolutionTooltip(status),
          ),
          selected: processing && !presenter.isOriginalPreview,
          showSelection: false,
          busy: superResolutionPhaseIsBusy(status.phase),
          failed: status.phase == SuperResolutionPagePhase.failed,
          showLabel: true,
          onPressed: () => _onBodyTap(context, presenter, status, processing),
          onLongPressStart: () => _startHold(presenter),
          onLongPressEnd: _endHold,
        ),
        ReaderToolbarFeatureButton(
          icon: AppGlyphs.power,
          label: '超分',
          tooltip: enabled
              ? t.reader.disableBookUpscale
              : t.reader.enableBookUpscale,
          selected: enabled,
          showLabel: false,
          onPressed: () =>
              enabled ? _disable(presenter) : _enable(context, presenter),
        ),
      ],
    );
  }

  /// 点主体：开着就切「对比原图」，关着就当按下开关。
  Future<void> _onBodyTap(
    BuildContext context,
    GpuPresentController presenter,
    SuperResolutionPageStatus status,
    bool processing,
  ) async {
    if (!processing) {
      await _enable(context, presenter);
      return;
    }
    final bool willBeOriginal =
        status.phase != SuperResolutionPagePhase.originalPreview;
    await presenter.setOriginalPreview(willBeOriginal);
    showInfoToast(
      willBeOriginal
          ? t.reader.switchedToOriginalCompare
          : t.reader.switchedBackToProcessed,
    );
  }

  /// 打开超分。**模型没下载时不偷偷失败** —— 先问一句再下。
  ///
  /// 这颗开关是**本书**的：写的是这本书自己的覆盖（`RealSrBookScope`），
  /// 全局那条（设置页「自动超分」）不受影响 —— 别的书照旧按全局走。
  Future<void> _enable(
    BuildContext context,
    GpuPresentController presenter,
  ) async {
    if (!await ensureSuperResolutionModel(context)) return;
    await RealSrBookScope.setForActiveLocalBook(true);
    await presenter.setUpscaleEnabled(true);
    showInfoToast(t.reader.bookAiUpscaleOn);
  }

  Future<void> _disable(GpuPresentController presenter) async {
    await RealSrBookScope.setForActiveLocalBook(false);
    await presenter.setUpscaleEnabled(false);
    showInfoToast(t.reader.bookAiUpscaleOff);
  }
}

/// 让超分模型就绪：已下载直接返回 true；没下载则**先问一句再下**。
///
/// 抽出来是因为顶栏那两条路（本地呈现器的开关 / 在线图源的总闸开关）都得
/// 先过这一关 —— 同一件事不该有两种交互。
Future<bool> ensureSuperResolutionModel(BuildContext context) async {
  if (await RealSrSuperResolution.isAvailable) return true;
  // 上面那一次 await 之后再用 context：窗口可能已经拆了。
  if (!context.mounted) return false;
  final bool? confirm = await showPopupPanel<bool>(
    context: context,
    presentation: PopupPresentation.modal,
    builder: (ctx) => PopupPanel(
      title: Text(t.reader.downloadAiUpscaleModel),
      content: Text(t.reader.mimageModelMissingPrompt),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(t.reader.downloadNow),
        ),
      ],
    ),
  );
  if (confirm != true) return false;
  showInfoToast(t.reader.downloadingUpscaleInBackground);
  try {
    await RealSrSuperResolution.downloadModel();
    return true;
  } catch (e) {
    showInfoToast(t.reader.modelDownloadFailed(error: e));
    return false;
  }
}

/// 在线图源的超分入口：本书启停与选中状态，没有逐页状态。
///
/// 与本地入口使用同一套 48dp 按钮，开着 = `secondaryContainer`，
/// 关着 = `surfaceContainerHigh`；文字仍然按 [superResolutionShowsLabel] 让位。
/// 状态之所以只有「开/关」：在线那条路的超分发生在取图/解码层，
/// 呈现器不在场，问不出「这一页跑到哪一步」。
class ReaderOnlineUpscaleChip extends StatefulWidget {
  const ReaderOnlineUpscaleChip({
    super.key,
    this.availableWidth = double.infinity,
  });

  final double availableWidth;

  @override
  State<ReaderOnlineUpscaleChip> createState() =>
      _ReaderOnlineUpscaleChipState();
}

class _ReaderOnlineUpscaleChipState extends State<ReaderOnlineUpscaleChip> {
  /// null = 还在读设置（这一帧不画，免得开关先弹一下再翻）。
  bool? _bookEnabled;

  /// 全局总闸：只进 tooltip（这颗开关拨的是**本书**，不是它）。
  bool _globalEnabled = false;

  /// 悬停要说清的另外两件事：模型、生效阈值。它们只能从设置里读 ——
  /// 在线这一路没有呈现器，问不出「这一页跑到哪一步」。
  bool _modelReady = false;
  String _thresholdLabel = '';

  @override
  void initState() {
    super.initState();
    _load();
    // 面板里拨了同一条（或全局变了）都要跟着刷新，否则两颗控件会各说各话。
    RealSrBookScope.changes.addListener(_onScopeChanged);
  }

  @override
  void dispose() {
    RealSrBookScope.changes.removeListener(_onScopeChanged);
    super.dispose();
  }

  void _onScopeChanged() {
    if (mounted) unawaited(_load());
  }

  /// 这本书的身份：在线书 = `插件id:漫画id`。拿不到就是 null（按全局走）。
  String? get _bookKey => RealSrBookScope.keyFor(
    from: ReaderSessionCoordinator.instance.from,
    comicId: ReaderSessionCoordinator.instance.comicId,
  );

  Future<void> _load() async {
    // **先只读 SharedPreferences**：这颗芯片不该等 Rust 那一趟可用性检查才肯出现
    // —— 那条调用在测试里根本不返回，等于「超分显示又没了」；在真机上它也要跨一次 FFI。
    var book = false;
    var global = false;
    try {
      book = await RealSrBookScope.enabledFor(_bookKey);
      global = await RealSrSettings.loadAutoUpscale();
    } catch (_) {
      // 读不到就按「关着」画：芯片不该把顶栏炸掉。
    }
    if (mounted) {
      setState(() {
        _bookEnabled = book;
        _globalEnabled = global;
      });
    }

    // 悬停信息随后补。读不到就少写那两行，不影响芯片本身。
    try {
      final ready = await RealSrSuperResolution.isAvailable;
      final threshold = RealSrSettings.effectiveThreshold(
        await RealSrSettings.loadResolutionThreshold(),
      ).label;
      if (mounted) {
        setState(() {
          _modelReady = ready;
          _thresholdLabel = threshold;
        });
      }
    } catch (_) {}
  }

  String get _tooltip => [
    t.reader.onlineUpscaleAtFetchLayer,
    t.reader.thisBookState(
      state: _bookEnabled == true ? t.reader.stateOn : t.reader.stateOff,
    ),
    t.reader.globalDefaultState(
      state: _globalEnabled ? t.reader.stateOn : t.reader.stateOff,
    ),
    t.reader.modelState(
      state: _modelReady
          ? t.reader.stateDownloaded
          : t.reader.stateNotDownloadedAsk,
    ),
    if (_thresholdLabel.isNotEmpty)
      t.reader.activeThreshold(value: _thresholdLabel),
  ].join('\n');

  Future<void> _toggle(bool value) async {
    if (value && !await ensureSuperResolutionModel(context)) return;
    await RealSrBookScope.save(_bookKey, value);
    if (!mounted) return;
    setState(() => _bookEnabled = value);
    showInfoToast(
      value ? t.reader.bookUpscaleOnFetch : t.reader.bookUpscaleOff,
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = _bookEnabled;
    if (value == null) return const SizedBox.shrink();
    return ReaderToolbarFeatureButton(
      icon: AppGlyphs.sparkle,
      label: '超分',
      shape: ExpressiveButtonShape.cookie4Sided,
      tooltip: _tooltip,
      selected: value,
      onPressed: () => _toggle(!value),
    );
  }
}
