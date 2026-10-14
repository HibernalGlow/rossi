import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:scrollview_observer/scrollview_observer.dart';
import 'package:zephyr/page/setting/common/setting_entry.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';

/// 「把某个设置项滚进视口」的请求入口。
///
/// 走全局 notifier 而不是给每个设置页挂一个控制器字段：上游的设置页就是
/// `ListView(children: [...])`，挂点越少，将来跟 upstream 融合时越不容易打架。
/// 发起方只写 id，页面自己认领。
final ValueNotifier<String?> settingFocusRequest = ValueNotifier<String?>(null);

/// 带 id 的设置页列表：渲染 [children]，并能按 id 把其中一项滚进视口。
///
/// index 一律从 [children] 现算，所以「有 id 的行」与「拿去渲染的列表」
/// 天然是同一份，不需要另外维护平行编号表。
class SettingEntryList extends StatefulWidget {
  const SettingEntryList({
    super.key,
    required this.children,
    this.padding = kSettingPagePadding,
  });

  final List<Widget> children;

  /// 设置页统一的页边距；这一页的可滚动容器是自己建的，所以由组件持有默认值。
  final EdgeInsets padding;

  @override
  State<SettingEntryList> createState() => _SettingEntryListState();
}

class _SettingEntryListState extends State<SettingEntryList> {
  final ScrollController _scrollController = ScrollController();
  late final ListObserverController _observer = ListObserverController(
    controller: _scrollController,
  );

  @override
  void initState() {
    super.initState();
    settingFocusRequest.addListener(_maybeFocus);
    // 路由刚推进来时请求可能已经挂在 notifier 上，那一帧就得认领一次。
    SchedulerBinding.instance.addPostFrameCallback((_) => _maybeFocus());
  }

  @override
  void dispose() {
    settingFocusRequest.removeListener(_maybeFocus);
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeFocus() {
    final id = settingFocusRequest.value;
    if (id == null || !mounted) return;

    // 只认领属于自己这一页的 id；不是就留着，否则「先开乙页、再请求甲页的项」
    // 会被乙页静默吃掉。
    final index = indexOfSettingEntry(widget.children, id);
    if (index < 0) return;
    settingFocusRequest.value = null;

    unawaited(_focus(id, index));
  }

  Future<void> _focus(String id, int index) async {
    // 行在分组卡里时，卡是一个下标、卡里的行已经跟着卡建出来了，直接挪进视口。
    // 这种结构**不能**交给包的按下标收敛：卡比视口高，包会在「已经落在这个下标」
    // 上反复找位置，Future 不完成，后面的补挪也就永远轮不到（实测行纹丝不动）。
    final rowIsDirectChild = widget.children[index].key is SettingEntryKey;
    if (!rowIsDirectChild) {
      final built = mounted ? _findEntry(context, id) : null;
      if (built != null) {
        await _reveal(built);
        return;
      }
    }

    // 不给 isFixedHeight：设置页行高本来就不一致（章节标题、有无副标题、
    // 下拉行），此时包会先在目标附近逐步滚动再定位，代价是一段收敛动画。
    await _observer.animateTo(
      index: index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );

    // 只有目标在卡里时才补挪：卡是刚落地的，行这才被建出来。
    if (rowIsDirectChild) return;
    final self = context;
    if (!self.mounted) return;
    final row = _findEntry(self, id);
    if (row != null) await _reveal(row);
  }

  Future<void> _reveal(BuildContext target) {
    return Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0,
    );
  }

  static BuildContext? _findEntry(BuildContext root, String id) {
    final key = SettingEntryKey(id);
    BuildContext? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key == key) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    (root as Element).visitChildren(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    return ListViewObserver(
      controller: _observer,
      child: ListView(
        controller: _scrollController,
        padding: widget.padding,
        children: widget.children,
      ),
    );
  }
}
