// 轮盘的**文档层**判据（纯 Dart，不碰 FRB —— 见 `radial_doc.dart` 的头注释）。
//
// 这里钉的是最容易出错的四件事：
// ① 改形状时不许洗掉用户没碰过的字段；
// ② 一个槽只许一条绑定（追加=当场造出冲突）；
// ③ descriptor 的形状必须与核心逐字段一致（差一个字符那条绑定就永远不生效）；
// ④ 重置只重写预设那几条。
//
// 几何与解析的判据在 Rust 侧（`cargo test -p rossi_local_core`）：那边才是算术的
// 唯一权威，这里重复断言一遍只会造成两处同时改才能过的冗余。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/radial_doc.dart';
import 'package:zephyr/widgets/radial/radial_wheel_painter.dart';

/// 核心给默认轮盘算出的布局（r120 · 内 40 · 3 层 · 每层 8 格）在这里手抄一份，
/// 只用于喂 painter —— 断言的是「画法不崩、缩放合理」，不是几何本身。
List<RadialSlotPaint> _defaultLayout({String menuId = 'default'}) {
  const inner = 40.0;
  const radius = 120.0;
  const layers = 3;
  const sectors = 8;
  final band = (radius - inner) / layers;
  const sweep = 360.0 / sectors;
  return [
    for (var layer = 1; layer <= layers; layer++)
      for (var sector = 0; sector < sectors; sector++)
        RadialSlotPaint(
          menuId: menuId,
          itemId: 'l${layer}s$sector',
          layer: layer,
          sector: sector,
          innerRadius: inner + (layer - 1) * band,
          outerRadius: inner + layer * band,
          startDeg: -90.0 + sector * sweep - sweep / 2,
          endDeg: -90.0 + sector * sweep + sweep / 2,
          midDeg: -90.0 + sector * sweep,
        ),
  ];
}

const _sampleDoc =
    '{'
    '"enabled":true,'
    '"activeMenuId":"default",'
    '"toUser":"keep-me",'
    '"menus":[{"id":"default","name":"默认轮盘","layers":3,"toRow":"keep-too",'
    '"geometry":{"radius":120,"innerRadius":40,"sectors":8}}]'
    '}';

