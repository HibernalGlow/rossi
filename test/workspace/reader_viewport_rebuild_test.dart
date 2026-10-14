import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/workspace/widgets/reader/reader_viewport.dart';

class _ProfileNotificationBinding extends AutomatedTestWidgetsFlutterBinding {
  void dispatchLayoutNotification(VoidCallback notify) {
    // Profile 没有这条 debug 检查；其余布局与重建检查照常执行。
    final building = debugBuildingDirtyElements;
    debugBuildingDirtyElements = false;
    try {
      notify();
    } finally {
      debugBuildingDirtyElements = building;
    }
  }
}

class _LayoutNotification extends SingleChildRenderObjectWidget {
  const _LayoutNotification({required this.onLayout});
  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNotification(onLayout);
}

class _RenderNotification extends RenderProxyBox {
  _RenderNotification(this.onLayout);
  final VoidCallback onLayout;
  bool _sent = false;

  @override
  void performLayout() {
    size = constraints.biggest;
    if (!_sent) {
      _sent = true;
      onLayout();
    }
  }
}

void main() {
  final binding = _ProfileNotificationBinding();
  testWidgets('布局期间更新后，阅读视口仍能继续处理悬停重建', (tester) async {
    final value = ValueNotifier(0);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: ReaderViewport(
            child: Stack(
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: value,
                  builder: (_, n, _) => Text('visible:$n'),
                ),
                Positioned.fill(
                  child: _LayoutNotification(
                    onLayout: () {
                      // 模拟 Profile 的现场：布局期间的通知不会被 debug 的
                      // “Build scheduled during frame” 检查提前中断。保留其他渲染断言，
                      // 普通 LayoutBuilder 会在此把自己重新标脏并卡住后续更新。
                      binding.dispatchLayoutNotification(() => value.value = 1);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('visible:1'), findsOneWidget);
    value.value = 2;
    await tester.pump();
    expect(find.text('visible:2'), findsOneWidget);
  });
}
