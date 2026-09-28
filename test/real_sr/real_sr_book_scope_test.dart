import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_book_scope.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';

/// 书级超分开关（覆盖 ?? 全局）的口径。
///
/// 要防的两类静默错：
/// 1. 键不唯一（同一本书算出两个键）→ 关掉的那本下次又开起来，或者「设置没生效」；
/// 2. 覆盖与全局同值却留着 —— 之后改全局再也影响不到这本书，看起来就是「设置坏了」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('书身份', () {
    test('本地书用规范化路径（与阅读历史键同源）', () {
      expect(RealSrBookScope.keyFor(localPath: '/a/b/'), '/a/b');
      expect(RealSrBookScope.keyFor(localPath: '  /a/b  '), '/a/b');
      expect(RealSrBookScope.keyFor(localPath: '/a/./b'), '/a/b');
    });

    test('在线书用「插件id:漫画id」，只有漫画 id 时不留空插件前缀', () {
      expect(RealSrBookScope.keyFor(from: 'bika', comicId: '123'), 'bika:123');
      expect(RealSrBookScope.keyFor(comicId: '123'), '123');
      expect(RealSrBookScope.keyFor(from: 'bika'), isNull);
      expect(RealSrBookScope.keyFor(), isNull);
    });

    test('本地路径优先于插件身份', () {
      expect(
        RealSrBookScope.keyFor(localPath: '/x', from: 'f', comicId: 'c'),
        '/x',
      );
    });
  });

  group('覆盖 ?? 全局', () {
    test('没有覆盖时跟随全局，全局一改就跟着变', () async {
      await RealSrSettings.saveAutoUpscale(true);
      expect(await RealSrBookScope.enabledFor('bika:1'), isTrue);
      await RealSrSettings.saveAutoUpscale(false);
      expect(await RealSrBookScope.enabledFor('bika:1'), isFalse);
    });

    test('关掉一本书不影响别的书（两组方向都验）', () async {
      await RealSrSettings.saveAutoUpscale(true);
      await RealSrBookScope.save('bika:1', false);
      expect(await RealSrBookScope.enabledFor('bika:1'), isFalse);
      expect(await RealSrBookScope.enabledFor('bika:2'), isTrue, reason: '别的书照旧按全局');

      // 反过来也一样：全局关着，某一本单独打开
      await RealSrSettings.saveAutoUpscale(false);
      await RealSrBookScope.save('bika:1', true);
      expect(await RealSrBookScope.enabledFor('bika:1'), isTrue);
      expect(await RealSrBookScope.enabledFor('bika:2'), isFalse);
    });

    test('拨回与全局同值时清掉覆盖（之后全局能再次影响它）', () async {
      await RealSrSettings.saveAutoUpscale(true);
      await RealSrBookScope.save('bika:1', false);
      expect(await RealSrBookScope.overrideFor('bika:1'), isFalse);

      await RealSrBookScope.save('bika:1', true); // == 全局
      expect(await RealSrBookScope.overrideFor('bika:1'), isNull);

      await RealSrSettings.saveAutoUpscale(false);
      expect(await RealSrBookScope.enabledFor('bika:1'), isFalse, reason: '回到跟随全局');
    });

    test('拿不到书身份（null）不写覆盖，按全局走', () async {
      await RealSrSettings.saveAutoUpscale(true);
      await RealSrBookScope.save(null, false);
      expect(await RealSrBookScope.enabledFor(null), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(RealSrBookScope.prefsKey), isNull);
    });
  });

  group('持久化与上限', () {
    test('覆盖落盘（重开 app 仍是这个选择）', () async {
      await RealSrBookScope.save('bika:1', true); // 全局默认 false
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(RealSrBookScope.prefsKey);
      expect(raw, isNotNull);
      expect(raw, contains('bika:1'));
      expect(await RealSrBookScope.overrideFor('bika:1'), isTrue);
    });

    test('超过上限按最后写入时间淘汰最旧的，最新那条一定在', () async {
      final newest = 'book:${RealSrBookScope.maxEntries + 2}';
      for (var i = 0; i <= RealSrBookScope.maxEntries + 2; i++) {
        await RealSrBookScope.save('book:$i', true);
      }
      expect(await RealSrBookScope.overrideFor('book:0'), isNull, reason: '最旧的被淘汰');
      expect(await RealSrBookScope.overrideFor(newest), isTrue);
    });

    test('覆盖变化与全局变化都走同一个通知源', () async {
      var fired = 0;
      void listener() => fired++;
      RealSrBookScope.changes.addListener(listener);
      addTearDown(() => RealSrBookScope.changes.removeListener(listener));

      await RealSrBookScope.save('bika:1', true);
      expect(fired, greaterThan(0), reason: '写覆盖要通知');

      final afterOverride = fired;
      await RealSrSettings.saveAutoUpscale(true);
      expect(fired, greaterThan(afterOverride), reason: '全局那条也要通知（没有覆盖的书要跟随）');
    });
  });
}
