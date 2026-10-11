// 纯 Dart 模型回归：无需启动 Flutter 或 native-assets 构建钩子。
// dart --packages=.dart_tool/package_config.json test/workspace/lane_interaction_check.dart
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_lane_interaction.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';

int _passed = 0;

void check(String label, bool condition) {
  if (!condition) throw StateError('FAIL: $label');
  _passed++;
}

void main() {
  _legacyDefaults();
  _independentPreferences();
  _delayInheritance();
  _malformedData();
  _valueEquality();
  _snapshotRoundTrip();
  print('PASS: $_passed lane interaction checks');
}

void _legacyDefaults() {
  final old = WorkspaceInteractionSettings.fromJson({
    'hoverFocusEnabled': false,
    'panelHoverFocusEnabled': true,
    'hoverFocusDelayMs': 275,
  });
  check('旧快照不主动生成覆盖项', old.laneInteractions.isEmpty);
  check('Reader 自动定位继承旧开关', !old.interactionForLane(LaneId.reader).autoReveal);
  for (final lane in [LaneId.left, LaneId.right]) {
    check('$lane 自动定位继承面板开关', old.interactionForLane(lane).autoReveal);
  }
  for (final lane in LaneId.defaultOrder) {
    check('$lane 键盘跟随默认开启', old.interactionForLane(lane).inputTargetOnHover);
    check('$lane 延迟保持继承标记', old.interactionForLane(lane).hoverDelayMs == null);
    check('$lane 继承全局延迟', old.hoverDelayForLane(lane) == 275);
  }
  final reversed = old.copyWith(
    hoverFocusEnabled: true,
    panelHoverFocusEnabled: false,
  );
  check(
    'Reader 与面板默认独立',
    reversed.interactionForLane(LaneId.reader).autoReveal,
  );
  check('左侧继承面板关闭', !reversed.interactionForLane(LaneId.left).autoReveal);
  check('右侧继承面板关闭', !reversed.interactionForLane(LaneId.right).autoReveal);
  check('未知泳道按面板回退', !reversed.interactionForLane('future-lane').autoReveal);
  check(
    '空快照使用默认值',
    WorkspaceInteractionSettings.fromJson({}) ==
        const WorkspaceInteractionSettings(),
  );
}

void _independentPreferences() {
  const settings = WorkspaceInteractionSettings(
    hoverFocusEnabled: false,
    laneInteractions: {
      LaneId.reader: WorkspaceLaneInteraction(autoReveal: false),
      LaneId.left: WorkspaceLaneInteraction(inputTargetOnHover: false),
    },
  );
  final reader = settings.interactionForLane(LaneId.reader);
  final left = settings.interactionForLane(LaneId.left);
  check('关闭定位仍能跟随键盘目标', !reader.autoReveal && reader.inputTargetOnHover);
  check('关闭键盘跟随仍能定位', !left.inputTargetOnHover && left.autoReveal);
  final changed = settings.copyWith(
    laneInteractions: {
      ...settings.laneInteractions,
      LaneId.reader: reader.copyWith(autoReveal: true),
    },
  );
  check('覆盖项优先于旧开关', changed.interactionForLane(LaneId.reader).autoReveal);
  check('修改一条保留另一条', changed.interactionForLane(LaneId.left) == left);
  check('修改不污染原模型', !settings.interactionForLane(LaneId.reader).autoReveal);
  check(
    '改全局字段保留泳道覆盖',
    settings.copyWith(showTopChrome: true).interactionForLane(LaneId.left) ==
        left,
  );
}

void _delayInheritance() {
  const lane = WorkspaceLaneInteraction(hoverDelayMs: 321);
  const settings = WorkspaceInteractionSettings(
    laneInteractions: {LaneId.reader: lane},
  );
  final changed = settings.copyWith(hoverFocusDelayMs: 600);
  check('自定义延迟不随全局变化', changed.hoverDelayForLane(LaneId.reader) == 321);
  check('未覆盖泳道随全局变化', changed.hoverDelayForLane(LaneId.left) == 600);
  final inherited = lane.copyWith(hoverDelayMs: () => null);
  check('可恢复 null 继承标记', inherited.hoverDelayMs == null);
  final reset = changed.copyWith(laneInteractions: {LaneId.reader: inherited});
  check('恢复继承立即解析全局值', reset.hoverDelayForLane(LaneId.reader) == 600);
  check('继承标记序列化为 null', inherited.toJson()['hoverDelayMs'] == null);
  check('修改开关不丢自定义延迟', lane.copyWith(autoReveal: false).hoverDelayMs == 321);
  check('支持精确毫秒值', lane.copyWith(hoverDelayMs: () => 137).hoverDelayMs == 137);
}

