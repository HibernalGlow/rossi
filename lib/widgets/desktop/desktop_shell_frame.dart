import 'package:material_ui/material_ui.dart';
import 'package:zephyr/service/reader/reader_desktop_fullscreen_service.dart';
import 'package:zephyr/widgets/desktop/custom_title_bar.dart';

/// 自制标题栏在窗口里的摆放方式。
enum DesktopTitleBarPlacement {
  /// **整条不建**：全屏时那 40px 要还给内容。
  hidden,

  /// **占一行**：标题栏在正常流里，内容从它下面开始（改造前的样子）。
  reserved,

  /// **浮在最上层**：标题栏不占位，内容顶到窗口顶部，标题栏只把应用名与
  /// 窗口按钮浮在画面上（`透明标题栏` 开关打开时的样子）。
  overlay,
}

/// 「全屏 + 透明标题栏（+ 摆放方式）」→ 这一条栏该怎么摆。
///
/// 抽成纯函数是为了让真值表全部组合都能在 `flutter test` 里断言 ——
/// 起整个 app 去数矩形太贵，而这三种摆放的差别全在这几个 bool 里。
///
/// **全屏优先于一切**：窗口已经全屏时，任何档位都不该再画这一条
/// （要透明就干脆不建，而不是留一条看不见却吃鼠标的东西）。
///
/// **「独立行」与「实色一行」是同一种摆放**（`reserved`）：差别只在栏自己
/// 画不画底色，不在这 40px 归谁 —— 所以摆放判定里只有 `fused` 一个新变量。
/// `fused` 只在 `transparent` 打开时生效：开关关着时它是死数据，
/// 就算误传 true 也退回标准那一行（独立行是默认档，不能被它悄悄改掉）。
DesktopTitleBarPlacement resolveDesktopTitleBarPlacement({
  required bool isFullscreen,
  required bool transparent,
  bool fused = false,
}) {
  if (isFullscreen) return DesktopTitleBarPlacement.hidden;
  if (transparent && fused) return DesktopTitleBarPlacement.overlay;
  return DesktopTitleBarPlacement.reserved;
}

/// 桌面外壳：自制标题栏 + 内容。
///
/// **窗口全屏时标题栏整条不建**（不是「透明 / 隐藏但仍占 40px」，是根本
/// 不占位）—— 全屏的意义就是把这一行还给内容。
/// 全屏状态来自 `ReaderDesktopFullscreenService.fullscreenNotifier`，那个状态
/// 由**窗口自己的全屏事件**驱动（见该服务的文档），所以无论是按应用里的
/// 全屏按钮、⌃⌘F 还是视图菜单，这里都会让位；不再出现「窗口已经全屏、
/// 顶上还挂着一条写着应用名的标题栏」。
///
/// [transparentTitleBar] 打开时透明档生效，摆放再分两档（JHenTai 桌面端
/// 两种形态的口径）：
/// - **独立行**（默认，[titleBarFused] = false）：栏仍占自己那 40px，
///   只是不画底色 —— 页面背景从它底下连上来，看起来和内容融为一体；
/// - **融合浮层**（[titleBarFused] = true）：内容顶到窗口顶部，栏变成
///   一层没有底色的浮层叠在画面上。
/// 代价写在设置项副标题里：文字与窗口按钮浮在画面之上，画面颜色浅时
/// 可能不易看清。
class DesktopShellFrame extends StatelessWidget {
  const DesktopShellFrame({
    super.key,
    required this.child,
    this.transparentTitleBar = false,
    this.titleBarFused = false,
  });

  /// 标题栏下面的内容（导航栈）。
  final Widget child;

  /// 「透明标题栏」开关（`GlobalSettingState.transparentDesktopTitleBar`）。
  final bool transparentTitleBar;

  /// 透明档的摆放方式：false = 独立行（默认），true = 融合浮层
  /// （`GlobalSettingState.transparentTitleBarFused`）。
  final bool titleBarFused;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable:
          ReaderDesktopFullscreenService.instance.fullscreenNotifier,
      builder: (context, isFullscreen, _) {
        final placement = resolveDesktopTitleBarPlacement(
          isFullscreen: isFullscreen,
          transparent: transparentTitleBar,
          fused: titleBarFused,
        );

        switch (placement) {
          case DesktopTitleBarPlacement.hidden:
            return child;
          case DesktopTitleBarPlacement.reserved:
            return Column(
              children: [
                // 独立行：透明开关打开时这一行不画底色，页面背景从底下连上来；
                // 关着时照旧是主题 surface 的实色一行。
                CustomTitleBar(transparent: transparentTitleBar),
                Expanded(child: child),
              ],
            );
          case DesktopTitleBarPlacement.overlay:
            return Stack(
              fit: StackFit.expand,
              children: [
                child,
                // 只铺顶部那 40px：内容照旧满窗，标题栏自己不带底色。
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: CustomTitleBar(transparent: true),
                ),
              ],
            );
        }
      },
    );
  }
}
