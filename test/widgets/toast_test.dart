import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/util/toast/toast_style.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/widgets/toast/toast_card.dart';

/// 提示条渲染与宿主的判据。
///
/// 这一层要钉住的是**改造前的真实症状**：下载完成那类长文件名（`[Fanbox(Normal) & Pixiv]
/// pazzimo [ZZR个人汉化] 下载完成`）在旧实现里因为正文 ≥ 30 字被换成了
/// 「成功 / 取消 / 确定」的模态对话框。现在必须一律是提示条，且正文自己换行。
void main() {
  setUp(ToastOverlayController.instance.resetForTest);
  tearDown(ToastOverlayController.instance.resetForTest);

  testWidgets('长正文在提示条内换行，不再截断', (tester) async {
    const message = '[Fanbox(Normal) & Pixiv] pazzimo [ZZR个人汉化] 下载完成';
    final spec = resolveToastOverlaySpec(const ToastSettingState());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ToastCard(
                type: ToastType.success,
                message: message,
                spec: spec,
                onDismiss: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text(message), findsOneWidget);
    // 单行高约 17.5px；能在 360 宽里折行才会超过 25px。
    expect(
      tester.getSize(find.text(message)).height,
      greaterThan(25),
      reason: '正文必须自己换行，而不是被截断或退化成对话框',
    );
    expect(tester.widget<Text>(find.text(message)).maxLines, isNull);

    // 别把倒计时留在测试里：让它自然走完。
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('常驻提示：没有进度条，但保留关闭按钮', (tester) async {
    final spec = resolveToastOverlaySpec(
      const ToastSettingState(durationMs: 0, showCloseButton: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ToastCard(
              type: ToastType.warning,
              message: '这条不会自己消失',
              spec: spec,
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(FractionallySizedBox), findsNothing);
    expect(find.byIcon(Icons.close), findsOneWidget);
    // 常驻没有动画控制器，这里 pump 多久都不该有副作用。
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('这条不会自己消失'), findsOneWidget);
  });

  testWidgets('按设置关掉开关后，图标与关闭按钮都不渲染', (tester) async {
    final spec = resolveToastOverlaySpec(
      const ToastSettingState(showIcon: false, showCloseButton: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ToastCard(
              type: ToastType.info,
              message: '纯文本提示',
              spec: spec,
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.info_outline), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('调用提示接口后，提示挂到根 Overlay 上并且可以关掉', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showSuccessToast('保存成功', context: context),
                child: const Text('触发'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('触发'));
    await tester.tap(find.text('触发'));
    await tester.pump(); // 插入 OverlayEntry（首帧还是「收起」状态）
    await tester.pump(); // 翻成展开，隐式动画在这里起跑
    await tester.pump(const Duration(milliseconds: 400)); // 动画走完

    expect(find.byType(ToastCard), findsOneWidget);
    expect(find.text('保存成功'), findsOneWidget);

    // 默认停在右上、距边缘 12px：动画结束后卡片右边缘必须留出这段空白。
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final rect = tester.getRect(find.byType(ToastCard));
    expect(rect.right, lessThanOrEqualTo(screenWidth - 12 + 0.5));
    expect(rect.top, lessThan(120));

    // 关闭按钮能立刻收起（走完退场动画后从树上摘掉）。
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('保存成功'), findsNothing);
    expect(ToastOverlayController.instance.toasts, isEmpty);
  });
}
