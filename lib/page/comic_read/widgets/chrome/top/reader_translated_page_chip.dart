import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_feature_button.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/reader/translated_page_status.dart';
import 'package:zephyr/reader/translated_page_controller.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';

/// 顶栏上的「这一页译不译」芯片。
///
/// # 为什么是**每页**一颗，而不是一个全局开关
/// 成品页要十几秒（检测 + 识别 + 擦字 + 一次翻译请求 + 排版），全局开关等于
/// 「往后每一页都得等」；而且用户常常只想看清某一格说了什么。
/// 所以这里只管当前页：翻到下一页，状态自然回到「译」。
///
/// # 「译」的字是怎么上屏的（两档，芯片要说得清是哪一档）
/// 烘焙：擦字 + 画字烤成一张 PNG，注进呈现器的增强图轨 —— 它占掉这一页唯一的像素，
/// 所以超分为它让路。叠层：底图照旧（原图或超分产物），中文由 `TranslatedPageOverlay`
/// 盖在底图上，不是烤进像素的。（占不换轨由控制器的 overlayNeedsBase 决定：今天恒占，
/// 因为底必须是擦干净的字底 —— 量数见 ADR-0018 §4。）
/// 哪一档生效由 `TranslatedPageDisplayMode` 决定，而**这一页实际走的是哪一档**问控制器
/// （`overlayLabelFor`）—— 判据见 [translatedPageDisplayOf]。
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
    // 这一页的字是叠上去的还是烤进像素的 —— 与叠层画的是同一本账（见 [translatedPageDisplayOf]）。
    final display = translatedPageDisplayOf(
      overlayLabel: controller.overlayLabelFor(index),
    );
    final onLabel = display == TranslatedPageDisplay.overlay
        ? t.ocr.chipOnOverlay
        : t.ocr.chipOn;
    return ReaderToolbarFeatureButton(
      shape: ExpressiveButtonShape.slanted,
      tooltip: switch (state) {
        TranslatedPageChipState.failed => controller.lastError,
        TranslatedPageChipState.showing => onLabel,
        TranslatedPageChipState.building => t.ocr.building,
        // 这一态的短语是中文原文：`ocr` 那段 i18n 里还没有对应键，而同一条链路上
        // 其余诊断文案（[TranslatedPageController.lastError]、超分的状态表）
        // 本来也是原文。要补 i18n 就在 `ocr` 段加两个键，别在这里另起一套。
        TranslatedPageChipState.blockedByOriginalPreview =>
          t.reader.translationHiddenByCompare,
        _ => t.reader.tabTranslate,
      },
      onPressed: () async {
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
      icon: switch (state) {
        TranslatedPageChipState.blockedByOriginalPreview => AppGlyphs.eyeOff,
        TranslatedPageChipState.showing
            when display == TranslatedPageDisplay.overlay =>
          AppGlyphs.layers,
        TranslatedPageChipState.failed => AppGlyphs.error,
        _ => AppGlyphs.translate,
      },
      label: switch (state) {
        TranslatedPageChipState.building => t.ocr.building,
        TranslatedPageChipState.failed => t.ocr.failedShort,
        TranslatedPageChipState.showing => onLabel,
        TranslatedPageChipState.blockedByOriginalPreview =>
          t.reader.comparingOriginal,
        _ => t.reader.tabTranslate,
      },
      selected: state == TranslatedPageChipState.showing,
      busy: state == TranslatedPageChipState.building,
      failed: state == TranslatedPageChipState.failed,
      showLabel: availableWidth >= 720 || state == TranslatedPageChipState.off,
    );
  }
}
