import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ray_menu/flutter_ray_menu.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/radial/expressive_ray_menu.dart';
import 'package:zephyr/widgets/radial/radial_focus_surface.dart';

final _rings = [
  for (var ring = 0; ring < 3; ring++)
    RayMenuRing(
      slotCount: 8,
      items: [
        for (final slot in [0, 2, 4, 6])
          RayMenuItem(
            id: '$ring:$slot',
            slot: slot,
            label: '操作 $ring·$slot',
            icon: const Icon(Icons.settings),
            enabled: slot != 6,
          ),
      ],
    ),
];

Future<void> pumpMenu(
  WidgetTester tester, {
  required List<String> selected,
  required List<bool> dismissed,
  RayMenuController? controller,
  bool reduced = false,
  Size size = const Size(640, 640),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: reduced),
        child: ExpressiveRayMenu(
          rings: _rings,
          controller: controller,
          geometry: const RayMenuGeometry(),
          style: const RayMenuStyle(),
          onSelected: (item) => selected.add(item.id),
          onDismiss: () => dismissed.add(true),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect visualRect(WidgetTester tester, String id) {
  final box = tester.renderObject<RenderBox>(
    find.byKey(ValueKey('ray-item:$id')),
  );
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

void main() {
  testWidgets('连续悬停有惯性，停下后稳定，按下冻结几何并执行同一项', (tester) async {
    final selected = <String>[];
    final dismissed = <bool>[];
    await pumpMenu(tester, selected: selected, dismissed: dismissed);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    final target = visualRect(tester, '2:2').center;
    final before = visualRect(tester, '2:2');
    await pointer.moveTo(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final during = visualRect(tester, '2:2');
    expect(during.width, greaterThan(before.width));
    await pointer.down(target);
    final pressed = visualRect(tester, '2:2');
    await tester.pump(const Duration(milliseconds: 300));
    expect(visualRect(tester, '2:2'), pressed);
    await pointer.up();
    await tester.pumpAndSettle();
    expect(selected, ['2:2']);
    expect(dismissed, isEmpty);
    final settled = visualRect(tester, '2:2');
    await tester.pump(const Duration(seconds: 2));
    expect(visualRect(tester, '2:2'), settled);
    await pointer.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('按住拖动后松手执行一次，空白处和右键取消', (tester) async {
    final selected = <String>[];
    final dismissed = <bool>[];
    await pumpMenu(tester, selected: selected, dismissed: dismissed);
    final mouse = await tester.startGesture(
      const Offset(320, 320),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveTo(visualRect(tester, '1:0').center);
    await tester.pumpAndSettle();
    await mouse.up();
    await tester.pumpAndSettle();
    expect(selected, ['1:0']);
    final surface = tester.state<RadialFocusSurfaceState>(
      find.byType(RadialFocusSurface),
    );
    expect(surface.hitTest(const Offset(8, 8)), isNull);
    await tester.tapAt(const Offset(8, 8));
    expect(dismissed, [true]);
    final again = await tester.startGesture(
      visualRect(tester, '0:0').center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await again.up();
    expect(dismissed, [true, true]);
    expect(selected, ['1:0']);
  });

  testWidgets('键盘能聚焦外围按钮并确认，减少动画立即落位', (tester) async {
    final selected = <String>[];
    final dismissed = <bool>[];
    final controller = RayMenuController();
    addTearDown(controller.dispose);
    await pumpMenu(
      tester,
      selected: selected,
      dismissed: dismissed,
      controller: controller,
      reduced: true,
      size: const Size(360, 640),
    );
    controller.moveSelection(1);
    controller.moveRing(1);
    controller.moveRing(1);
    await tester.pump();
    final item = controller.selectedItem!;
    expect(visualRect(tester, item.id).width, greaterThanOrEqualTo(48));
    final semantics = tester
        .widget<Semantics>(find.byKey(ValueKey('ray-item:${item.id}')))
        .properties;
    expect(semantics.button, isTrue);
    expect(semantics.selected, isTrue);
    expect(semantics.onTap, isNotNull);
    controller.confirm();
    expect(selected, [item.id]);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(dismissed, [true]);
  });
}
