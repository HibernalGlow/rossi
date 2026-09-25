import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/model/file_manager_tab_session.dart';
import 'package:zephyr/workspace/service/file_manager_tab_session_store.dart';

/// 文件浏览「自动恢复上次打开的页签」的落盘判据。
///
/// 要防的是两个方向的故障：
/// - 「看着记住了，其实只活在会话里」—— 页签的正本住在 Rust 会话里，而会话只活到
///   卡片卸载为止，换布局 / 收起再展开 / 重启都会把它整份抹掉；
/// - 「每帧都在写盘」—— 每一份快照都会走 `remember`，去重一旦失效，翻一页目录、
///   点一次排序都会落一次盘。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tabA = '/data/comics/a';
  const tabB = '/data/comics/b';
  const twoTabs = FileManagerTabSession(paths: [tabA, tabB], activeIndex: 1);

  /// 等掉 `remember` 里那个不await的写盘。
  Future<void> settled() => Future<void>.delayed(Duration.zero);

  group('落盘往返', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('没存过时读到 null，而不是「一个空页签集合」', () async {
      expect(await PreferencesFileManagerTabSessionStore().read(), isNull);
    });

    test('写过的页签与当前项，换一个实例（＝重启）还读得回来', () async {
      await PreferencesFileManagerTabSessionStore().write(twoTabs);
      expect(
        await PreferencesFileManagerTabSessionStore().read(),
        twoTabs,
        reason: '顺序或当前页签在往返里变了，恢复出来的是另一个现场',
      );
    });

    test('键里是坏 JSON 时退回「没存过」而不是抛', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kFileManagerTabSessionNamespace: '{"p": [',
      });
      expect(await PreferencesFileManagerTabSessionStore().read(), isNull);
    });

    test('写 null 就是清掉，下一次读到 null', () async {
      final store = PreferencesFileManagerTabSessionStore();
      await store.write(twoTabs);
      await store.write(null);
      expect(await store.read(), isNull);
    });
  });

  group('decode 夹取不认识的输入', () {
    test('超出上限的页签夹掉，前面的原样留下', () {
      final decoded = FileManagerTabSession.decode(<String, Object?>{
        'p': [for (var i = 0; i < 12; i++) '/p/$i'],
        'a': 3,
      })!;
      expect(decoded.paths.length, kFileManagerTabSessionMaxTabs);
      expect(decoded.paths.first, '/p/0');
      expect(decoded.activeIndex, 3);
    });

    test('当前页签下标越界夹回末尾，不是整数退回首个', () {
      expect(
        FileManagerTabSession.decode(<String, Object?>{
          'p': const ['/a', '/b', '/c'],
          'a': 99,
        })!.activeIndex,
        2,
      );
      expect(
        FileManagerTabSession.decode(<String, Object?>{
          'p': const ['/a'],
          'a': 'x',
        })!.activeIndex,
        0,
      );
    });

    test('空列表与不是列表的 p ⇒ 整份无效（宁可不恢复）', () {
      expect(
        FileManagerTabSession.decode(<String, Object?>{'p': <Object?>[]}),
        isNull,
      );
      expect(
        FileManagerTabSession.decode(<String, Object?>{'p': tabA}),
        isNull,
      );
    });
  });

  group('FileManagerTabMemory', () {
    test('单个页签不记，凑够两个才记', () async {
      final store = _RecordingStore();
      final memory = FileManagerTabMemory(store: store);
      memory.remember(enabled: true, paths: const [tabA], activeIndex: 0);
      await settled();
      expect(store.writes, isEmpty, reason: '只剩一个页签时不该留下恢复记录');

      memory.remember(enabled: true, paths: const [tabA, tabB], activeIndex: 1);
      await settled();
      expect(store.writes, <FileManagerTabSession?>[twoTabs]);
    });

    test('同一批页签反复来快照只落一次盘，当前项变了才再落', () async {
      final store = _RecordingStore();
      final memory = FileManagerTabMemory(store: store);
      for (var i = 0; i < 5; i++) {
        memory.remember(
          enabled: true,
          paths: const [tabA, tabB],
          activeIndex: 1,
        );
      }
      await settled();
      expect(store.writes.length, 1, reason: '导航与排序也会走这里，去重失效就是每帧写盘');

      memory.remember(enabled: true, paths: const [tabA, tabB], activeIndex: 0);
      await settled();
      expect(store.writes.length, 2);
    });

    test('恢复回来的那一份不会被立刻再写一遍', () async {
      final store = _RecordingStore()..stored = twoTabs;
      final memory = FileManagerTabMemory(store: store);
      expect(await memory.restore(enabled: true), twoTabs);
      memory.remember(enabled: true, paths: const [tabA, tabB], activeIndex: 1);
      await settled();
      expect(store.writes, isEmpty);
    });

    test('中途关掉开关：把已存的那份撤掉', () async {
      final store = _RecordingStore();
      final memory = FileManagerTabMemory(store: store);
      memory.remember(enabled: true, paths: const [tabA, tabB], activeIndex: 1);
      await settled();
      memory.remember(
        enabled: false,
        paths: const [tabA, tabB],
        activeIndex: 1,
      );
      await settled();
      expect(store.writes, <FileManagerTabSession?>[twoTabs, null]);
      expect(store.stored, isNull, reason: '关掉后还留着一个用户不要的现场');
    });

    test('开关没开时，恢复这条路连盘都不读', () async {
      final store = _RecordingStore()..stored = twoTabs;
      expect(
        await FileManagerTabMemory(store: store).restore(enabled: false),
        isNull,
      );
      expect(store.reads, 0);
    });

    test('一次写盘失败后，下一次页签变化会重试', () async {
      final store = _RecordingStore()..failNextWrite = true;
      final memory = FileManagerTabMemory(store: store);
      memory.remember(enabled: true, paths: const [tabA, tabB], activeIndex: 1);
      await settled();
      expect(store.writes, isEmpty);

      memory.remember(enabled: true, paths: const [tabA, tabB], activeIndex: 1);
      await settled();
      expect(store.writes, <FileManagerTabSession?>[
        twoTabs,
      ], reason: '失败后签名没退回「没写过」，这批页签就永远进不了盘');
    });
  });
}

/// 记录读写次数与内容的假 store：真 store 没有可观测的写入计数，
/// 而「同一份页签只落一次盘」正是这里要钉住的东西。
class _RecordingStore implements FileManagerTabSessionStore {
  final List<FileManagerTabSession?> writes = <FileManagerTabSession?>[];
  FileManagerTabSession? stored;
  int reads = 0;
  bool failNextWrite = false;

  @override
  Future<FileManagerTabSession?> read() async {
    reads++;
    return stored;
  }

  @override
  Future<void> write(FileManagerTabSession? session) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('写盘失败（判据注入）');
    }
    writes.add(session);
    stored = session;
  }
}
