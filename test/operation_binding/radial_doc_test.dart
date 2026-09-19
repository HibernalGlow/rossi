// 轮盘的**文档层**判据（纯 Dart，不碰 FRB —— 见 `radial_doc.dart` 的头注释）。
//
// 这里钉的是最容易出错的四件事：
// ① 改形状时不许洗掉用户没碰过的字段；
// ② 一个条目只许一条绑定（追加 = 当场造出冲突）；
// ③ descriptor 的形状必须与核心逐字段一致（差一个字符那条绑定就永远不生效）；
// ④ 重置只重写预设那几条，用户自绑的一条不动。
//
// 几何与解析的判据在 Rust 侧（`cargo test -p rossi_local_core`）：那边才是算术与
// 预设的唯一权威，这里重复断言一遍只会造成两处同时改才能过的冗余。

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/service/operation_binding/radial_doc.dart';
import 'package:zephyr/widgets/radial/radial_wheel_painter.dart';

/// 一份带「未知字段」的轮盘文档：`toUser` / `toRow` 是本层不认识的键，
/// 判据是它们必须活着回到 JSON 里。
const _sampleDoc = '''
{
  "enabled": true,
  "layerCount": 3,
  "activeMenuId": "default",
  "toUser": "keep-me",
  "radius": 120,
  "innerRadius": 40,
  "variant": "slice",
  "startAngle": -90,
  "sweepAngle": 360,
  "menus": [
    {
      "id": "default",
      "name": "默认轮盘",
      "toRow": "keep-too",
      "layers": [
        [
          {"id": "radial-next-page", "label": "下一页", "slotIndex": 0},
          {"id": "radial-fullscreen", "label": "全屏", "slotIndex": 6}
        ],
        [{"id": "item-9", "label": "第一页", "slotIndex": 0}],
        []
      ]
    }
  ]
}''';