void _malformedData() {
  for (final invalid in [null, true, 'bad', <Object>[]]) {
    final parsed = WorkspaceInteractionSettings.fromJson({
      'laneInteractions': invalid,
      'showTopChrome': true,
    });
    check('非对象覆盖表回退为空：$invalid', parsed.laneInteractions.isEmpty);
    check('坏覆盖表不丢其他偏好：$invalid', parsed.showTopChrome);
  }
  for (final invalid in [0, -1, 2.5, '150', false]) {
    final lane = WorkspaceLaneInteraction.fromJson({
      'inputTargetOnHover': false,
      'hoverDelayMs': invalid,
    });
    check('坏延迟退回继承：$invalid', lane.hoverDelayMs == null);
    check('坏延迟保留合法开关：$invalid', !lane.inputTargetOnHover);
  }
  final partial = WorkspaceInteractionSettings.fromJson({
    'hoverFocusEnabled': false,
    'panelHoverFocusEnabled': true,
    'laneInteractions': {
      LaneId.reader: {
        'inputTargetOnHover': 'bad',
        'autoReveal': 1,
        'hoverDelayMs': 201,
      },
      LaneId.left: {'inputTargetOnHover': false},
      LaneId.right: 'bad',
      'future-lane': {'autoReveal': false, 1: 'ignored'},
      '': {'autoReveal': true},
      99: {'autoReveal': true},
    },
  });
  check(
    '坏布尔回到键盘跟随默认',
    partial.interactionForLane(LaneId.reader).inputTargetOnHover,
  );
  check(
    '部分 Reader 配置回退旧开关',
    !partial.interactionForLane(LaneId.reader).autoReveal,
  );
  check('部分面板配置回退旧开关', partial.interactionForLane(LaneId.left).autoReveal);
  check('部分损坏仍保留合法延迟', partial.hoverDelayForLane(LaneId.reader) == 201);
  check('坏泳道条目不阻断同级解析', !partial.laneInteractions.containsKey(LaneId.right));
  check('保留未来泳道 ID 的偏好', !partial.interactionForLane('future-lane').autoReveal);
  check('丢弃非法 ID', partial.laneInteractions.length == 3);
}

void _valueEquality() {
  const a = WorkspaceInteractionSettings(
    laneInteractions: {
      LaneId.left: WorkspaceLaneInteraction(inputTargetOnHover: false),
      LaneId.reader: WorkspaceLaneInteraction(hoverDelayMs: 222),
    },
  );
  final b = WorkspaceInteractionSettings(
    laneInteractions: {
      LaneId.reader: WorkspaceLaneInteraction.fromJson({'hoverDelayMs': 222}),
      LaneId.left: WorkspaceLaneInteraction.fromJson({
        'inputTargetOnHover': false,
      }),
    },
  );
  check('相等性比较内容而非 Map 身份或插入顺序', a == b);
  check('相同值有相同哈希', a.hashCode == b.hashCode);
  final changed = b.copyWith(
    laneInteractions: {
      ...b.laneInteractions,
      LaneId.reader: const WorkspaceLaneInteraction(hoverDelayMs: 223),
    },
  );
  check('单条偏好变化可被状态比较发现', a != changed);
  check('删除覆盖项可被状态比较发现', a != a.copyWith(laneInteractions: {}));
}

void _snapshotRoundTrip() {
  final before = WorkspaceLayoutSnapshot.defaults().copyWithInteraction(
    const WorkspaceInteractionSettings(
      hoverFocusEnabled: false,
      panelHoverFocusEnabled: false,
      hoverFocusDelayMs: 412,
      panelTabSortMode: true,
      showTopChrome: true,
      laneInteractions: {
        LaneId.left: WorkspaceLaneInteraction(
          inputTargetOnHover: false,
          hoverDelayMs: 137,
        ),
        LaneId.reader: WorkspaceLaneInteraction(autoReveal: false),
        LaneId.right: WorkspaceLaneInteraction(hoverDelayMs: 491),
        'future-lane': WorkspaceLaneInteraction(autoReveal: false),
      },
    ),
  );
  final encoded = jsonEncode(before.toJson());
  final decoded = WorkspaceLayoutSnapshot.decode(jsonDecode(encoded));
  check('无需提升 snapshot 版本', decoded != null);
  final after = WorkspaceLayoutSnapshot.fromJson(decoded!);
  check('整份 snapshot 完整往返', jsonEncode(after.toJson()) == encoded);
  check('交互模型完整往返', after.interaction == before.interaction);
  check(
    '继承延迟重启后仍继承',
    after.interaction.interactionForLane(LaneId.reader).hoverDelayMs == null,
  );
  check(
    '恢复后能继续继承新的全局值',
    after.interaction
            .copyWith(hoverFocusDelayMs: 800)
            .hoverDelayForLane(LaneId.reader) ==
        800,
  );
  check(
    '既有交互字段不因新增配置丢失',
    after.interaction.panelTabSortMode && after.interaction.showTopChrome,
  );
}
