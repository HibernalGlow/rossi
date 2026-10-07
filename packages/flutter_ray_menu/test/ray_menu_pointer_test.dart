// 轮盘组件的**指针链**判据（只依赖 packages/flutter_ray_menu，不碰 zephyr 树）。
//
// 阅读器浮层依赖的四件事：
//   ① 唤出指针的**抬起**必须落到组件上（Flutter 对进行中的指针复用按下时的命中路径，
//      所以浮层只能靠「组件自己的全局路由」或「宿主转交」拿到这次手势的后续事件）；
//   ② 松开在某一格 = 执行那一格；松开在中心空洞 = 取消；
//   ③ 按下-松开之间没移动 = 不执行也不关（手快的人不算取消）；
//   ④ 轮盘开着时再按一次右键 = 关掉它，且不执行指针下那一格。
//
// ① 有两条来路，两条都要成立，而且**同时成立时不能执行两遍**：
//   - 传 `openingPointer`：组件自己注册全局路由；
//   - 宿主转交 `handlePointerEvent`：宿主握着指针路由（阅读器就是这样）。

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_ray_menu/flutter_ray_menu.dart';
import 'package:flutter_test/flutter_test.dart';

/// 与阅读器同一形状：**按下就开**，并把这次手势的 pointer id 交进去。
class _Host extends StatefulWidget {
  const _Host({
    required this.onSelected,
    required this.onDismiss,
    this.passesOpeningPointer = true,
    this.forwardsFromHost = false,
  });

  final ValueChanged<RayMenuItem> onSelected;
  final VoidCallback onDismiss;

  /// 把唤出指针交给组件（组件自己注册全局路由）。
  final bool passesOpeningPointer;

  /// 宿主自己把那根指针的 move/up/cancel 转交进来（阅读器那条路）。
  final bool forwardsFromHost;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final _controller = RayMenuController();
  OverlayEntry? _entry;
  int? _openingPointer;
  var _moved = false;

  static const _origin = Offset(20, 20);
  static const _center = Offset(200, 200);

  static final _rings = [
    RayMenuRing(
      slotCount: 4,
      items: const [
        RayMenuItem(id: 'up', label: '上', slot: 0),
        RayMenuItem(id: 'right', label: '右', slot: 1),
        RayMenuItem(id: 'down', label: '下', slot: 2),
        RayMenuItem(id: 'left', label: '左', slot: 3),
      ],
    ),
  ];

  void _open(int pointer, Offset position) {
    _openingPointer = pointer;
    _moved = false;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => RayMenu(
        controller: _controller,
        rings: _rings,
        geometry: const RayMenuGeometry(
          radius: 140,
          innerRadius: 40,
          ringWidth: 60,
        ),
        center: _center,
        openingPointer: widget.passesOpeningPointer ? pointer : null,
        openingPosition: position,
        keyboardEnabled: false,
        onSelected: (item) {
          _entry = null;
          _openingPointer = null;
          entry.remove();
          widget.onSelected(item);
        },
        onDismiss: () {
          _entry = null;
          _openingPointer = null;
          entry.remove();
          widget.onDismiss();
        },
      ),
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  /// 阅读器那一层：唤出指针的 move/up/cancel 由看得见它的宿主转交。
  void _forward(PointerEvent event) {
    final pointer = _openingPointer;
    if (pointer == null || event.pointer != pointer) return;
    if (event is PointerMoveEvent &&
        (event.position - _origin).distance >= kTouchSlop) {
      _moved = true;
    }
    if (event is PointerUpEvent && !_moved) return;
    _controller.handlePointerEvent(event);
  }

  @override
  void dispose() {
    _entry?.remove();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (event) => _open(event.pointer, event.position),
    onPointerMove: widget.forwardsFromHost ? _forward : null,
    onPointerUp: widget.forwardsFromHost ? _forward : null,
    onPointerCancel: widget.forwardsFromHost ? _forward : null,
    child: const SizedBox.expand(),
  );
}

Offset _slotCenter(WidgetTester tester, String id) =>
    tester.getCenter(find.byKey(ValueKey('ray-item:$id')));

/// 装好宿主（宿主自己就在 Overlay 里，和阅读器一样），再按下唤出。
Future<TestGesture> _openMenu(
  WidgetTester tester,
  List<String> selected,
  List<int> dismissed, {
  bool passesOpeningPointer = true,
  bool forwardsFromHost = false,
}) async {
  await _pumpHost(tester, selected, dismissed, forwardsFromHost: forwardsFromHost);
  final mouse = await tester.startGesture(
    const Offset(20, 20),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
  expect(find.byType(RayMenu), findsOneWidget, reason: '按下就该开出轮盘');
  return mouse;
}

Future<void> _pumpHost(
  WidgetTester tester,
  List<String> selected,
  List<int> dismissed, {
  bool passesOpeningPointer = true,
  bool forwardsFromHost = true,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (context) => _Host(
              passesOpeningPointer: passesOpeningPointer,
              forwardsFromHost: forwardsFromHost,
              onSelected: (item) => selected.add(item.id),
              onDismiss: () => dismissed.add(1),
            ),
          ),
        ],
      ),
    ),
  );
  await tester.pump();
}