/// 核心给默认轮盘算出的布局，这里手抄一份**只用来喂 painter**：
/// 断言的是「画法不崩、缩放合理」，几何本身由 Rust 的测试守着。
List<RadialSlotPaint> _layoutForPainting() {
  const sweep = 360.0 / 8;
  return [
    for (var level = 1; level <= 3; level++)
      for (var index = 0; index < 8; index++)
        RadialSlotPaint(
          menuId: 'default',
          level: level,
          index: index,
          innerRadius: level == 1 ? 40 : 120.0 + (level - 2) * 60,
          outerRadius: 120.0 + (level - 1) * 60,
          startDeg: -90.0 + index * sweep - sweep / 2,
          endDeg: -90.0 + index * sweep + sweep / 2,
          midDeg: -90.0 + index * sweep,
          itemId: index.isEven && level == 1 ? 'radial-next-page' : null,
          label: index.isEven && level == 1 ? '下一页' : null,
          selectable: index.isEven && level == 1,
        ),
  ];
}

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
      expect(doc.layerCount, 3);
      expect(doc.radius, 120);
      expect(doc.innerRadius, 40);
      expect(doc.startAngle, -90);
      expect(doc.sweepAngle, 360);
      expect(doc.variant, 'slice');
      expect(doc.itemCount, 3);
    });

    test('改一个字段不许洗掉别的字段（未知键原样留着）', () {
      final doc = parseRadialDoc(_sampleDoc)!;
      final menu = doc.menus.single;
      final next = doc.copyWith(
        layerCount: 2,
        variant: 'bubble',
      ).withMenuReplaced(menu.copyWith(name: '改名了'));
      final decoded = jsonDecode(next.encode()) as Map<String, dynamic>;
      expect(decoded['toUser'], 'keep-me', reason: '文档级的未知键要留着');
      expect((decoded['menus'] as List).first['toRow'], 'keep-too', reason: '轮盘级的也一样');
      expect(decoded['layerCount'], 2);
      expect(decoded['variant'], 'bubble');
      expect(decoded['enabled'], isTrue, reason: '没碰过的开关不该被写没了');
      expect((decoded['menus'] as List).first['name'], '改名了');
    });

    test('生效轮盘指不到时退回第一个（删了没改选中项也不该开不出轮盘）', () {
      final doc = parseRadialDoc(_sampleDoc)!.copyWith(activeMenuId: 'gone');
      expect(doc.activeMenu?.id, 'default');
      expect(doc.menu('nope'), isNull);
    });

    test('每层的条目按层取，缺的层补成空', () {
      final menu = parseRadialDoc(_sampleDoc)!.menus.single;
      expect(menu.layers.length, 3);
      expect(menu.layer(1).map((item) => item.id), [
        'radial-next-page',
        'radial-fullscreen',
      ]);
      expect(menu.layer(2).single.slotIndex, 0);
      expect(menu.layer(3), isEmpty);
      expect(menu.layer(0), isEmpty, reason: '层号 1 起；越界不炸只给空');
      expect(menu.layer(9), isEmpty);
      expect(menu.item('item-9')?.label, '第一页');
      expect(menu.item('nope'), isNull);
      expect(menu.hasItem('radial-fullscreen'), isTrue);
    });

    test('条目上的遗留动作与跳转目标都读得出来', () {
      final menu = RadialMenuDoc({
        'id': 'default',
        'name': '默认轮盘',
        'layers': [
          [
            {'id': 'a', 'label': 'A', 'slotIndex': 0, 'action': 'reader.next-page'},
            {'id': 'b', 'label': 'B', 'slotIndex': 1, 'moveToMenuId': 'two'},
            {'id': 'c', 'label': 'C', 'slotIndex': 2, 'disabled': true},
            {'id': 'd', 'label': 'D', 'slotIndex': 3, 'moveToMenuId': ''},
          ],
        ],
      });
      expect(menu.item('a')!.legacyAction, 'reader.next-page');
      expect(menu.item('b')!.isMoveTo, isTrue);
      expect(menu.item('b')!.moveToMenuId, 'two');
      expect(menu.item('c')!.disabled, isTrue);
      expect(menu.item('d')!.moveToMenuId, isNull, reason: '空串等于没设');
      expect(menu.item('d')!.isMoveTo, isFalse);
    });

    test('加条目 / 换槽位后仍按槽位排序，删条目不留残行', () {
      var menu = RadialMenuDoc({'id': 'default', 'name': '默认轮盘', 'layers': [[]]});
      menu = menu.withItem(RadialItemDoc.create(id: 'item-1', label: '一', slotIndex: 4), level: 1);
      menu = menu.withItem(RadialItemDoc.create(id: 'item-2', label: '二', slotIndex: 1), level: 1);
      expect(menu.layer(1).map((item) => item.slotIndex), isNot([4, 1]), reason: '写回要按槽位排好');
      expect(menu.layer(1).map((item) => item.slotIndex), [1, 4]);
      menu = menu.withItemReplaced(menu.item('item-1')!.copyWith(slotIndex: 0));
      expect(menu.layer(1).map((item) => item.slotIndex), [0, 1]);
      menu = menu.withoutItem('item-2');
      expect(menu.layer(1).map((item) => item.id), ['item-1']);
      expect(menu.itemCount, 1);
    });

    test('条目 id 必须过 neoview 的形状校验', () {
      // 它是落进绑定包的 `itemId`，形状不合法 = 老版本读不懂用户配置。
      // 判据写成可测的函数而不是 assert：assert 在 release 里会被剥掉。
      for (final ok in ['item-1', 'radial-next-page', 'a', 'x_1-2.3']) {
        expect(isRadialItemIdShape(ok), isTrue, reason: '$ok 应当合法');
        expect(RadialItemDoc.create(id: ok, label: '', slotIndex: 0).id, ok);
      }
      for (final bad in ['', '-bad', '.bad', 'a b', 'a/b', 'x' * 81]) {
        expect(isRadialItemIdShape(bad), isFalse, reason: '"$bad" 应当被挡下');
      }
    });
  });

  group('槽位与绑定行', () {
    test('radial descriptor 的形状与核心逐字段一致', () {
      // 核心产的是 `{"device":"radial","menuId":…,"itemId":…}`（model.rs 钉过）。
      // 这里差一个字母，那条绑定就永远匹配不上，而两边看着都正常。
      expect(
        jsonDecode(radialInputJson(menuId: 'default', itemId: 'radial-next-page')),
        {
          'device': 'radial',
          'menuId': 'default',
          'itemId': 'radial-next-page',
        },
      );
    });

    test('同一格只留一条：改写而不是追加，且保住原 id', () {
      final slot = (menuId: 'default', itemId: 'radial-next-page');
      var bindings = bindSlot(<Map<String, dynamic>>[], slot, 'reader.next-page');
      expect(bindings.length, 1);
      expect(actionForSlot(bindings, slot), 'reader.next-page');

      final id = bindings.single['id'];
      bindings = bindSlot(bindings, slot, 'reader.fullscreen');
      expect(bindings.length, 1, reason: '同一格再绑一次是改写，不是第二条（第二条=冲突）');
      expect(bindings.single['id'], id, reason: '改写要保住 id，否则预设前缀认不出来');
      expect(actionForSlot(bindings, slot), 'reader.fullscreen');

      bindings = bindSlot(bindings, slot, '');
      expect(bindings, isEmpty);
      expect(actionForSlot(bindings, slot), isNull);
    });

    test('新行的 context 是 reader，input 是 radial，且默认启用', () {
      final row = bindSlot(
        <Map<String, dynamic>>[],
        (menuId: 'default', itemId: 'item-1'),
        'reader.zoom-in',
      ).single;
      expect(row['context'], 'reader');
      expect(row['enabled'], isTrue);
      expect((row['input'] as Map)['device'], InputDevice.radial);
      expect((row['input'] as Map)['itemId'], 'item-1');
      expect(describeInput(Map<String, dynamic>.from(row['input'] as Map)),
          'radial:default:item-1');
    });

    test('解绑一条不影响别的轮盘的同名条目', () {
      final bindings = [
        buildBinding(
          id: 'a',
          action: 'reader.next-page',
          context: 'reader',
          inputJson: radialInputJson(menuId: 'default', itemId: 'x'),
        ),
        buildBinding(
          id: 'b',
          action: 'reader.last-page',
          context: 'reader',
          inputJson: radialInputJson(menuId: 'two', itemId: 'x'),
        ),
      ];
      final next = unbindSlot(bindings, (menuId: 'default', itemId: 'x'));
      expect(next.map((row) => row['id']), ['b']);
      expect(radialBindingsForMenu(next, 'two').length, 1);
      expect(slotOfBinding(bindings.first), (menuId: 'default', itemId: 'x'));
      expect(slotOfBinding({'id': 'k', 'input': {'device': 'keyboard'}}), isNull);
    });

    test('重置只重写这个轮盘的预设行，用户自绑的一条不动', () {
      final user = buildBinding(
        id: 'user-radial-1',
        action: 'reader.zoom-in',
        context: 'reader',
        inputJson: radialInputJson(menuId: 'default', itemId: 'radial-next-page'),
      );
      final otherWheel = buildBinding(
        id: 'preset-radial-two-l1s0',
        action: 'reader.last-page',
        context: 'reader',
        inputJson: radialInputJson(menuId: 'two', itemId: 'l1s0'),
      );
      final rows = [
        buildBinding(
          id: 'preset-radial-default-radial-fullscreen',
          action: 'reader.fullscreen',
          context: 'reader',
          inputJson: radialInputJson(menuId: 'default', itemId: 'radial-fullscreen'),
        ),
      ];
      final next = resetRadialPresetSlots([user, otherWheel], 'default', rows);
      expect(next.map((row) => row['id']), [
        'user-radial-1',
        'preset-radial-two-l1s0',
        'preset-radial-default-radial-fullscreen',
      ]);
      expect(
        actionForSlot(next, (menuId: 'default', itemId: 'radial-fullscreen')),
        'reader.fullscreen',
      );
    });
  });

  group('画法（与运行时共用同一个 painter）', () {
    test('三层八格的轮盘画得出来，缩放比不会溢出盒子', () {
      final layout = _layoutForPainting();
      expect(layout.length, 24);
      // 第 3 层外缘 = r120 + 2*60 = 240 ⇒ 直径 480，比盒子大 ⇒ 必须缩到装得下。
      final scale = radialFitScale(box: const Size(460, 460), radius: 240);
      expect(scale, lessThan(1.0));
      final painter = RadialWheelPainter(
        slots: layout,
        colors: ColorScheme.fromSeed(seedColor: Colors.teal),
        hoveredItem: 'radial-next-page',
        scale: scale,
        centerLabel: '松手执行',
      );
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(460, 460));
      expect(recorder.endRecording(), isNotNull);
      expect(painter.naturalRadius, 240);
      expect(painter.paintedRadius, closeTo(240 * scale, 1e-6));
      expect(painter.paintedHoleRadius, closeTo(40 * scale, 1e-6));
      expect(
        painter.paintedRadius * 2,
        lessThanOrEqualTo(460.0),
        reason: '缩放后必须装进盒子',
      );
      expect(
        radialFitScale(box: const Size(900, 900), radius: 120),
        1.0,
        reason: '装得下就不放大',
      );
    });

    test('空槽没有 itemId，因此不会被高亮成选中', () {
      final layout = _layoutForPainting();
      final empty = layout.firstWhere((RadialSlotPaint slot) => slot.isEmpty);
      expect(empty.slot, isNull);
      expect(empty.selectable, isFalse);
      final filled = layout.firstWhere((RadialSlotPaint slot) => !slot.isEmpty);
      expect(filled.slot, (menuId: 'default', itemId: 'radial-next-page'));
    });
  });
}
