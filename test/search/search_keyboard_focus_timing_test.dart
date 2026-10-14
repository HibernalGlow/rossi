import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/bookshelf/widgets/shelf_search_field.dart';
import 'package:zephyr/page/bookshelf/widgets/shelf_search_header.dart';
import 'package:zephyr/page/search/widget/search_input_dialog.dart';

/// 点击搜索框到「框架向系统请求键盘」之间的等待时间。
///
/// 键盘真正弹出是系统侧的事，测不到；但 `requestFocus()` 与随后打在
/// `SystemChannels.textInput` 上的 `TextInput.show` 是本仓能控制的
/// 那半段。假时钟逐帧推进，把毫秒数和通道调用序列打印出来。
void main() {
  /// 逐帧推进，返回 (输入框上树, 焦点落位) 两个毫秒数，未发生记 -1。
  Future<(int, int)> pumpUntilFocus(WidgetTester tester) async {
    var elapsed = 0;
    var appeared = -1;
    FocusNode? node;
    var focused = -1;
    while (elapsed < 3000 && focused < 0) {
      await tester.pump(const Duration(milliseconds: 16));
      elapsed += 16;
      if (node == null && find.byType(EditableText).evaluate().isNotEmpty) {
        node = tester.widget<EditableText>(find.byType(EditableText)).focusNode;
        appeared = elapsed;
      }
      if (node != null && node.hasFocus) focused = elapsed;
    }
    return (appeared, focused);
  }

  void report(String name, int appeared, int focused) {
    // ignore: avoid_print
    print('[timing] $name 输入框上树：$appeared ms → 发出键盘请求：$focused ms');
  }

  Widget app(Widget home) => MaterialApp(home: home);

  Widget searchPage() => Scaffold(
    body: SearchQueryField(query: '', autoExpand: true, onSubmitted: (_) {}),
  );

  testWidgets('A 浮层路径：点 pill 到发出键盘请求', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.useDeviceLocale());

    await tester.pumpWidget(
      app(
        Scaffold(body: SearchQueryField(query: '', onSubmitted: (_) {})),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SearchQueryField));
    final (appeared, focused) = await pumpUntilFocus(tester);
    report('A pill 点击', appeared, focused);
  });

  Future<void> pushAndMeasure(
    WidgetTester tester,
    String name,
    Route<Object?> Function() route,
  ) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.useDeviceLocale());

    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(route()),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('go'));
    final (appeared, focused) = await pumpUntilFocus(tester);
    report('$name 进页(autoExpand)', appeared, focused);
  }

  testWidgets('B autoExpand：带转场路由进页', (tester) async {
    await pushAndMeasure(
      tester,
      'B',
      () => MaterialPageRoute(builder: (_) => searchPage()),
    );
  });

  /// 书架移动端：表头图标触发展开，内联输入框挂载后 autofocus。
  Future<void> pumpShelf(WidgetTester tester, FocusNode focus) async {
    var expanded = false;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, refresh) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => refresh(() => expanded = true),
                  child: const Text('open shelf search'),
                ),
                ShelfSearchRegion(
                  expanded: expanded,
                  child: ShelfSearchField(
                    query: '',
                    focusNode: focus,
                    hintText: 'hint',
                    onChanged: (_) {},
                    onSubmitted: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('D 书架内联：点搜索图标到发出键盘请求', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.useDeviceLocale());

    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pumpShelf(tester, focus);

    await tester.tap(find.text('open shelf search'));
    final (appeared, focused) = await pumpUntilFocus(tester);
    report('D 书架内联展开', appeared, focused);
  });

  /// 把 `SystemChannels.textInput` 换成记录器：键盘请求的真实发出口。
  ({List<String> calls, void Function(int ms) advance}) watchTextInput(
    WidgetTester tester,
  ) {
    final calls = <String>[];
    var clock = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        calls.add('$clock ms ${call.method}');
        return null;
      },
    );
    return (calls: calls, advance: (ms) => clock += ms);
  }

  testWidgets('E 书架内联：点图标后输入通道的调用时序', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.useDeviceLocale());

    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pumpShelf(tester, focus);

    final watch = watchTextInput(tester);
    await tester.tap(find.text('open shelf search'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      watch.advance(16);
    }
    // ignore: avoid_print
    print('[timing] E 点图标 → 通道序列：${watch.calls.join(' | ')}');
  });

  testWidgets('F 书架内联：已挂载的输入框再点一次的通道时序', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.useDeviceLocale());

    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pumpShelf(tester, focus);

    // 先走一次展开 + autofocus，把它推到「栏已展开、键盘已收起」的状态。
    await tester.tap(find.text('open shelf search'));
    await tester.pumpAndSettle();
    focus.unfocus();
    await tester.pumpAndSettle();

    final watch = watchTextInput(tester);
    await tester.tap(find.byType(TextField));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      watch.advance(16);
    }
    // ignore: avoid_print
    print(
      '[timing] F 点已挂载输入框 → 通道序列：${watch.calls.join(' | ')} '
      '落焦=${focus.hasFocus}',
    );
  });
}
