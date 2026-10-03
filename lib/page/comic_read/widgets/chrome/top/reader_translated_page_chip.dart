import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/reader/translated_page_status.dart';
import 'package:zephyr/reader/translated_page_controller.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/widgets/toast.dart';

/// 顶栏上的「这一页译不译」芯片。
///
/// # 为什么是**每页**一颗，而不是一个全局开关
/// 成品页要十几秒（检测 + 识别 + 擦字 + 一次翻译请求 + 排版），全局开关等于
/// 「往后每一页都得等」；而且用户常常只想看清某一格说了什么。
/// 所以这里只管当前页：翻到下一页，状态自然回到「译」。
///
/// # 为什么放在呈现器的增强图轨上，而不是在图上再盖一层
/// 见 `TranslatedPageController` 的注释：阅读器在桌面端由 native 上屏，
/// Flutter 侧再画一张 `Image.file` 会绕开旋转 / 双页 / 页宽适配。
///
/// 只在**本地来源 + 桌面平台**出现：在线图源没有呈现器，
/// Android / iOS 是 ADR-0018 §决定 6 的排除项。
class ReaderTranslatedPageChip extends StatelessWidget {
  const ReaderTranslatedPageChip({
    super.key,
    this.availableWidth = double.infinity,
  });

  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    if (!ocrSupportedHere) return const SizedBox.shrink();
    final source = LocalReadSession.instance.currentSource;
    final presenter = LocalReadSession.instance.presenter;
    if (source == null || presenter == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      // 两边都要听：控制器给「归属与阶段」，呈现器给「原图对比旁路」。
      // 少了呈现器这一路，切回超分的那一刻芯片会一直停在「原图对比中」，
      // 直到用户翻页或再点一次才改口 —— 而画面其实早就换成译文了。
      listenable: Listenable.merge([
        TranslatedPageController.instance,
        presenter,
      ]),
      builder: (context, _) {
        final controller = TranslatedPageController.instance;
        final index = context.select<ReaderCubit, int>(
          (c) => c.state.currentSlot,
        );
        final state = translatedPageChipState(
          phase: controller.phase,
          phaseIndex: controller.index,
          index: index,
          owned: controller.isOwned(index),
          degraded: controller.isDegraded(index),
          bypassed: presenter.isOriginalPreview,
        );
        return _build(context, controller, source, presenter, index, state);
      },
    );
  }

  Widget _build(
    BuildContext context,
    TranslatedPageController controller,
    PageSource source,
    GpuPresentController presenter,
    int index,
    TranslatedPageChipState state,
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
      // 降级产物看着像成功，所以给它一个**不同**的颜色而不是复用 showing 的强调色。
      TranslatedPageChipState.showingOriginal => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      // 被原图对比挡住：既不能用失败色（没失败），也不能用 showing 的强调色
      // （画面上此刻就是原图）。给它中性色 + 一个「看不见」的图标。
      TranslatedPageChipState.blockedByOriginalPreview => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      _ => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
    };
    final showLabel = availableWidth >= 620;

    return Tooltip(
      message: switch (state) {
        TranslatedPageChipState.failed => controller.lastError,
        TranslatedPageChipState.showing => t.ocr.chipOn,
        TranslatedPageChipState.showingOriginal => t.ocr.degradedHint,
        TranslatedPageChipState.building => t.ocr.building,
        // 这一态的短语是中文原文：`ocr` 那段 i18n 里还没有对应键，而同一条链路上
        // 其余诊断文案（[TranslatedPageController.lastError]、超分的状态表）
        // 本来也是原文。要补 i18n 就在 `ocr` 段加两个键，别在这里另起一套。
        TranslatedPageChipState.blockedByOriginalPreview =>
          '译文已经生成并注入，正被「对比原图」挡着：切回超分就显示译文',
        _ => t.ocr.chipOff,
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
          final ok = await controller.toggle(
            source: source,
            presenter: TranslatedPagePresenter.of(presenter),
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
                  // 「注进去了但这会儿看不见」——窄屏上不显示文字时，图标是这一态
                  // 唯一和「译」「译文页」区分得开的东西。
                  TranslatedPageChipState.blockedByOriginalPreview =>
                    Icons.visibility_off_outlined,
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
                    TranslatedPageChipState.showingOriginal =>
                      t.ocr.chipDegraded,
                    TranslatedPageChipState.blockedByOriginalPreview =>
                      '原图对比中',
                    TranslatedPageChipState.off => t.ocr.chipOff,
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
