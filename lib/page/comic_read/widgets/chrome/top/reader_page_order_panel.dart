import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_read/cubit/reader_page_order_cubit.dart';
import 'package:zephyr/page/comic_read/method/reader_page_order_apply.dart';
import 'package:zephyr/page/comic_read/model/reader_page_order.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/page/comic_read/widgets/picker/reader_page_order_sheet.dart';
import 'package:zephyr/widgets/toast.dart';

/// 排序档位对应的图标与说明。
///
/// 图标与中文名都放这里对外暴露：主行那颗按钮要按当前档位换图标，
/// 让面板自己藏一份就会出现「主行与面板各说各的」那种不一致。
const Map<ReaderPageOrderMode, Glyph> kReaderPageOrderIcons = {
  ReaderPageOrderMode.source: AppGlyphs.layoutList,
  ReaderPageOrderMode.reverse: AppGlyphs.arrowDown,
  ReaderPageOrderMode.natural: AppGlyphs.sortAlpha,
  ReaderPageOrderMode.custom: AppGlyphs.dragHandle,
};

const Map<ReaderPageOrderMode, String> kReaderPageOrderLabels = {
  ReaderPageOrderMode.source: '图源顺序（插件/归档给的顺序）',
  ReaderPageOrderMode.reverse: '倒序（本章页表整个反过来）',
  ReaderPageOrderMode.natural: '文件名自然序（page2 排在 page10 前）',
  ReaderPageOrderMode.custom: '手动顺序（在页面列表里拖）',
};

/// 顶栏「页面排序」面板。
///
/// 排的是**章节内**的页序，不是章节顺序：章节队列由无缝拼接那一套管，
/// 已经有它自己的顺序与过渡卡片，这里再动就会和过渡卡片互相打乱。
class ReaderPageOrderPanel extends StatelessWidget {
  const ReaderPageOrderPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select(
      (GlobalSettingCubit c) => c.state.readSetting.readerPageOrderMode,
    );
    // 订阅排列本身而不是「有没有」：手动编辑存完要当场点亮那颗编辑入口。
    final customCount = context.select(
      (ReaderPageOrderCubit c) => c.state.customOrders.length,
    );
    final epInfo = currentReaderChapterEpInfo(context: context);
    final hasCustomForChapter =
        epInfo != null &&
        context.read<ReaderPageOrderCubit>().hasCustomOrder(epInfo.epId);

    return ReaderToolbarPanelRow(
      children: [
        const ReaderToolbarLabel('页序'),
        ReaderToolbarPill(
          children: [
            for (final option in ReaderPageOrderMode.values)
              ReaderToolbarIconButton(
                icon: kReaderPageOrderIcons[option]!,
                tooltip: kReaderPageOrderLabels[option]!,
                selected: mode == option,
                onPressed: () => _apply(context, option),
              ),
          ],
        ),
        const ReaderToolbarSeparator(),
        ReaderToolbarIconButton(
          icon: AppGlyphs.edit,
          tooltip: hasCustomForChapter
              ? '编辑本章的手动顺序'
              : '打开本章页面列表并拖出顺序（以当前顺序为起点）',
          selected: hasCustomForChapter,
          onPressed: () => _editCustomOrder(context),
        ),
        // 清除只对本章有意义，所以 customCount 只用来决定这一行要不要参与布局：
        // 一章都没排过时按下去必然无事发生，那颗按钮就只会是一颗装饰品。
        if (customCount > 0) ...[
          ReaderToolbarIconButton(
            icon: AppGlyphs.clearAll,
            tooltip: epInfo == null || !hasCustomForChapter
                ? '本章没有手动顺序可清除'
                : '清除本章的手动顺序',
            enabled: epInfo != null && hasCustomForChapter,
            onPressed: () {
              final chapter = epInfo;
              if (chapter == null) return;
              context.read<ReaderPageOrderCubit>().clearCustomOrder(
                chapter.epId,
              );
              // 清完停在「图源顺序」而不是停在 customs：档位还指着 custom 而排列没了，
              // 画面会退回原样，而那颗高亮的却是「手动」—— 说的是两件事。
              if (mode == ReaderPageOrderMode.custom) {
                applyReaderPageOrder(
                  context: context,
                  mode: ReaderPageOrderMode.source,
                );
              } else {
                showInfoToast('已清除本章的手动顺序');
              }
            },
          ),
        ],
      ],
    );
  }

  Future<void> _apply(BuildContext context, ReaderPageOrderMode option) async {
    if (option == ReaderPageOrderMode.custom) {
      final cubit = context.read<ReaderPageOrderCubit>();
      final epInfo = currentReaderChapterEpInfo(context: context);
      if (epInfo == null) return;
      // 手动那一档必须真有一份排列才谈得上「选中」：没有排列时它是原样顺序，
      // 点亮它只会让顶栏和画面各说一套。
      if (!cubit.hasCustomOrder(epInfo.epId)) {
        await _editCustomOrder(context);
        return;
      }
    }
    await applyReaderPageOrder(context: context, mode: option);
  }

  Future<void> _editCustomOrder(BuildContext context) async {
    final epInfo = currentReaderChapterEpInfo(context: context);
    if (epInfo == null) return;
    final order = await showReaderPageOrderSheet(
      context: context,
      epInfo: epInfo,
    );
    if (order == null || !context.mounted) return;
    await applyReaderPageOrder(
      context: context,
      mode: ReaderPageOrderMode.custom,
      customOrder: order,
    );
  }
}