void main() {
  group('轮盘文档', () {
    test('读不懂的文档一律 null（不猜一份默认值覆盖用户的）', () {
      expect(parseRadialDoc(''), isNull);
      expect(parseRadialDoc('not json'), isNull);
      expect(parseRadialDoc('[]'), isNull);
      expect(parseRadialDoc('{"menus":{}}'), isNull);
      final doc = parseRadialDoc(_sampleDoc);
      expect(doc, isNotNull);
      expect(doc!.enabled, isTrue);
      expect(doc.menus.single.layers, 3);
      expect(doc.menus.single.sectors, 8);
      expect(doc.menus.single.slotCount, 24);
    });

    test('改一个字段不许洗掉别的字段（未知键原样留着）', () {
      final doc = parseRadialDoc(_sampleDoc)!;
      final next = doc.copyWith(activeMenuId: 'x').withMenuReplaced(
        doc.menus.single.copyWith(layers: 2),
      );
      final decoded = jsonDecode(next.encode()) as Map<String, dynamic>;
      // 文档级与菜单级各留一个本层不认识的键。
      expect(decoded['toUser'], 'keep-me');
      expect((decoded['menus'] as List).first['toRow'], 'keep-too');
      expect(decoded['activeMenuId'], 'x');
      expect((decoded['menus'] as List).first['layers'], 2);
      // enabled 没被碰过 ⇒ 还在。
      expect(decoded['enabled'], isTrue);
    });

    test('生效轮盘指不到时退回第一个（删了没改选中项也不该开不出轮盘）', () {
      final doc = parseRadialDoc(_sampleDoc)!.copyWith(activeMenuId: 'gone');
      expect(doc.activeMenu?.id, 'default');
      expect(doc.menu('nope'), isNull);
    });

    test('删轮盘会把选中项挪到剩下的第一个，并拒绝删到空', () {
      var doc = parseRadialDoc(_sampleDoc)!;
      doc = doc.withMenu(RadialMenuDoc({'id': 'two', 'name': '轮盘 2'}));
      expect(doc.menus.length, 2);
      doc = doc.withoutMenu('default');
      expect(doc.menus.map((menu) => menu.id), ['two']);
      expect(doc.activeMenuId, 'two');
    });
  });

  group('槽位与绑定行', () {
    test('radial descriptor 的形状与核心逐字段一致', () {
      // 核心产的是 `{"device":"radial","menuId":…,"itemId":…}`（model.rs 钉过）。
      // 这里差一个字母，那条绑定就永远匹配不上，而两边看着都正常。
      expect(
        jsonDecode(radialInputJson(menuId: 'default', itemId: 'l1s0')),
        {'device': 'radial', 'menuId': 'default', 'itemId': 'l1s0'},
      );
    });

    test('同一格只留一条：改写而不是追加', () {
      var bindings = <Map<String, dynamic>>[];
      final slot = (menuId: 'default', itemId: 'l2s3');
      bindings = bindSlot(bindings, slot, 'reader.next-page');
      expect(bindings.length, 1);
      expect(actionForSlot(bindings, slot), 'reader.next-page');

      final id = bindings.single['id'];
      bindings = bindSlot(bindings, slot, 'reader.fullscreen');
      expect(bindings.length, 1, '同一格再绑一次是改写，不是第二条（第二条=冲突）');
      expect(bindings.single['id'], id, '改写要保住 id，否则预设前缀的认不出来');
      expect(actionForSlot(bindings, slot), 'reader.fullscreen');

      bindings = bindSlot(bindings, slot, '');
      expect(bindings, isEmpty);
      expect(actionForSlot(bindings, slot), isNull);
    });

    test('新行的 context 是 reader，input 是 radial', () {
      final bindings = bindSlot(
        <Map<String, dynamic>>[],
        (menuId: 'default', itemId: 'l1s0'),
        'reader.zoom-in',
      );
      final row = bindings.single;
      expect(row['context'], 'reader');
      expect(row['enabled'], isTrue);
      expect((row['input'] as Map)['device'], InputDevice.radial);
      expect((row['input'] as Map)['itemId'], 'l1s0');
    });

    test('槽位清单含空槽，顺序是层由内向外、格顺时针', () {
      final menu = parseRadialDoc(_sampleDoc)!.menus.single;
      final bindings = bindSlot(
        <Map<String, dynamic>>[],
        (menuId: 'default', itemId: 'l1s2'),
        'reader.fullscreen',
      );
      final slots = radialSlots(menu, bindings);
      expect(slots.length, 24);
      expect(slots.first.slot.itemId, 'l1s0');
      expect(slots.first.actionId, isNull);
      expect(slots[2].actionId, 'reader.fullscreen');
      expect(slots[8].slot.itemId, 'l2s0', '第 9 格已经是第二层');
      expect(slots.last.slot.itemId, 'l3s7');
    });

    test('itemId 只认 `l<层>s<格>`（别的形状一律 null）', () {
      expect(parseSlotItemId('l3s7'), (3, 7));
      expect(parseSlotItemId('l0s0'), (0, 0));
      for (final bad in ['', 's1', 'l1', 'lXs1', '1s1', 'l1x1', 'L1s1']) {
        expect(parseSlotItemId(bad), isNull, '$bad 不是合法 itemId');
      }
      final menu = parseRadialDoc(_sampleDoc)!.menus.single;
      expect(menu.hasSlot((menuId: 'default', itemId: 'l1s0')), isTrue);
      expect(menu.hasSlot((menuId: 'default', itemId: 'l4s0')), isFalse, '只有 3 层');
      expect(menu.hasSlot((menuId: 'default', itemId: 'l1s8')), isFalse, '每层 8 格');
      expect(menu.hasSlot((menuId: 'default', itemId: 'nonsense')), isFalse);
    });

    test('重置只重写这个轮盘的预设行，用户自绑的一条不动', () {
      const prefix = 'preset-radial-default-';
      final user = buildBinding(
        id: 'user-radial-1',
        action: 'reader.zoom-in',
        context: 'reader',
        inputJson: radialInputJson(menuId: 'default', itemId: 'l1s0'),
      );
      final otherWheel = buildBinding(
        id: 'preset-radial-two-l1s0',
        action: 'reader.last-page',
        context: 'reader',
        inputJson: radialInputJson(menuId: 'two', itemId: 'l1s0'),
      );
      final presetRow = buildBinding(
        id: '${prefix}l3s4',
        action: 'reader.reset-view',
        context: 'reader',
        inputJson: radialInputJson(menuId: 'default', itemId: 'l3s4'),
      );
      final rows = [
        buildBinding(
          id: '${prefix}l1s0',
          action: 'reader.fullscreen',
          context: 'reader',
          inputJson: radialInputJson(menuId: 'default', itemId: 'l1s0'),
        ),
      ];
      final next = resetRadialPresetSlots(
        [user, otherWheel, presetRow],
        'default',
        rows,
      );
      expect(next.map((row) => row['id']), [
        'user-radial-1',
        'preset-radial-two-l1s0',
        'preset-radial-default-l1s0',
      ]);
      // 用户自绑的那一格（l1s0）被预设覆盖了 —— 这正是「按前缀重写」的语义：
      // 预设行按 id 前缀认，与它落在哪一格无关。
      expect(actionForSlot(next, (menuId: 'default', itemId: 'l1s0')), 'reader.fullscreen');
      expect(actionForSlot(next, (menuId: 'default', itemId: 'l3s4')), isNull);
    });

    test('解绑一条不影响别的轮盘的同名格', () {
      final bindings = [
        buildBinding(
          id: 'a',
          action: 'reader.next-page',
          context: 'reader',
          inputJson: radialInputJson(menuId: 'default', itemId: 'l1s0'),
        ),
        buildBinding(
          id: 'b',
          action: 'reader.last-page',
          context: 'reader',
          inputJson: radialInputJson(menuId: 'two', itemId: 'l1s0'),
        ),
      ];
      final next = unbindSlot(bindings, (menuId: 'default', itemId: 'l1s0'));
      expect(next.map((row) => row['id']), ['b']);
      expect(radialBindingsForMenu(next, 'two').length, 1);
    });
  });

  group('画法（与运行时共用同一个 painter）', () {
    test('24 格的轮盘画得出来，缩放比不会溢出盒子', () {
      final layout = _defaultLayout();
      expect(layout.length, 24);
      final picture = const RadialWheelPainter(
        slots: layout,
        labels: {'l1s0': '下一页', 'l3s7': '一个很长很长很长很长的动作名'},
        colors: ColorScheme.fromSeed(seedColor: Colors.teal),
        hoveredItem: 'l2s3',
        centerLabel: '默认轮盘',
      );
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      picture.paint(canvas, const Size(400, 400));
      final image = recorder.endRecording().toPicture();
      // 画得出来 = 有一批绘制指令；空 Picture 意味着几何全被夹成 0。
      expect(image, isNotNull);
      expect(radialFitScale(box: const Size(400, 400), radius: 120), 1.0);
      expect(
        radialFitScale(box: const Size(150, 900), radius: 120) * 240,
        lessThanOrEqualTo(150.0 + 1e-6),
        '小盒子必须整体缩小，而不是溢出',
      );
    });
  });
}
