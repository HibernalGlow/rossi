// 机制判据：`InteractiveViewer.scaleEnabled` 与「外层 GestureDetector 能不能收到单击」。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/comic_read/interactive_viewer_tap_steal_test.dart
//
// 为什么单独为这条写判据：阅读器把单击分区挂在 `InteractiveViewer` **外层**的
// `GestureDetector` 上（`reader_input_controller.dart` 的 buildInteractiveViewer），
// 而 `scaleEnabled` 的表达式是 `!_isDesktopPlatform || 双指 || 已放大`
// —— 安卓那一带**恒真**。手指按下时缩放识别器一旦当场接受，同一个序列里的
// 单击识别器就被逐出战场，表现就是「点哪儿都没反应」（翻页、点中间唤出上下栏
// 全部失效）。桌面端 `scaleEnabled` 默认假，所以这条永远暴露不出来 ——
// 真机报上来的症状与它逐字吻合，但**症状本身不是证据**，故在此钉死。
//
// 手指事件一律用 `PointerDeviceKind.touch` 显式造（down 这一步不能省 ——
// 只 `addPointer` 发的是 PointerAddedEvent，整场根本没有点击，两条断言都会拿到 0，
// 第一版就是这么假红的）：本判据唯一关心的变量就是「这一序列归谁」。
// ignore_for_file: avoid_print
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用一根手指单击中心，返回外层 `GestureDetector.onTap` 收到的次数。
Future<int> _tapOnce(WidgetTester tester, {required bool scaleEnabled}) async {
  var taps = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 300,
          height: 300,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: InteractiveViewer(
              scaleEnabled: scaleEnabled,
              child: const ColoredBox(
                color: Colors.blue,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final center = tester.getCenter(find.byType(InteractiveViewer));
  final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
  addTearDown(gesture.removePointer);
  await gesture.addPointer(location: center);
  await tester.pump();
  await gesture.down(center);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
  return taps;
}

void main() {
  testWidgets('scaleEnabled 为真：外层 onTap 收不到这一下单击', (tester) async {
    expect(await _tapOnce(tester, scaleEnabled: true), 0,
        reason: '缩放识别器当场接受 ⇒ 序列不再归单击识别器');
  });

  testWidgets('scaleEnabled 为假：同一坐标同一手指，onTap 收得到', (tester) async {
    expect(await _tapOnce(tester, scaleEnabled: false), 1,
        reason: '阳性对照 —— 少了这一条，上一条的 0 可能来自任何别的原因');
  });
}
