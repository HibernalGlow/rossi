import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_list/scene_filter/plugin_list_filter_dialog.dart';
import 'package:zephyr/page/comic_list/scene_filter/plugin_list_filter_schema.dart';

void main() {
  test('parses dropdown filter field and resolves defaults', () {
    final schema = PluginListFilterSchema.fromMap({
      'title': '筛选',
      'fields': [
        {
          'key': 'week',
          'kind': 'dropdown',
          'label': '更新时间',
          'options': [
            {
              'label': '第2期',
              'value': 'w2',
              'result': {
                'core': {'week': 'w2'},
              },
            },
            {
              'label': '第1期',
              'value': 'w1',
              'result': {
                'core': {'week': 'w1'},
              },
            },
          ],
        },
        {
          'key': 'type',
          'kind': 'choice',
          'label': '分类',
          'options': [
            {
              'label': '日漫',
              'value': 'manga',
              'result': {
                'core': {'type': 'manga'},
              },
            },
          ],
        },
      ],
    });

    final resolved = schema.resolve(
      requestedSelections: const {'week': 'w2'},
      defaultSelections: const {'week': 'w1', 'type': 'manga'},
    );

    expect(resolved.selections, {'week': 'w2', 'type': 'manga'});
    expect(resolved.core, {'week': 'w2', 'type': 'manga'});
  });

  testWidgets('filter dialog dropdown selects options and renders children', (
    tester,
  ) async {
    final schema = PluginListFilterSchema.fromMap({
      'title': '筛选',
      'fields': [
        {
          'key': 'week',
          'kind': 'dropdown',
          'label': '更新时间',
          'options': [
            for (var i = 0; i < 30; i++)
              {'label': '第${i + 1}期', 'value': 'w${i + 1}', 'result': {}},
          ],
        },
        {
          'key': 'type',
          'kind': 'dropdown',
          'label': '分类',
          'options': [
            {
              'label': '日漫',
              'value': 'manga',
              'result': {},
              'children': [
                {'label': '汉化', 'value': 'manga_cn', 'result': {}},
              ],
            },
          ],
        },
      ],
    });

    Map<String, String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<Map<String, String>>(
                    context: context,
                    builder: (context) => PluginListFilterDialog(
                      scheme: schema,
                      initialSelections: const {'week': 'w1', 'type': 'manga'},
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('更新时间'), findsOneWidget);
    expect(find.text('第1期'), findsOneWidget);

    await tester.tap(find.text('第1期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第2期'));
    await tester.pumpAndSettle();
    expect(find.text('第2期'), findsOneWidget);

    // children 选项以缩进项直接渲染，可直接选中。
    await tester.tap(find.text('日漫'));
    await tester.pumpAndSettle();
    expect(find.textContaining('汉化'), findsOneWidget);
    await tester.tap(find.textContaining('汉化'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result, {'week': 'w2', 'type': 'manga_cn'});
  });
  testWidgets('back closes the dropdown before the filter dialog', (
    tester,
  ) async {
    final schema = PluginListFilterSchema.fromMap({
      'title': '筛选',
      'fields': [
        {
          'key': 'week',
          'kind': 'dropdown',
          'label': '更新时间',
          'options': [
            {'label': '第2期', 'value': 'w2', 'result': {}},
            {'label': '第1期', 'value': 'w1', 'result': {}},
          ],
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showDialog<Map<String, String>>(
                    context: context,
                    builder: (context) => PluginListFilterDialog(
                      scheme: schema,
                      initialSelections: const {'week': 'w1'},
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第1期'));
    await tester.pumpAndSettle();
    expect(find.text('第2期'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('第2期'), findsNothing);
    expect(find.text('确定'), findsOneWidget);
  });
}
