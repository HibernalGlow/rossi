import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/reader/online_translated_page_surface.dart';
import 'package:zephyr/reader/online_translated_page_track.dart';
import 'package:zephyr/reader/translated_page_controller.dart';
import 'package:zephyr/reader/translated_page_status.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/widgets/toast.dart';

/// 顶栏上给**在线图源**用的「这一页译不译」芯片。
///
/// # 为什么不复用 [ReaderTranslatedPageChip] 那颗
///
/// 那颗的成立前提是「本地会话 + GPU 呈现器」，两样在线都没有；把它的判据改成
/// 「有就用呈现器，没有就退回译文轨」会让一颗芯片同时管两条渲染路，
/// 而那两条路上「画面换了没有」的证据来源根本不是一回事。
/// 所以这里单独一颗，与那颗互斥：本地会话在的时候自己不画。
///
/// 状态表**不另起一套** —— 直接走 [translatedPageChipState]，与那颗同一份判据。
class ReaderOnlineTranslatedPageChip extends StatelessWidget {
  const ReaderOnlineTranslatedPageChip({
    super.key,
    this.availableWidth = double.infinity,
  });

  final double availableWidth;

  /// 两个适配器都是无状态的壳（真状态在译文轨里），各造一份就够了。
  static final TranslatedPagePresenter _surface = OnlineTranslatedPageSurface();
  static final OnlineTranslatedPageInput _input = OnlineTranslatedPageInput();

  @override
  Widget build(BuildContext context) {
    if (!ocrSupportedHere) return const SizedBox.shrink();
    // 先订阅，再判「这是不是一页在线漫画」。反过来写会漏：作用域是正文第一帧
    // 渲染时才绑上的，那颗提前 return 的芯片当时根本没挂监听，
    // 于是「有在线页了」这一下没人告诉它 —— 芯片要等到顶栏因为别的原因重建才出现。
    final track = OnlineTranslatedPageTrack.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([TranslatedPageController.instance, track]),
      builder: (context, _) {
        // 本地那一路有自己的芯片（它注的是 GPU 增强图轨），这里让开，
        // 免得同一页顶上出现两颗都说得出「译文页」的芯片。
        if (LocalReadSession.instance.currentSource != null) {
          return const SizedBox.shrink();
        }
        if (!track.hasScope) return const SizedBox.shrink();
        final controller = TranslatedPageController.instance;
        final index = context.select<ReaderCubit, int>(
          (c) => c.state.currentSlot,
        );
        final state = translatedPageChipState(
          phase: controller.phase,
          phaseIndex: controller.index,
          index: index,
          owned: controller.isOwned(index),
        );
        return _build(context, controller, index, state, track);
      },
    );
  }

  Widget _build(
    BuildContext context,
    TranslatedPageController controller,
    int index,
    TranslatedPageChipState state,
    OnlineTranslatedPageTrack track,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (Color bg, Color fg) = switch (state) {
      TranslatedPageChipState.failed => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      TranslatedPageChipState.showing => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _ => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
    };
    final showLabel = availableWidth >= 620;
    // 这一页还没解析出磁盘路径 —— 只有正文还没画过它才会这样（路径是显示端
    // 上报的）。这时点它只会得到一句「取不到图像字节」，不如当场说清楚。
    final inputReady = track.sourcePathFor(index) != null;

    return Tooltip(
      message: switch (state) {
        TranslatedPageChipState.failed => controller.lastError,
        TranslatedPageChipState.showing => t.ocr.chipOn,
        TranslatedPageChipState.building => t.ocr.building,
        _ => inputReady ? t.ocr.chipOff : '这一页还没加载出来，稍等一下再译',
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(ReaderToolbarMetrics.fullRadius),
        onTap: () async {
          switch (translatedPageTapFor(state)) {
            case TranslatedPageTap.wait:
              showInfoToast(t.ocr.busyToast);
              return;
            case TranslatedPageTap.toggle:
              break;
          }
          if (!inputReady) {
            showErrorToast('这一页还没加载出来，稍等一下再译');
            return;
          }
          final ok = await controller.toggle(
            source: _input,
            presenter: _surface,
            index: index,
          );
          if (!ok && controller.lastError.isNotEmpty) {
            showErrorToast(controller.lastError);
          }
        },
        child: Container(
          height: ReaderToolbarMetrics.chipHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(
              ReaderToolbarMetrics.fullRadius,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                switch (state) {
                  TranslatedPageChipState.building =>
                    Icons.hourglass_top_outlined,
                  _ => Icons.translate_outlined,
                },
                size: 14,
                color: fg,
              ),
              if (showLabel) ...[
                const SizedBox(width: 4),
                Text(
                  switch (state) {
                    TranslatedPageChipState.building => t.ocr.building,
                    TranslatedPageChipState.failed => t.ocr.failedShort,
                    TranslatedPageChipState.showing => t.ocr.chipOn,
                    _ => t.ocr.chipOff,
                  },
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
