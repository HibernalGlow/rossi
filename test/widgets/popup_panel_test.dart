// 弹出层（`PopupPanel` / `CommonPopupBox` / 出场方式判定）的判据。
//
// # 判据钉的是什么
//
// 1. **面板永不铺满整屏** —— 这是这条弹层最硬的一条口径：改造前全仓弹层都是
//    `AlertDialog`（卡片），所以「铺满」在任何尺寸、任何一种出场方式下都不许
//    再出现。判据直接量矩形：宽度不超过卡片档上限、也不等于屏幕宽。
// 2. **出场方式判定**（纯函数）：声明 modal 的一律走「全屏遮罩 + 居中」，
//    声明 relative 的只在宽屏上相对弹出 —— 窄屏（移动端）保持改造前的样子。
// 3. **modal 档真的居中**：这是改造前 `showDialog` 的唯一落点，偏了就是换了张脸。
// 4. **关掉时带出来的值回到调用方**：`CommonPopupBox` 的 `open()` 与
//    `showPopupPanel` 的返回值都是这一次的选择结果，筛选项就是靠它落账的。
//
// 不钉动效本身（弹簧手感没有数值判据，同 `spring_lens_bar_test.dart` 头部口径），
// 只钉「停稳之后面板在哪儿、多大」。

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/widgets/common_popup.dart';
import 'package:zephyr/widgets/popup_panel.dart';

/// 一个最小宿主：一颗按钮，按下去弹 `PopupPanel`。
///
/// `applyValue` 为 null 表示「取消」（`pop()` 不带值）。
Widget _host({
  PopupPresentation presentation = PopupPresentation.modal,
  int? applyValue = 7,
  void Function(int? value)? onResult,
  /// 走 [`CommonPopupBox`]（锚在按钮上）而不是 [`showPopupPanel`]。
  bool boxed = false,
}) {
  Widget panel(BuildContext popupContext) => PopupPanel(
    title: const Text('panel-title'),
    content: const Text('panel-body'),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(popupContext).pop(applyValue),
        child: const Text('panel-apply'),
      ),
      TextButton(
        onPressed: () => Navigator.of(popupContext).pop(),
        child: const Text('panel-cancel'),
      ),
    ],
  );

  return BlocProvider<GlobalSettingCubit>(
    create: (_) => GlobalSettingCubit(),
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) {
              if (boxed) {
                return CommonPopupBox<int>(
                  targetBuilder: (open) => TextButton(
                    onPressed: () async {
                      final value = await open();
                      onResult?.call(value);
                    },
                    child: const Text('open'),
                  ),
                  popupBuilder: panel,
                );
              }
              return TextButton(
                onPressed: () async {
                  final value = await showPopupPanel<int>(
                    context: context,
                    presentation: presentation,
                    builder: panel,
                  );
                  onResult?.call(value);
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ),
  );
}

Future<void> _openPanel(WidgetTester tester, String trigger) async {
  await tester.tap(find.text(trigger));
  await tester.pumpAndSettle();
}

/// 把测试窗口定死（`physicalSize` × `devicePixelRatio` = 逻辑尺寸）。
Future<void> _resize(WidgetTester tester, Size logical) async {
  tester.view.physicalSize = logical;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('resolvePopupRelative', () {
    test('modal 一律不相对弹出 —— 不看尺寸', () {
      for (final width in <double>[320, 599, 600, 1200, 2560]) {
        expect(
          resolvePopupRelative(
            presentation: PopupPresentation.modal,
            width: width,
          ),
          isFalse,
          reason: 'width=$width',
        );
      }
    });

    test('relative 只在宽屏上生效，窄屏保持改造前的样子', () {
      // 阈值与导航栏的窄屏口径同源，600 是「不算窄」的那一侧。
      expect(
        resolvePopupRelative(
          presentation: PopupPresentation.relative,
          width: 599,
        ),
        isFalse,
      );
      expect(
        resolvePopupRelative(
          presentation: PopupPresentation.relative,
          width: 600,
        ),
        isTrue,
      );
      for (final width in <double>[600, 1200]) {
        expect(
          resolvePopupRelative(
            presentation: PopupPresentation.relative,
            width: width,
          ),
          isTrue,
          reason: 'width=$width',
        );
      }
    });
  });

  group('面板永不铺满整屏', () {
    // 两轴 × 两档：任何一种组合下，面板都必须明显小于整屏。
    for (final size in <Size>[Size(400, 800), Size(800, 600)]) {
      for (final presentation in PopupPresentation.values) {
        testWidgets('${size.width}×${size.height} · ${presentation.name}', (
          tester,
        ) async {
          await _resize(tester, size);
          await tester.pumpWidget(_host(presentation: presentation));
          await _openPanel(tester, 'open');

          final rect = tester.getRect(find.byType(PopupPanel));
          expect(find.text('panel-title'), findsOneWidget);
          // ① 宽度不超过卡片档上限（旧的 `SizedBox(width: 420)` 同一档）。
          expect(rect.width, lessThanOrEqualTo(PopupPanel.cardMaxWidth + 0.01));
          // ② 也不是整屏 —— 这一条正是改造时踩过的坑。
          expect(
            rect.width < size.width || rect.height < size.height,
            isTrue,
            reason: '面板铺满了整屏：$rect / $size',
          );
        });
      }
    }

    testWidgets('窄屏上 relative 同样不铺满（移动端不改）', (tester) async {
      await _resize(tester, const Size(400, 800));
      await tester.pumpWidget(
        _host(presentation: PopupPresentation.relative),
      );
      await _openPanel(tester, 'open');

      final rect = tester.getRect(find.byType(PopupPanel));
      expect(rect.width, lessThan(400));
      expect(rect.height, lessThan(800));
    });
  });

  group('modal 档是改造前那张脸', () {
    testWidgets('居中在屏幕正中', (tester) async {
      await _resize(tester, const Size(800, 600));
      await tester.pumpWidget(_host());
      await _openPanel(tester, 'open');

      final rect = tester.getRect(find.byType(PopupPanel));
      expect(rect.center.dx, closeTo(400, 0.5));
      expect(rect.center.dy, closeTo(300, 0.5));
    });
  });

  group('关掉时带出来的值', () {
    testWidgets('showPopupPanel 把这一次的选择还给调用方', (tester) async {
      final received = <int?>[];
      await tester.pumpWidget(_host(onResult: received.add));
      await _openPanel(tester, 'open');

      await tester.tap(find.text('panel-apply'));
      await tester.pumpAndSettle();

      expect(received, <int>[7]);
      expect(find.text('panel-title'), findsNothing);
    });

    testWidgets('取消（pop 不带值）时给出 null —— 与「选了 0」分得开', (tester) async {
      final received = <int?>[];
      await tester.pumpWidget(_host(onResult: received.add));
      await _openPanel(tester, 'open');

      await tester.tap(find.text('panel-cancel'));
      await tester.pumpAndSettle();

      expect(received, <int?>[null]);
    });

    testWidgets('CommonPopupBox 的 open() 同样带得出结果', (tester) async {
      final received = <int?>[];
      await tester.pumpWidget(_host(boxed: true, onResult: received.add));
      await _openPanel(tester, 'open');

      await tester.tap(find.text('panel-apply'));
      await tester.pumpAndSettle();

      expect(received, <int>[7]);
    });
  });
}
