import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/model/workspace_reveal_zones.dart';
import 'package:zephyr/workspace/service/workspace_layout_bridge.dart';

/// 「设置 → 布局」：工作台走哪条呈现、焦点与独占什么时候响应、
/// 以及**悬停唤出区**那块可以拖的画布。
///
/// 复刻的是 neoview 的 `BoardLayoutSettingsCard`（「泳道与布局」卡片的泳道页）。
/// 那里头的另一半「布局看板」（面板 / 卡片拖到左栏 / 右栏 / 隐藏）不在这一页 ——
/// 它改的是面板记账，与这里的「指针停在哪儿会把东西调出来」是两件事。
///
/// # 值存在哪儿
///
/// 全部落在 `workspace_layout.json` 的 `mode` 与 `interaction` 两块里，
/// **不进** `GlobalSettingState`。理由与 `WorkspaceLayoutSnapshot` 同源：
/// 这些是布局的偏好，与泳道宽度、面板记账是同一批要一起备份、一起重置的东西；
/// 拆到全局设置里就会有两个真相（改一处、另一处仍然生效）。
/// 读写走 [WorkspaceLayoutBridge]：工作台在场时改的是活的 cubit
/// （直接写盘会被它的去抖落盘覆盖回去），不在场时才读盘改写。
@RoutePage()
class WorkspaceLayoutSettingPage extends StatefulWidget {
  const WorkspaceLayoutSettingPage({super.key});

  @override
  State<WorkspaceLayoutSettingPage> createState() =>
      _WorkspaceLayoutSettingPageState();
}

