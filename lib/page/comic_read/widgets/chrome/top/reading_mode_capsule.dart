import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';

/// 阅读模式胶囊切换器 (条漫 / 单页横向)。
///
/// 只管**版式**（竖向连续滚动 还是 横向按页翻），不再管方向：方向是顶栏
/// [ReadingDirectionToggle] 的唯一职责。以前这里挂着 →/← 两格，与那颗按钮
/// 写同一个 `readMode` 1↔2，而且切完会把阅读位置清零 —— 同一个功能两个入口、
/// 行为还不一样。所以两格并成一格：从条漫切到单页时进入缺省方向（右开），
/// 要左开再点一下方向按钮。
///
/// 外壳与里面的两颗都用顶栏那一套度量（[ReaderToolbarPill] +
/// [ReaderToolbarIconButton]），这样它与主行其余控件的边长、状态层完全一致。
class ReadingModeCapsule extends StatelessWidget {
  final int currentMode;
  final ValueChanged<int> onModeChanged;

  const ReadingModeCapsule({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ReaderToolbarPill(
      children: [
        ReaderToolbarIconButton(
          icon: Icons.view_day_outlined,
          tooltip: t.reader.webtoon,
          selected: currentMode == kReadModeColumn,
          onPressed: () {
            if (currentMode != kReadModeColumn) {
              onModeChanged(kReadModeColumn);
            }
          },
        ),
        ReaderToolbarIconButton(
          icon: Icons.menu_book_rounded,
          tooltip: t.reader.singlePageRow,
          selected: currentMode != kReadModeColumn,
          onPressed: () {
            if (currentMode == kReadModeColumn) {
              onModeChanged(kReadModeRowLtr);
            }
          },
        ),
      ],
    );
  }
}

/// 单/双页模式快速切换芯片。
class DoublePageToggle extends StatelessWidget {
  final bool isDoublePage;
  final ValueChanged<bool> onToggle;

  /// 宽档才写「单页/双页」，中档收成图标 —— 主行的宽度预算就这么多。
  final bool showLabel;

  const DoublePageToggle({
    super.key,
    required this.isDoublePage,
    required this.onToggle,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return ReaderToolbarToggleChip(
      icon: isDoublePage
          ? Icons.auto_stories_rounded
          : Icons.crop_portrait_rounded,
      label: showLabel ? (isDoublePage ? '双页' : '单页') : null,
      tooltip: isDoublePage ? '双页模式（点击切为单页）' : '单页模式（点击切为双页）',
      selected: isDoublePage,
      onTap: () => onToggle(!isDoublePage),
    );
  }
}

/// 顶栏「阅读方向」切换芯片（neo 的左开/右开独立入口，也是本仓**唯一**的方向入口）。
///
/// 单击在右开（[kReadModeRowLtr]，下一页在右）⇄ 左开（[kReadModeRowRtl]，下一页
/// 在左）之间切换，**不动阅读位置** —— 两个模式同属 `RowModeWidget`，槽位含义不变，
/// 只是翻页语义反过来。旧实现（设置页里切方向跟着 `changePageIndex(0)`）会把位置
/// 清零跳回第一页。
///
/// 条漫（[kReadModeColumn]）没有左右翻页方向：芯片置灰（**置灰不隐藏** —— 隐藏等于
/// 让人以为没这功能）。整颗芯片由全局设置 `readingDirectionToggle` 控制，
/// 关掉后顶栏不再出现（用户约定：所有功能都要有开关、可随时关闭）。
class ReadingDirectionToggle extends StatelessWidget {
  final int currentMode;
  final ValueChanged<int> onModeChanged;
  final bool showLabel;

  const ReadingDirectionToggle({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    // 「左开」= 下一页在左 = RTL 推进；「右开」= 下一页在右 = LTR 推进。
    final isLeftOpen = currentMode == kReadModeRowRtl;
    final isHorizontal =
        currentMode == kReadModeRowLtr || currentMode == kReadModeRowRtl;

    return ReaderToolbarToggleChip(
      icon: isLeftOpen ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
      label: showLabel ? t.reader.readingDirectionToggle : null,
      tooltip: !isHorizontal
          ? t.reader.readingDirectionToggleDisabled
          : isLeftOpen
          ? t.reader.readingDirectionToggleLeftOpen
          : t.reader.readingDirectionToggleRightOpen,
      // 方向本身不是「开/关」，是二选一的当前值 —— 所以它不亮 `secondaryContainer`，
      // 只借用芯片的外形；置灰才是这里要表达的状态。
      enabled: isHorizontal,
      onTap: isHorizontal
          ? () => onModeChanged(isLeftOpen ? kReadModeRowLtr : kReadModeRowRtl)
          : null,
    );
  }
}

/// 窄档的阅读模式循环切换按钮（条漫 → 右开 → 左开 → 条漫）。
class CompactReadingModeButton extends StatelessWidget {
  final int currentMode;
  final ValueChanged<int> onModeChanged;

  const CompactReadingModeButton({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    String tooltip;
    int nextMode;

    if (currentMode == kReadModeColumn) {
      icon = Icons.view_day_outlined;
      tooltip =
          '${t.reader.webtoon}（点击切为${t.reader.readingDirectionRightOpen}）';
      nextMode = kReadModeRowLtr;
    } else if (currentMode == kReadModeRowLtr) {
      icon = Icons.arrow_forward_rounded;
      tooltip =
          '${t.reader.readingDirectionRightOpen}（点击切为${t.reader.readingDirectionLeftOpen}）';
      nextMode = kReadModeRowRtl;
    } else {
      icon = Icons.arrow_back_rounded;
      tooltip = '${t.reader.readingDirectionLeftOpen}（点击切为${t.reader.webtoon}）';
      nextMode = kReadModeColumn;
    }

    return ReaderToolbarIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: () => onModeChanged(nextMode),
    );
  }
}