void main() {
  const routes = <String, (bool passesOpeningPointer, bool forwardsFromHost)>{
    '组件全局路由': (true, false),
    '宿主转交': (false, true),
    '两条路都在（生产形态）': (true, true),
  };

  for (final entry in routes.entries) {
    final label = entry.key;
    final (passesOpeningPointer, forwardsFromHost) = entry.value;

    Future<TestGesture> open(
      WidgetTester tester,
      List<String> selected,
      List<int> dismissed,
    ) => _openMenu(
      tester,
      selected,
      dismissed,
      passesOpeningPointer: passesOpeningPointer,
      forwardsFromHost: forwardsFromHost,
    );

    testWidgets('[$label] 按下唤出 → 拖到某一格 → 松手即执行', (tester) async {
      final selected = <String>[];
      final dismissed = <int>[];
      final mouse = await open(tester, selected, dismissed);
      await mouse.moveTo(_slotCenter(tester, 'right'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('ray-item:right')))
            .properties
            .selected,
        isTrue,
        reason: '拖到哪一格就该高亮哪一格',
      );
      await mouse.up();
      await tester.pumpAndSettle();
      expect(selected, ['right'], reason: '松手应当确认当前槽，而且只确认一次');
      expect(dismissed, isEmpty);
    });

    testWidgets('[$label] 按下唤出但没移动 → 松手不执行也不关', (tester) async {
      final selected = <String>[];
      final dismissed = <int>[];
      final mouse = await open(tester, selected, dismissed);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      expect(dismissed, isEmpty);
      expect(find.byType(RayMenu), findsOneWidget);
    });

    testWidgets('[$label] 中心空洞里松手 = 取消', (tester) async {
      final selected = <String>[];
      final dismissed = <int>[];
      final mouse = await open(tester, selected, dismissed);
      await mouse.moveTo(const Offset(212, 200));
      await tester.pumpAndSettle();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      expect(dismissed, [1]);
    });

    testWidgets('[$label] 另一次点击落在某一格 = 执行', (tester) async {
      final selected = <String>[];
      final dismissed = <int>[];
      final mouse = await open(tester, selected, dismissed);
      await mouse.up();
      await tester.pumpAndSettle();
      await tester.tapAt(_slotCenter(tester, 'down'));
      await tester.pumpAndSettle();
      expect(selected, ['down']);
      expect(dismissed, isEmpty);
    });

    testWidgets('[$label] 轮盘开着时再按一次右键 = 关掉，且不执行指针下那一格', (tester) async {
      final selected = <String>[];
      final dismissed = <int>[];
      final mouse = await open(tester, selected, dismissed);
      await mouse.up();
      await tester.pumpAndSettle();
      final again = await tester.startGesture(
        _slotCenter(tester, 'up'),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await again.up();
      await tester.pumpAndSettle();
      expect(dismissed, [1], reason: '第二次右键应当关掉轮盘');
      expect(selected, isEmpty, reason: '关掉的那一下不该顺手执行指针下的那一格');
    });
  }

  // 真实鼠标的 pointer id 约定：hover 与每一次按下/抬起是**不同**的 id，而按下与抬起
  // 挤在同一帧时，浮层还没挂载 —— 唤出那一次的抬起组件整条都看不见。
  // `TestGesture` 一整条手势只用一个 id，测不出这两种情况，所以这里发裸事件。
  group('真实鼠标的 pointer id', () {
    const viewId = 0;
    const origin = Offset(20, 20);

    PointerHoverEvent hover(int pointer, Offset at) => PointerHoverEvent(
      viewId: viewId,
      pointer: pointer,
      position: at,
      kind: PointerDeviceKind.mouse,
    );
    PointerDownEvent press(int pointer, Offset at, int buttons) =>
        PointerDownEvent(
          viewId: viewId,
          pointer: pointer,
          position: at,
          buttons: buttons,
          kind: PointerDeviceKind.mouse,
        );
    PointerUpEvent release(int pointer, Offset at) => PointerUpEvent(
      viewId: viewId,
      pointer: pointer,
      position: at,
      kind: PointerDeviceKind.mouse,
    );

    /// 右键按下把轮盘开出来；[sameFrameRelease] = 抬起紧跟在同一个批次里（挂载之前）。
    Future<void> rightPress(
      WidgetTester tester, {
      required int pointer,
      bool sameFrameRelease = false,
    }) async {
      await tester.sendEventToBinding(
        PointerAddedEvent(
          viewId: viewId,
          pointer: 1,
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.sendEventToBinding(hover(1, origin));
      await tester.sendEventToBinding(press(pointer, origin, kSecondaryButton));
      if (sameFrameRelease) {
        await tester.sendEventToBinding(release(pointer, origin));
      }
      await tester.pumpAndSettle();
      if (!sameFrameRelease) {
        await tester.sendEventToBinding(release(pointer, origin));
      }
      await tester.pumpAndSettle();
      expect(find.byType(RayMenu), findsOneWidget, reason: '轮盘该开出来');
    }

    testWidgets('hover 到某一格 → 左键单击即执行', (tester) async {
      final selected = <String>[];
      final dismissed = <int>[];
      await _pumpHost(tester, selected, dismissed);
      await rightPress(tester, pointer: 2);

      final target = _slotCenter(tester, 'down');
      await tester.sendEventToBinding(hover(1, target));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('ray-item:down')))
            .properties
            .selected,
        isTrue,
        reason: '不按住、只是移过去，也该高亮那一格',
      );
      await tester.sendEventToBinding(press(3, target, kPrimaryButton));
      await tester.sendEventToBinding(release(3, target));
      await tester.pumpAndSettle();
      expect(selected, ['down']);
      expect(dismissed, isEmpty);
    });

    testWidgets('唤出的抬起早于浮层挂载 → 之后左键单击仍然可用', (
      tester,
    ) async {
      final selected = <String>[];
      final dismissed = <int>[];
      await _pumpHost(tester, selected, dismissed);
      // 按下与抬起之间一帧都不给：组件既没注册全局路由，也还没进命中路径。
      await rightPress(tester, pointer: 2, sameFrameRelease: true);

      final target = _slotCenter(tester, 'right');
      await tester.sendEventToBinding(hover(1, target));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('ray-item:right')))
            .properties
            .selected,
        isTrue,
        reason: '高亮照旧跟着鼠标走 —— 这正是它容易被误判成「没坏」的地方',
      );
      await tester.sendEventToBinding(press(3, target, kPrimaryButton));
      await tester.sendEventToBinding(release(3, target));
      await tester.pumpAndSettle();
      expect(
        selected,
        ['right'],
        reason: '漏掉一次抬起不能把后面所有点击永久挡死',
      );
    });

    testWidgets('右键按住拖到某一格 → 松手即执行', (tester) async {
      final selected = <String>[];
      final dismissed = <int>[];
      await _pumpHost(tester, selected, dismissed);
      await tester.sendEventToBinding(
        PointerAddedEvent(
          viewId: viewId,
          pointer: 1,
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.sendEventToBinding(hover(1, origin));
      await tester.sendEventToBinding(press(2, origin, kSecondaryButton));
      await tester.pumpAndSettle();
      final target = _slotCenter(tester, 'up');
      await tester.sendEventToBinding(
        PointerMoveEvent(
          viewId: viewId,
          pointer: 2,
          position: target,
          buttons: kSecondaryButton,
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendEventToBinding(release(2, target));
      await tester.pumpAndSettle();
      expect(selected, ['up']);
      expect(dismissed, isEmpty);
    });
  });
}
