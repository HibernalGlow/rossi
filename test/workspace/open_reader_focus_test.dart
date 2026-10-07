// 「点阅读这一下，人要不要跟着跳到阅读器泳道」—— 开书时的聚焦判定。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     CARGO_HOME=/opt/homebrew flutter test test/workspace/open_reader_focus_test.dart
//
// # 为什么需要这条判据
//
// 详情页那颗「阅读」与封面那颗「直接阅读」推的是**同一个** `ComicReadRoute`，
// 工作台在场时被根路由守卫改派进中央阅读器泳道；而 `WorkspaceCubit.openReader`
// 除了把书塞进泳道，还会**顺带把交互交过去**（`activeLaneId = reader`）——
// 于是条带滚向阅读器，用户正在浏览的那条泳道被推出视口，每次读完都要重新唤回来。
//
// 这一颗开关（`autoFocusReaderOnOpen`）把「要不要跟着过去」交还给用户。
// 判定住在 `openReader` 一处，所以判据也钉在那一处：**书必须真的开进去**，
// 而激活泳道不许动 —— 只断言「没变」是空转，两条必须成对出现（见下面每一条
// 用例里的 reason）。
//
// # 两条纪律
//
// 1. 每一条「不该变」都配一条「必须变」的对照：默认档那条就是对照 ——
//    它一变不动，说明这把尺子根本没在量 `activeLaneId`。
// 2. 老快照缺键时必须落到**默认档**（= 改造前的行为）。落到反了，
//    升级一次就把所有人的手感改掉了，而那条路没有任何运行时报错。
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_reader_target.dart';

WorkspaceReaderTarget _target(String comicId) => WorkspaceReaderTarget(
  comicId: comicId,
  from: 'test',
  stringSelectCubit: StringSelectCubit(),
);

/// 一条已经「人在左泳道、手里翻着书架」的工作台。
WorkspaceCubit _browsingInLeftLane({required bool focusReaderOnOpen}) {
  final cubit = WorkspaceCubit();
  cubit.setInteraction(
    cubit.state.interaction.copyWith(
      autoFocusReaderOnOpen: focusReaderOnOpen,
    ),
  );
  cubit.activateLane(LaneId.left);
  expect(
    cubit.state.activeLaneId,
    LaneId.left,
    reason: '前置：得先真的站在左泳道里，否则「没换」是废话',
  );
  return cubit;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认档：拆封设置里就是「开书换激活泳道」（= 改造前的行为）', () {
    const settings = WorkspaceInteractionSettings();
    expect(
      settings.autoFocusReaderOnOpen,
      isTrue,
      reason: '默认必须等于改造前行为，否则升级会悄悄改掉所有人的手感',
    );
  });

  test('对照（默认档）：打开一本书必须把交互交给阅读器泳道', () {
    final cubit = _browsingInLeftLane(focusReaderOnOpen: true);
    addTearDown(cubit.close);

    cubit.openReader(_target('comic-A'));

    expect(cubit.state.readerTarget?.comicId, 'comic-A', reason: '书得开进去');
    expect(
      cubit.state.activeLaneId,
      LaneId.reader,
      reason: '这条不成立就说明这把尺子看不见激活泳道的变化，下面「没换」全是空转',
    );
  });

  test('关掉：书开进阅读器泳道，但激活泳道留在用户手上那条', () {
    final cubit = _browsingInLeftLane(focusReaderOnOpen: false);
    addTearDown(cubit.close);

    cubit.openReader(_target('comic-A'));

    expect(
      cubit.state.readerTarget?.comicId,
      'comic-A',
      reason: '关的是「跟不跟着过去」，不是「要不要开书」—— 书必须真的开了',
    );
    expect(
      cubit.state.activeLaneId,
      LaneId.left,
      reason: '条带不许动：用户还在左泳道里翻书架，这就是他要的那一档',
    );
  });

  test('关掉：同一本书重复点不出多余的 emit（关掉不等于每次点击白刷一遍）', () {
    final cubit = _browsingInLeftLane(focusReaderOnOpen: false);
    addTearDown(cubit.close);
    cubit.openReader(_target('comic-A'));

    final emissions = <WorkspaceState>[];
    final subscription = cubit.stream.listen(emissions.add);
    addTearDown(subscription.cancel);

    cubit.openReader(_target('comic-A'));

    expect(
      emissions,
      isEmpty,
      reason: 'target 没变、激活态也不该变 ⇒ 一次 emit 都不该有（关掉之前这条靠 activate 短路）',
    );
  });

  test('关掉只挡「开书那一下」：手动激活阅读器泳道照样生效', () {
    final cubit = _browsingInLeftLane(focusReaderOnOpen: false);
    addTearDown(cubit.close);
    cubit.openReader(_target('comic-A'));

    cubit.activateLane(LaneId.reader);

    expect(
      cubit.state.activeLaneId,
      LaneId.reader,
      reason: '开关管的是开书，不是把泳道锁死 —— 点一下（或悬停）仍然要能过去',
    );
  });

  test('老快照缺键 ⇒ 落到默认档（而不是落到「关」）', () {
    final restored = WorkspaceInteractionSettings.fromJson(
      const <String, Object?>{'autoSoloOnFocus': true},
    );

    expect(
      restored.autoFocusReaderOnOpen,
      isTrue,
      reason: '缺键 = 老快照 ⇒ 必须等于改造前行为，否则升级后所有人被静默改成新档',
    );
    expect(restored.autoSoloOnFocus, isTrue, reason: '别的键照旧读出来');
  });

  test('JSON 往返：关掉那一档存得下、读得回', () {
    final off = const WorkspaceInteractionSettings().copyWith(
      autoFocusReaderOnOpen: false,
    );
    final roundTrip = WorkspaceInteractionSettings.fromJson(off.toJson());

    expect(
      roundTrip.autoFocusReaderOnOpen,
      isFalse,
      reason: 'toJson 漏了键的话，关掉之后重启就自己变回开',
    );
    expect(roundTrip, off);
  });
}
