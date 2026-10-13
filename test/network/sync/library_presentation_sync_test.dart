import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/network/sync/sync_service.dart';
import 'package:zephyr/workspace/model/library_presentation_preferences.dart';
import 'package:zephyr/workspace/service/library_presentation_store.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';

const custom = LibraryPresentation(
  editorial: false,
  hero: false,
  sections: true,
  asymmetric: false,
  weight: LibraryWeight.imageShape,
  emphasis: .9,
  recursiveStats: true,
  cardWidth: 240,
  cardHeight: 320,
  gap: 18,
  imageScale: .8,
  signalWeights: {'reading': 2, 'favorite': 6},
  coverTapAction: LibraryCoverTapAction.openDetails,
);
const standard = LibraryPresentation();

Map<String, dynamic> payload(
  Map<String, LibraryPresentationPreference> preferences,
) => {
  'blocks': {
    if (preferences.isNotEmpty)
      'libraryPresentation': {
        'updatedAt': 9999,
        'data': LibraryPresentationPreferences.encode(preferences),
      },
  },
};

Map<String, LibraryPresentationPreference> preferencesFromPayload(
  Map<String, dynamic> value,
) => LibraryPresentationPreferences.decode(
  ((value['blocks'] as Map)['libraryPresentation'] as Map?)?['data'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('所有已存在及未来位置的全部展墙字段往返，各自保持独立配置', () async {
    final store = LibraryPresentationStore(now: () => 100);
    const scopes = [
      'home:favorite',
      'home:history',
      'home:download',
      'bookmarks',
      'reading-history',
      'file-manager',
      'reader-pages',
      'discover:plugin:category/list',
      'future-panel',
    ];
    for (var i = 0; i < scopes.length; i++) {
      await store.save(scopes[i], custom.copyWith(cardWidth: 200.0 + i));
    }
    final block = (await localLibraryPresentationBlockForTest())!;
    final encoded = jsonDecode(jsonEncode(block['data']));
    final restored = LibraryPresentationPreferences.decode(encoded);
    expect(restored.keys, unorderedEquals(scopes));
    for (var i = 0; i < scopes.length; i++) {
      expect(
        restored[scopes[i]]!.presentation.toJson(),
        custom.copyWith(cardWidth: 200.0 + i).toJson(),
      );
      expect(restored[scopes[i]]!.updatedAt, 100);
    }
    expect(block['updatedAt'], 100);
  });

  test('新设备不上传默认展墙，也不把损坏偏好当成默认值上传', () async {
    SharedPreferences.setMockInitialValues({
      '${LibraryPresentationStore.prefix}bad-json': '{',
      '${LibraryPresentationStore.prefix}bad-type': 20,
      '${LibraryPresentationStore.prefix}unknown': '{"garbage":true}',
      'unrelated': 'keep',
    });
    expect(await localLibraryPresentationBlockForTest(), isNull);
  });

  test('旧键原样迁移，记录一次时间；重启和重复同步不刷新修改时间', () async {
    SharedPreferences.setMockInitialValues({
      '${LibraryPresentationStore.prefix}bookmarks': jsonEncode(
        custom.toJson(),
      ),
    });
    final first = LibraryPresentationStore(now: () => 100);
    expect((await first.readAll())['bookmarks']!.updatedAt, 100);
    final restarted = LibraryPresentationStore(now: () => 900);
    expect((await restarted.readAll())['bookmarks']!.updatedAt, 100);
    await restarted.save('bookmarks', custom);
    expect((await restarted.readAll())['bookmarks']!.updatedAt, 100);
    await restarted.save('bookmarks', standard);
    expect((await restarted.readAll())['bookmarks']!.updatedAt, 900);
  });

  test('生产快照按位置合并，不按整个块时间覆盖；同位置取更新版本', () async {
    const state = GlobalSettingState(
      syncSetting: SyncSettingState(syncSettings: true),
    );
    final merged = await mergeSettingsPayloadsForTest(
      state,
      payload({
        'bookmarks': const LibraryPresentationPreference(custom, 300),
        'reading-history': const LibraryPresentationPreference(standard, 100),
      }),
      payload({
        'reading-history': const LibraryPresentationPreference(custom, 200),
        'reader-pages': const LibraryPresentationPreference(custom, 150),
      }),
    );
    final scopes = preferencesFromPayload(merged);
    expect(
      scopes.keys,
      unorderedEquals(['bookmarks', 'reading-history', 'reader-pages']),
    );
    expect(scopes['bookmarks']!.updatedAt, 300);
    expect(scopes['reading-history']!.updatedAt, 200);
    expect(scopes['reading-history']!.presentation.toJson(), custom.toJson());
    // 外层的 9999 不参与位置冲突；合并快照的时间来自真实设置修改。
    expect((merged['blocks'] as Map)['libraryPresentation']['updatedAt'], 300);
    expect(merged['syncTime'], 300);
  });

  test('旧客户端没有展墙块时保留本机；新设备采纳云端所有位置', () async {
    const state = GlobalSettingState(
      syncSetting: SyncSettingState(syncSettings: true),
    );
    final saved = payload({
      'reader-pages': const LibraryPresentationPreference(custom, 100),
    });
    final local = await mergeSettingsPayloadsForTest(state, saved, payload({}));
    final remote = await mergeSettingsPayloadsForTest(
      state,
      payload({}),
      saved,
    );
    expect(
      preferencesFromPayload(local)['reader-pages']!.presentation.toJson(),
      custom.toJson(),
    );
    expect(
      preferencesFromPayload(remote)['reader-pages']!.presentation.toJson(),
      custom.toJson(),
    );
  });

  test('关闭同步设置时保留云端载荷，不混入本机展墙配置', () async {
    final remote = payload({
      'bookmarks': const LibraryPresentationPreference(custom, 100),
    });
    final merged = await mergeSettingsPayloadsForTest(
      const GlobalSettingState(
        syncSetting: SyncSettingState(syncPlugins: true),
      ),
      payload({
        'reader-pages': const LibraryPresentationPreference(custom, 200),
      }),
      remote,
    );
    expect(
      (merged['blocks'] as Map)['libraryPresentation'],
      (remote['blocks'] as Map)['libraryPresentation'],
    );
    expect(await LibraryPresentationStore.instance.readAll(), isEmpty);
  });

  test('同一毫秒发生冲突的合并可收敛，信号的插入顺序不影响结果', () {
    final a = {'bookmarks': const LibraryPresentationPreference(custom, 100)};
    final b = {'bookmarks': const LibraryPresentationPreference(standard, 100)};
    expect(
      LibraryPresentationPreferences.encode(
        LibraryPresentationPreferences.merge(a, b),
      ),
      LibraryPresentationPreferences.encode(
        LibraryPresentationPreferences.merge(b, a),
      ),
    );
    expect(
      LibraryPresentationPreferences.content(custom),
      LibraryPresentationPreferences.content(
        custom.copyWith(signalWeights: {'favorite': 6, 'reading': 2}),
      ),
    );
    expect(
      jsonEncode(LibraryPresentationPreferences.encode(a)),
      jsonEncode(
        LibraryPresentationPreferences.encode({
          'bookmarks': LibraryPresentationPreference(
            custom.copyWith(signalWeights: {'favorite': 6, 'reading': 2}),
            100,
          ),
        }),
      ),
    );
  });

  test('坏记录逐项跳过，合法数据限幅；未知位置照常保留', () {
    final value = LibraryPresentationPreferences.decode({
      'scopes': {
        'broken': {
          'updatedAt': 100,
          'presentation': {'hero': 'wrong'},
        },
        'wrong-time': {'updatedAt': -1, 'presentation': custom.toJson()},
        'missing-time': {'presentation': custom.toJson()},
        'future': {
          'updatedAt': 100,
          'presentation': {
            ...custom.toJson(),
            'cardWidth': 9999,
            'gap': -10,
            'signalWeights': {'good': 99, 'bad': 'oops'},
          },
        },
      },
    });
    expect(value.keys, ['future']);
    expect(value['future']!.presentation.cardWidth, 420);
    expect(value['future']!.presentation.gap, 4);
    expect(value['future']!.presentation.signalWeights, {'good': 10});
  });

  test('远端应用落盘且保留原时间；重复应用不通知、不回写新时间', () async {
    final store = LibraryPresentationStore(now: () => 900);
    final changes = <LibraryPresentationChange>[];
    final subscription = store.changes.listen(changes.add);
    addTearDown(subscription.cancel);
    final remote = {
      'bookmarks': const LibraryPresentationPreference(custom, 100),
    };
    await store.apply(remote);
    await store.apply(remote);
    expect(changes.length, 1);
    expect(
      (await LibraryPresentationStore(
        now: () => 1000,
      ).readAll())['bookmarks']!.updatedAt,
      100,
    );
    expect((await store.read('bookmarks'))!.toJson(), custom.toJson());
  });

  test('请求期间的新本机调整不会被旧网络快照盖回去', () async {
    final store = LibraryPresentationStore(now: () => 900);
    await Future.wait([
      store.save('reading-history', custom),
      store.apply({
        'reading-history': const LibraryPresentationPreference(standard, 100),
      }),
      store.save('bookmarks', custom),
    ]);
    expect((await store.read('reading-history'))!.toJson(), custom.toJson());
    expect((await store.read('bookmarks'))!.toJson(), custom.toJson());
  });

  test('手动下载以云端为准；云端缺失的位置、无关键和损坏块不清空本机', () async {
    SharedPreferences.setMockInitialValues({'unrelated': 'keep'});
    final store = LibraryPresentationStore.instance;
    await store.save('bookmarks', custom);
    await store.save('reader-pages', custom);
    await applyLibraryPresentationBlockForTest(
      LibraryPresentationPreferences.encode({
        'bookmarks': const LibraryPresentationPreference(standard, 1),
      }),
      force: true,
    );
    await applyLibraryPresentationBlockForTest({
      'scopes': {'bookmarks': 'broken'},
    }, force: true);
    expect((await store.read('bookmarks'))!.toJson(), standard.toJson());
    expect((await store.read('reader-pages'))!.toJson(), custom.toJson());
    expect((await store.readAll())['bookmarks']!.updatedAt, 1);
    expect(
      (await SharedPreferences.getInstance()).getString('unrelated'),
      'keep',
    );
  });
}
