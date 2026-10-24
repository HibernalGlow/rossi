import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';

/// 移动端**单卡全屏宿主**：「同面板、两种宿主」里的第二种宿主。
///
/// 桌面上这张卡住在泳道面板 / 四边栏里；手机上它整页摊开 —— 内容一个字不重写，
/// 还是 [WorkspaceCardRegistry] 里那条 `builder`，只是 chrome 换成
/// `standalone: true`（不画折叠外壳与固定高度，卡自己就是整页主体，
/// 与桌面独占面板的直铺口径一致，见 `PanelCardList` 的 standalone 分支）。
///
/// 布局上刻意**不读也不写** [WorkspaceBoardLayout] 的用户记账：那份数据
/// 描述的是泳道几何（左右、宽度、折叠），在整页形态里没有意义；
/// 展开态是页面的局部状态，进出页面回到默认展开。
@RoutePage()
class WorkspaceMobileCardPage extends StatefulWidget {
  const WorkspaceMobileCardPage({super.key, required this.cardId});

  /// 要整页承载的卡片 id（`WorkspaceCardRegistry` 的常量之一）。
  final String cardId;

  @override
  State<WorkspaceMobileCardPage> createState() =>
      _WorkspaceMobileCardPageState();
}

class _WorkspaceMobileCardPageState extends State<WorkspaceMobileCardPage> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final def = WorkspaceCardRegistry.I.find(widget.cardId);
    final body = def == null
        ? Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              t.workspace.mobileCardMissing,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        : Builder(
            builder: (context) {
              final supported = def.supportedHere?.call() ?? true;
              if (!supported) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    def.unsupportedHint ?? t.workspace.mobileCardUnsupported,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final layout = WorkspaceCardRegistry.I.effectiveLayout(
                def,
                const WorkspaceBoardLayout(),
              );
              return ListView(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                children: [
                  def.builder(
                    context,
                    WorkspaceCardChrome(
                      expanded: _expanded,
                      onToggle: () => setState(() => _expanded = !_expanded),
                      index: 0,
                      count: 1,
                      standalone: true,
                      widthSpan: layout.widthSpan ?? def.defaultWidthSpan,
                      heightSpan: layout.heightSpan ?? def.defaultHeightSpan,
                    ),
                  ),
                ],
              );
            },
          );

    return Scaffold(
      appBar: AppBar(title: Text(def?.title ?? t.workspace.workspaceHome)),
      body: body,
    );
  }
}
