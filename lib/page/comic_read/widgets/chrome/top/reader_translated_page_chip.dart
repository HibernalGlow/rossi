import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/page_source.dart';
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
      listenable: TranslatedPageController.instance,
      builder: (context, _) {
        final controller = TranslatedPageController.instance;
        final index = context.select<ReaderCubit, int>(
          (c) => c.state.currentSlot,
        );
        final owned = controller.isOwned(index);
        final busy =
            controller.phase == TranslatedPagePhase.building &&
            controller.index == index;
        final failed =
            controller.phase == TranslatedPagePhase.failed &&
            controller.index == index;
        return _build(
          context,
          controller,
          source,
          presenter,
          index,
          owned: owned,
          busy: busy,
          failed: failed,
        );
      },
    );
  }

  Widget _build(
    BuildContext context,
    TranslatedPageController controller,
    PageSource source,
    GpuPresentController presenter,
    int index, {
    required bool owned,
    required bool busy,
    required bool failed,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (Color bg, Color fg) = failed
        ? (scheme.errorContainer, scheme.onErrorContainer)
        : owned
        ? (scheme.secondaryContainer, scheme.onSecondaryContainer)
        : (scheme.surfaceContainerHigh, scheme.onSurfaceVariant);
    final showLabel = availableWidth >= 620;

    return Tooltip(
      message: failed
          ? controller.lastError
          : owned
          ? t.ocr.chipOn
          : t.ocr.chipOff,
      child: InkWell(
        borderRadius: BorderRadius.circular(ReaderToolbarMetrics.fullRadius),
        onTap: () async {
          if (busy) {
            showInfoToast(t.ocr.busyToast);
            return;
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
                busy ? Icons.hourglass_top_outlined : Icons.translate_outlined,
                size: 14,
                color: fg,
              ),
              if (showLabel) ...[
                const SizedBox(width: 4),
                Text(
                  busy
                      ? t.ocr.building
                      : failed
                      ? t.ocr.failedShort
                      : owned
                      ? t.ocr.chipOn
                      : t.ocr.chipOff,
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