class _WorkspaceLayoutSettingPageState
    extends State<WorkspaceLayoutSettingPage> {
  /// 读盘是异步的：读回来之前先画一个空的骨架，而不是让整页在
  /// `null` 与真值之间闪一次。
  WorkspaceLayoutSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final snapshot = await WorkspaceLayoutBridge.instance.read();
    if (!mounted) return;
    setState(() => _snapshot = snapshot);
  }

  void _write({
    WorkspaceMode? mode,
    WorkspaceInteractionSettings? interaction,
  }) {
    unawaited(
      WorkspaceLayoutBridge.instance.write(
        mode: mode,
        interaction: interaction,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return SettingPageShell(
      title: t.settings.workspaceLayout,
      child: snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: kSettingPagePadding,
              children: [
                settingSectionTitle(
                  context,
                  t.settings.laneAndLayout,
                  icon: Icons.view_column_outlined,
                ),
                _StartupViewCard(
                  mode: snapshot.mode,
                  onChanged: (mode) {
                    setState(() => _snapshot = _snapshot!.copyWithMode(mode));
                    _write(mode: mode);
                  },
                ),
                const SizedBox(height: 12),
                _FocusAndSoloCard(
                  interaction: snapshot.interaction,
                  onChanged: (next) {
                    setState(
                      () => _snapshot = _snapshot!.copyWithInteraction(next),
                    );
                    _write(interaction: next);
                  },
                ),
                const SizedBox(height: 12),
                _RevealZoneCard(
                  zones: snapshot.interaction.revealZones,
                  onChanged: (zones) {
                    final next = snapshot.interaction.copyWith(
                      revealZones: zones,
                    );
                    setState(
                      () => _snapshot = _snapshot!.copyWithInteraction(next),
                    );
                    _write(interaction: next);
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  t.settings.delayRangeHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ── 默认启动视图 ──────────────────────────────────────────────────────────

class _StartupViewCard extends StatelessWidget {
  const _StartupViewCard({required this.mode, required this.onChanged});

  final WorkspaceMode mode;
  final ValueChanged<WorkspaceMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingSectionCard(
      title: t.settings.defaultStartupView,
      icon: Icons.tab_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SegmentedPicker<WorkspaceMode>(
                value: mode,
                onChanged: onChanged,
                entries: [
                  _Segment(
                    WorkspaceMode.edges,
                    t.settings.startupViewEdges,
                    Icons.vertical_align_center,
                  ),
                  _Segment(
                    WorkspaceMode.swimlane,
                    t.settings.startupViewSwimlane,
                    Icons.view_column,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                t.settings.startupViewHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 泳道焦点与独占 ────────────────────────────────────────────────────────

class _FocusAndSoloCard extends StatelessWidget {
  const _FocusAndSoloCard({required this.interaction, required this.onChanged});

  final WorkspaceInteractionSettings interaction;
  final ValueChanged<WorkspaceInteractionSettings> onChanged;

  void _patch(WorkspaceInteractionSettings Function(WorkspaceInteractionSettings) change) =>
      onChanged(change(interaction));

  @override
  Widget build(BuildContext context) {
    return SettingSectionCard(
      title: t.settings.laneFocusSolo,
      icon: Icons.center_focus_strong_outlined,
      children: [
        ListTile(
          title: Text(t.settings.laneFocusSoloSubtitle),
          subtitle: Text(t.settings.delayRangeHint),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.filter_center_focus_outlined),
          title: Text(t.settings.readerSoloOnFocus),
          subtitle: Text(t.settings.readerSoloOnFocusSubtitle),
          thumbIcon: kSettingSwitchThumbIcon,
          value: interaction.autoSoloOnFocus,
          onChanged: (value) =>
              _patch((c) => c.copyWith(autoSoloOnFocus: value)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.view_kanban_outlined),
          title: Text(t.settings.showLaneNavigatorInSolo),
          subtitle: Text(t.settings.showLaneNavigatorInSoloSubtitle),
          thumbIcon: kSettingSwitchThumbIcon,
          value: interaction.showLaneNavigatorInSolo,
          onChanged: (value) =>
              _patch((c) => c.copyWith(showLaneNavigatorInSolo: value)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.swipe),
          title: Text(t.settings.manualScrollEnabled),
          subtitle: Text(t.settings.manualScrollEnabledSubtitle),
          thumbIcon: kSettingSwitchThumbIcon,
          value: interaction.manualScrollEnabled,
          onChanged: (value) =>
              _patch((c) => c.copyWith(manualScrollEnabled: value)),
        ),
        _DelayTile(
          icon: Icons.speed_outlined,
          title: t.settings.edgeRevealDelay,
          value: interaction.edgeRevealDelayMs,
          min: 100,
          max: 5000,
          onChanged: (value) =>
              _patch((c) => c.copyWith(edgeRevealDelayMs: value)),
        ),
        _DelayTile(
          icon: Icons.mouse_outlined,
          title: t.settings.readerHoverFocusDelay,
          subtitle: t.settings.readerHoverFocusEnable,
          value: interaction.hoverFocusDelayMs,
          min: 200,
          max: 5000,
          enabled: interaction.hoverFocusEnabled,
          switchValue: interaction.hoverFocusEnabled,
          onSwitchChanged: (value) =>
              _patch((c) => c.copyWith(hoverFocusEnabled: value)),
          onChanged: (value) =>
              _patch((c) => c.copyWith(hoverFocusDelayMs: value)),
        ),
      ],
    );
  }
}

/// 一个毫秒级的驻留延时：标题 + 数字框（+ 可选的启用开关）。
///
/// 用数字框而不是滑块是**照抄 neoview**：这些值是「180 还是 250 毫秒」这种
/// 要精确对表的手感量，滑块把 100..5000 压到 700px 上，一格就是 50ms 起步，
/// 想复现另一个候选的取值反而做不到。
class _DelayTile extends StatelessWidget {
  const _DelayTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
    this.switchValue,
    this.onSwitchChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitchChanged;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: enabled ? null : Theme.of(context).disabledColor),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onSwitchChanged != null)
            Switch(
              value: switchValue ?? false,
              thumbIcon: kSettingSwitchThumbIcon,
              onChanged: onSwitchChanged,
            ),
          _NumberBox(
            key: ValueKey('$title-$value-$enabled'),
            value: value,
            min: min,
            max: max,
            step: 50,
            enabled: enabled,
            onCommit: onChanged,
          ),
        ],
      ),
    );
  }
}

/// 整数数字框：**回车或失焦才提交**，边打字边提交会让延时这种值每敲一下
/// 就生效一次（100 → 1 → 10 → 100 中间那几步都是无意义的抖动）。
class _NumberBox extends StatefulWidget {
  const _NumberBox({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onCommit,
    this.step = 1,
    this.enabled = true,
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final bool enabled;
  final ValueChanged<int> onCommit;

  @override
  State<_NumberBox> createState() => _NumberBoxState();
}

class _NumberBoxState extends State<_NumberBox> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChanged);
  bool _editing = false;

  void _onFocusChanged() {
    final focused = _focus.hasFocus;
    if (!focused) _commit();
    if (focused != _editing) setState(() => _editing = focused);
  }

  @override
  void didUpdateWidget(covariant _NumberBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部值变了（重置、联动）时跟着改；正在打字时**不改**，
    // 否则光标会跳走、用户敲到一半的数字被覆盖。
    if (!_editing && _controller.text != '${widget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = '${widget.value}';
      return;
    }
    // 对齐到 step 再夹取：`min` 是这一项的下限（100 / 200 毫秒），
    // 而 step 是它的刻度 —— 两者不夹清楚会让「输入 137」留下一个
    // 界面上再也调不回去的取值。
    final stepped = (parsed / widget.step).round() * widget.step;
    final next = stepped < widget.min
        ? widget.min
        : (stepped > widget.max ? widget.max : stepped);
    _controller.text = '$next';
    if (next != widget.value) widget.onCommit(next);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.enabled,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(signed: false),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration(isDense: true, isCollapsed: true),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

// ── 悬停唤出区 ────────────────────────────────────────────────────────────

class _RevealZoneCard extends StatelessWidget {
  const _RevealZoneCard({required this.zones, required this.onChanged});

  final WorkspaceRevealZones zones;
  final ValueChanged<WorkspaceRevealZones> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingSectionCard(
      title: t.settings.hoverRevealZones,
      icon: Icons.dashboard_customize_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: _RevealZoneEditor(zones: zones, onChange: onChanged),
        ),
      ],
    );
  }
}

/// 每条边的颜色（与 neoview 的 cyan / amber / emerald / fuchsia-400 对齐）。
///
/// 用固定色而不是 `ColorScheme` 的槽位：这四块是**并列的四个类别**，
/// 不是「主 / 次 / 危险」那种有层级的语义色，全塞进 primary 就分不出谁是谁了。
const Map<RevealEdge, Color> _kEdgeColors = <RevealEdge, Color>{
  RevealEdge.left: Color(0xFF22D3EE),
  RevealEdge.right: Color(0xFFFBBF24),
  RevealEdge.top: Color(0xFF34D399),
  RevealEdge.bottom: Color(0xFFE879F9),
};

String _edgeLabel(RevealEdge edge) => switch (edge) {
  RevealEdge.left => t.settings.revealEdgeLeft,
  RevealEdge.right => t.settings.revealEdgeRight,
  RevealEdge.top => t.settings.revealEdgeTop,
  RevealEdge.bottom => t.settings.revealEdgeBottom,
};

/// 一次拖拽：要么在空处**画框**，要么抓住选中的那块**拖某个角**。
class _ZoneDrag {
  _ZoneDrag.draw(Offset from, Offset clientFrom)
    : corner = null,
      start = from,
      startClient = clientFrom,
      initial = null,
      moved = false;

  _ZoneDrag.resize(RevealCorner this.corner, WorkspaceRevealZone this.initial)
    : start = null,
      startClient = null,
      moved = true;

  final RevealCorner? corner;
  final Offset? start;

  /// 按下那一刻的**屏幕**坐标 —— 4px 的「这一下算不算拖动」阈值要按屏幕
  /// 距离量，按画布内的百分比距离量的话，窗口一大阈值就被放大。
  final Offset? startClient;
  final WorkspaceRevealZone? initial;
  bool moved;

  bool get isResize => corner != null;
}

class _RevealZoneEditor extends StatefulWidget {
  const _RevealZoneEditor({required this.zones, required this.onChange});

  final WorkspaceRevealZones zones;
  final ValueChanged<WorkspaceRevealZones> onChange;

  @override
  State<_RevealZoneEditor> createState() => _RevealZoneEditorState();
}

class _RevealZoneEditorState extends State<_RevealZoneEditor> {
  static const double _handleHitRadius = 12;

  /// 画布长宽比。neoview 用 `aspect-video`（16:9）—— 桌面窗口的常见比例，
  /// 画布与真实视口越像，「框在这里」越接近「指针停在这里」。
  static const double _aspect = 16 / 9;

  RevealEdge _selected = RevealEdge.left;
  bool _horizontalLinked = true;
  bool _verticalLinked = true;
  late WorkspaceRevealZones _draft = widget.zones;
  _ZoneDrag? _drag;

  @override
  void didUpdateWidget(covariant _RevealZoneEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有**外部**把值改成与本地草稿不同时才跟随（重置、撤销）。
    // 本地拖完之后父级会把同一份值传回来，那时两者相等，不动草稿。
    if (widget.zones != _draft && widget.zones != oldWidget.zones) {
      _draft = widget.zones;
    }
  }

  void _apply(WorkspaceRevealZone zone) {
    setState(() {
      _draft = updateRevealZonesWithLink(
        zones: _draft,
        edge: _selected,
        zone: zone,
        horizontalLinked: _horizontalLinked,
        verticalLinked: _verticalLinked,
      );
    });
  }

  void _commit() => widget.onChange(_draft);

  /// 指针位置 → 画布的百分比坐标（0..100）。
  Offset _percent(Offset local, Size size) => Offset(
    clampRevealPercent(local.dx / size.width * 100),
    clampRevealPercent(local.dy / size.height * 100),
  );

  /// 百分比坐标 → 画布上的像素点。
  Offset _pixel(double xPercent, double yPercent, Size size) =>
      Offset(xPercent / 100 * size.width, yPercent / 100 * size.height);

  /// 画布上某个角的像素位置（手柄画在那儿，命中判定也用它）。
  Offset _cornerPixel(WorkspaceRevealZone zone, RevealCorner corner, Size size) {
    final x = corner.isWest ? zone.x : zone.right;
    final y = corner.isNorth ? zone.y : zone.bottom;
    return _pixel(x, y, size);
  }

  RevealCorner? _cornerAt(Offset local, Size size) {
    final zone = _draft[_selected];
    for (final corner in RevealCorner.values) {
      final handle = _cornerPixel(zone, corner, size);
      if ((handle - local).distance <= _handleHitRadius) return corner;
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent event, Size size) {
    final corner = _cornerAt(event.localPosition, size);
    setState(() {
      _drag = corner == null
          ? _ZoneDrag.draw(
              _percent(event.localPosition, size),
              event.position,
            )
          : _ZoneDrag.resize(corner, _draft[_selected]);
    });
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    final drag = _drag;
    if (drag == null) return;
    // 按下但没挪动过 4px ⇒ 不算画框：那一下是**点了一下**，
    // 而点画布不等于「把唤出区缩成 1%」。
    if (!drag.isResize && !drag.moved) {
      final origin = drag.startClient;
      if (origin == null) return;
      if ((event.position - origin).distance < 4) return;
      drag.moved = true;
    }
    final at = _percent(event.localPosition, size);
    if (drag.isResize) {
      _apply(
        resizedRevealZone(
          zone: drag.initial!,
          corner: drag.corner!,
          xPercent: at.dx,
          yPercent: at.dy,
        ),
      );
      return;
    }
    final from = drag.start!;
    _apply(
      drawnRevealZone(
        fromX: from.dx,
        fromY: from.dy,
        toX: at.dx,
        toY: at.dy,
      ),
    );
  }

  void _onPointerUp() {
    final drag = _drag;
    _drag = null;
    if (drag == null) return;
    if (!drag.isResize && !drag.moved) return;
    _commit();
  }

  void _resetToDefaults() {
    setState(() => _draft = WorkspaceRevealZones.defaults);
    _commit();
  }

  void _updateField(RevealZoneField field, double value) {
    final zone = _draft[_selected];
    final next = switch (field) {
      RevealZoneField.x => zone.copyWith(x: value),
      RevealZoneField.y => zone.copyWith(y: value),
      // 改宽 / 高时**不动原点**，越界的部分由 `clamped()` 收掉：
      // 反过来（先夹原点）会让「把宽拖到 100」顺手把 x 挪成 0，
      // 用户看到的却是矩形从右边缩回去。
      RevealZoneField.width => zone.copyWith(width: value),
      RevealZoneField.height => zone.copyWith(height: value),
    };
    _apply(next);
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.settings.hoverRevealZonesSubtitle,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _SegmentedPicker<RevealEdge>(
                    value: _selected,
                    onChanged: (edge) => setState(() => _selected = edge),
                    entries: [
                      for (final edge in RevealEdge.values)
                        _Segment(
                          edge,
                          _edgeLabel(edge),
                          null,
                          dot: _kEdgeColors[edge],
                        ),
                    ],
                  ),
                  _LinkCheck(
                    label: t.settings.revealLinkHorizontal,
                    value: _horizontalLinked,
                    onChanged: (v) => setState(() => _horizontalLinked = v),
                  ),
                  _LinkCheck(
                    label: t.settings.revealLinkVertical,
                    value: _verticalLinked,
                    onChanged: (v) => setState(() => _verticalLinked = v),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: t.settings.revealReset,
              onPressed: _resetToDefaults,
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = width / _aspect;
            final size = Size(width, height);
            return Listener(
              // 画布自己吃指针事件：`Listener` 不阻断冒泡，但命中区域由
              // 下面那个 `Positioned.fill` 的容器给出，画框因此整块可拖。
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _onPointerDown(e, size),
              onPointerMove: (e) => _onPointerMove(e, size),
              onPointerUp: (_) => _onPointerUp(),
              onPointerCancel: (_) => _onPointerUp(),
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: .35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: .7),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CustomPaint(
                    size: size,
                    painter: _RevealZonePainter(
                      zones: _draft,
                      selected: _selected,
                      guide: scheme.outlineVariant,
                      handleFill: scheme.primary,
                      handleBorder: scheme.surface,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final field in RevealZoneField.values) ...[
              Expanded(
                child: _LabeledNumberField(
                  label: field.label,
                  value: field.read(_draft[_selected]),
                  onCommit: (value) => _updateField(field, value),
                ),
              ),
              if (field != RevealZoneField.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          t.settings.hoverRevealZonesHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// 唤出区的四个可编辑量。
enum RevealZoneField {
  x,
  y,
  width,
  height;

  static const RevealZoneField last = RevealZoneField.height;

  String get label => switch (this) {
    RevealZoneField.x => t.settings.revealFieldX,
    RevealZoneField.y => t.settings.revealFieldY,
    RevealZoneField.width => t.settings.revealFieldWidth,
    RevealZoneField.height => t.settings.revealFieldHeight,
  };

  double read(WorkspaceRevealZone zone) => switch (this) {
    RevealZoneField.x => zone.x,
    RevealZoneField.y => zone.y,
    RevealZoneField.width => zone.width,
    RevealZoneField.height => zone.height,
  };
}

/// 画布下方的小数字框（X / Y / 宽 / 高）。
class _LabeledNumberField extends StatelessWidget {
  const _LabeledNumberField({
    required this.label,
    required this.value,
    required this.onCommit,
  });

  final String label;
  final double value;
  final ValueChanged<double> onCommit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        _PercentBox(value: value, onCommit: onCommit),
      ],
    );
  }
}

/// 百分比数字框：0..99，0.1 步进，同样只在回车 / 失焦时提交。
class _PercentBox extends StatefulWidget {
  const _PercentBox({required this.value, required this.onCommit});

  final double value;
  final ValueChanged<double> onCommit;

  @override
  State<_PercentBox> createState() => _PercentBoxState();
}

class _PercentBoxState extends State<_PercentBox> {
  late final TextEditingController _controller = TextEditingController(
    text: _format(widget.value),
  );
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChanged);
  bool _editing = false;

  static String _format(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  void _onFocusChanged() {
    final focused = _focus.hasFocus;
    if (!focused) _commit();
    if (focused != _editing) setState(() => _editing = focused);
  }

  @override
  void didUpdateWidget(covariant _PercentBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && _controller.text != _format(widget.value)) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = _format(widget.value);
      return;
    }
    final next = clampRevealPercent(parsed);
    _controller.text = _format(next);
    if (next != widget.value) widget.onCommit(next);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      style: const TextStyle(fontSize: 13),
      decoration: const InputDecoration(
        isDense: true,
        isCollapsed: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      ),
      onSubmitted: (_) => _commit(),
    );
  }
}

/// 画布：虚线十字参考线 + 四块唤出区 + 选中那块的四个角手柄。
///
/// 全部**画**出来而不是用 widget 摆：唤出区在画布上既不吃点击也不吃悬停
/// （指针事件归画布自己），摆 4 个 `Positioned` 容器再各套一层
/// `IgnorePointer` 反而更啰嗦。
class _RevealZonePainter extends CustomPainter {
  const _RevealZonePainter({
    required this.zones,
    required this.selected,
    required this.guide,
    required this.handleFill,
    required this.handleBorder,
  });

  final WorkspaceRevealZones zones;
  final RevealEdge selected;
  final Color guide;
  final Color handleFill;
  final Color handleBorder;

  static const double _handleSize = 11;

  @override
  void paint(Canvas canvas, Size size) {
    _paintDashedCross(canvas, size);
    for (final edge in RevealEdge.values) {
      final zone = zones[edge];
      final rect = Rect.fromLTWH(
        zone.x / 100 * size.width,
        zone.y / 100 * size.height,
        zone.width / 100 * size.width,
        zone.height / 100 * size.height,
      );
      final color = _kEdgeColors[edge]!;
      final active = edge == selected;
      canvas.drawRect(
        rect,
        Paint()
          ..color = color.withValues(alpha: active ? 0.24 : 0.14),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: active ? 1 : 0.7),
      );
      if (!active) continue;
      for (final corner in RevealCorner.values) {
        final center = Offset(
          (corner.isWest ? zone.x : zone.right) / 100 * size.width,
          (corner.isNorth ? zone.y : zone.bottom) / 100 * size.height,
        );
        final handle = Rect.fromCenter(
          center: center,
          width: _handleSize,
          height: _handleSize,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(handle, const Radius.circular(2)),
          Paint()..color = handleFill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            handle.deflate(0.5),
            const Radius.circular(2),
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = handleBorder,
        );
      }
    }
  }

  void _paintDashedCross(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = guide.withValues(alpha: .8)
      ..strokeWidth = 1;
    // dart:ui 没有虚线 PathEffect，只能自己一段一段画。
    const double dash = 6;
    const double gap = 5;
    final step = dash + gap;
    final midY = size.height / 2;
    for (var x = 0.0; x < size.width; x += step) {
      final end = (x + dash < size.width) ? x + dash : size.width;
      canvas.drawLine(Offset(x, midY), Offset(end, midY), paint);
    }
    final midX = size.width / 2;
    for (var y = 0.0; y < size.height; y += step) {
      final end = (y + dash < size.height) ? y + dash : size.height;
      canvas.drawLine(Offset(midX, y), Offset(midX, end), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RevealZonePainter oldDelegate) =>
      oldDelegate.zones != zones ||
      oldDelegate.selected != selected ||
      oldDelegate.guide != guide ||
      oldDelegate.handleFill != handleFill ||
      oldDelegate.handleBorder != handleBorder;
}

// ── 通用小件 ──────────────────────────────────────────────────────────────

class _Segment<T> {
  const _Segment(this.value, this.label, this.icon, {this.dot});

  final T value;
  final String label;
  final IconData? icon;

  /// 色点：唤出区的四条边靠它把「chip」和「画布上那块颜色」对起来。
  final Color? dot;
}

/// 圆角容器里的一排互斥选项（neoview 的 `TabsList` / `variant=default|ghost`）。
class _SegmentedPicker<T> extends StatelessWidget {
  const _SegmentedPicker({
    required this.value,
    required this.onChanged,
    required this.entries,
  });

  final T value;
  final ValueChanged<T> onChanged;
  final List<_Segment<T>> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .7)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: entry.value == value
                      ? scheme.primary
                      : Colors.transparent,
                  foregroundColor: entry.value == value
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => onChanged(entry.value),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entry.dot != null) ...[
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: entry.dot!.withValues(alpha: .85),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ] else if (entry.icon != null) ...[
                      Icon(entry.icon, size: 15),
                      const SizedBox(width: 6),
                    ],
                    Text(entry.label, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 一行紧凑的复选框（联动开关）。
class _LinkCheck extends StatelessWidget {
  const _LinkCheck({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 22,
              child: FittedBox(
                child: Checkbox(
                  value: value,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (next) => onChanged(next ?? false),
                ),
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
