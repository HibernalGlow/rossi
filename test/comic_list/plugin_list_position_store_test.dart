import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/page/comic_list/service/plugin_list_position_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('参数顺序不影响身份，插件和筛选条件互相隔离', () async {
    final a = pluginListPositionScope(
      'a',
      'latest',
      {'page': 1, 'sort': 'new'},
      {'category': 'all'},
    );
    expect(
      a,
      pluginListPositionScope(
        'a',
        'latest',
        {'sort': 'new', 'page': 1},
        {'category': 'all'},
      ),
    );
    final b = pluginListPositionScope(
      'a',
      'latest',
      {'page': 1, 'sort': 'popular'},
      {'category': 'all'},
    );
    final c = pluginListPositionScope(
      'b',
      'latest',
      {'page': 1, 'sort': 'new'},
      {'category': 'all'},
    );
    final store = PluginListPositionStore();
    await store.save(
      a,
      const PluginListPosition(page: 38, entryKey: 'a:book', offset: -42),
    );
    expect((await store.read(a))!.page, 38);
    expect((await store.read(a))!.offset, -42);
    expect(await store.read(b), isNull);
    expect(await store.read(c), isNull);
  });
  test('并行保存不丢其他标签的记录，损坏记录安全忽略', () async {
    final store = PluginListPositionStore();
    await Future.wait([
      store.save('a', const PluginListPosition(page: 20)),
      store.save('b', const PluginListPosition(page: 35)),
    ]);
    expect((await store.read('a'))!.page, 20);
    expect((await store.read('b'))!.page, 35);
    expect(PluginListPosition.parse({'page': 0, 'offset': 1}), isNull);
    expect(PluginListPosition.parse({'page': 1, 'offset': double.nan}), isNull);
  });
}
