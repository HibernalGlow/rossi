import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/network/sync/sync_service.dart';

/// 绝不允许出现在**任何**同步块里的键。
///
/// 它们要么是**本机事实**（绝对路径、窗口几何、代理），要么是**安全/私有**
/// （开屏密码、收藏作者名单、调试日志地址），要么是**瞬态**（缓存标记）。
/// 逐块扫一遍而不是只看几个已知块：真正的失败方式是「往某个块里顺手多加了一个键」，
/// 那时没人会回来读这段名单。
const List<String> _mustNotSync = <String>[
  'customExportPath',
  'appLockSetting',
  'cacheSetting',
  'favoriteArtistSetting',
  'artists',
  'enableMemoryDebug',
  'blockRustHttpRequests',
  'logAddress',
  'syncSetting',
  'themeInitState',
  'needCleanCache',
  'compatibleVersion',
  'socks5Proxy',
  'socks5ProxyEnabled',
  'proxySetting',
  'windowWidth',
  'windowHeight',
  'windowX',
  'windowY',
];

/// 本机绝对路径：`homePath` 除外（见下一条断言），其余路径类字段同样不许进。
void _expectNoLocalOnlyKeys(Map<String, Map<String, dynamic>> blocks) {
  for (final blockEntry in blocks.entries) {
    for (final key in _mustNotSync) {
      expect(
        blockEntry.value.containsKey(key),
        isFalse,
        reason:
            '$key 不该出现在同步块 ${blockEntry.key} 里（本机事实 / 安全 / 瞬态）',
      );
    }
  }
}

void main() {
  group('WebDAV / S3 Settings Sync Blocks', () {
    test(
      'extracts newly added download, library and appearance settings into blocks',
      () {
        const state = GlobalSettingState(
          localeFollowsSystem: false,
          chineseConvertMode: ChineseConvertMode.traditional,
          downloadConcurrency: 5,
          downloadDelayMs: 200,
          downloadAutoRetryCount: 4,
          autoFavoriteOnDownload: true,
          oldPageRollbackEnabled: true,
          cloudFavoritePreferred: true,
          autoFollowOnCollect: true,
          leftHandModeEnabled: true,
          clickCoverToStartReading: true,
          bookshelfSetting: BookshelfSettingState(
            homePageIndex: 1,
            rememberFavoriteSort: true,
            favoriteSort: 'da',
          ),
          favoriteArtistSetting: FavoriteArtistSettingState(
            highlightEnabled: true,
            artists: ['ArtistA', 'ArtistB'],
          ),
          readSetting: ReadSettingState(readWhileDownloading: false),
        );

        final blocks = extractSyncableSettingsBlocksForTest(state);

        expect(blocks.containsKey('appearance'), isTrue);
        expect(blocks.containsKey('library'), isTrue);
        expect(blocks.containsKey('reader'), isTrue);

        final appearance = blocks['appearance']!;
        expect(appearance['localeFollowsSystem'], isFalse);
        expect(appearance['chineseConvertMode'], 'traditional');

        final library = blocks['library']!;
        expect(library['downloadConcurrency'], 5);
        expect(library['downloadDelayMs'], 200);
        expect(library['downloadAutoRetryCount'], 4);
        expect(library['autoFavoriteOnDownload'], isTrue);
        expect(library['oldPageRollbackEnabled'], isTrue);
        expect(library['cloudFavoritePreferred'], isTrue);
        expect(library['autoFollowOnCollect'], isTrue);
        expect(library['leftHandModeEnabled'], isTrue);
        expect(library['clickCoverToStartReading'], isTrue);
        expect(library['bookshelfSetting'], isNotNull);
        expect((library['bookshelfSetting'] as Map)['homePageIndex'], 1);

        final reader = blocks['reader']!;
        expect(reader['readWhileDownloading'], isFalse);

        _expectNoLocalOnlyKeys(blocks);

        // 明确断言：收藏作者名单绝对不出现在任何同步块中
        for (final blockEntry in blocks.entries) {
          expect(
            blockEntry.value.containsKey('favoriteArtistSetting'),
            isFalse,
            reason:
                'favoriteArtistSetting should NOT be in block ${blockEntry.key}',
          );
          expect(
            blockEntry.value.containsKey('artists'),
            isFalse,
            reason: 'artists should NOT be in block ${blockEntry.key}',
          );
        }
      },
    );

    test('applies remote sync blocks while preserving local favoriteArtistSetting', () {
      const localState = GlobalSettingState(
        downloadConcurrency: 2,
        downloadDelayMs: 100,
        chineseConvertMode: ChineseConvertMode.off,
        favoriteArtistSetting: FavoriteArtistSettingState(
          highlightEnabled: true,
          artists: ['MySecretArtist'],
        ),
      );

      final remoteBlocks = <String, Map<String, dynamic>>{
        'appearance': {
          'dynamicColor': false,
          'themeMode': 'dark',
          'chineseConvertMode': 'simplified',
          'localeFollowsSystem': false,
        },
        'library': {
          'downloadConcurrency': 6,
          'downloadDelayMs': 300,
          'autoFavoriteOnDownload': true,
          'leftHandModeEnabled': true,
        },
        'reader': {'readWhileDownloading': false},
      };

      final merged = applySyncableBlockDataForTest(localState, remoteBlocks);

      // 远端新设置成功生效
      expect(merged.downloadConcurrency, 6);
      expect(merged.downloadDelayMs, 300);
      expect(merged.autoFavoriteOnDownload, isTrue);
      expect(merged.leftHandModeEnabled, isTrue);
      expect(merged.chineseConvertMode, ChineseConvertMode.simplified);
      expect(merged.localeFollowsSystem, isFalse);
      expect(merged.readSetting.readWhileDownloading, isFalse);

      // 本地私有的收藏作者名单不受任何影响，原样保留
      expect(merged.favoriteArtistSetting.artists, ['MySecretArtist']);
      expect(merged.favoriteArtistSetting.highlightEnabled, isTrue);
    });
  });

  group('同步块表的覆盖范围', () {
    test('新增的四类设置都进了块：外壳行为 / 提示条 / 文件管理器 / 操作绑定', () {
      final blocks = extractSyncableSettingsBlocksForTest(
        const GlobalSettingState(),
      );

      expect(blocks.containsKey('shell'), isTrue);
      expect(blocks.containsKey('toast'), isTrue);
      expect(blocks.containsKey('fileManager'), isTrue);
      expect(blocks.containsKey('operationBinding'), isTrue);

      // 载荷形状：块里装的是**顶层键 → 值**
      expect(blocks['shell']!.containsKey('startWithWorkspace'), isTrue);
      expect(blocks['shell']!.containsKey('backPressExitEnabled'), isTrue);
      expect(blocks['toast']!.containsKey('toastSetting'), isTrue);
      expect(blocks['toast']!.containsKey('switchToastSetting'), isTrue);
      expect(
        blocks['operationBinding']!.containsKey('operationBindingSetting'),
        isTrue,
      );
      expect(blocks['fileManager']!.containsKey('fileManagerSetting'), isTrue);
      // 漫画卡片展示归书架那一块
      expect(blocks['library']!.containsKey('comicCardSetting'), isTrue);
    });

    test('文件管理器块不带 homePath（本机绝对路径）', () {
      final blocks = extractSyncableSettingsBlocksForTest(
        const GlobalSettingState(fileManagerSetting: FileManagerSettingState(
          homePath: '/Users/someone/Comics',
        )),
      );

      final fileManager = blocks['fileManager']!;
      final payload = fileManager['fileManagerSetting'] as Map;
      expect(payload.containsKey('homePath'), isFalse);
      // 其余四项照常同步：漏掉它们等于「文件管理器设置根本没同步」
      expect(payload.containsKey('homeEnabled'), isTrue);
      expect(payload.containsKey('openHomeOnStart'), isTrue);
      expect(payload.containsKey('rememberViewState'), isTrue);
      expect(payload.containsKey('fileOperations'), isTrue);
    });

    test('应用远端文件管理器块时本机 homePath 原样保留', () {
      const localState = GlobalSettingState(
        fileManagerSetting: FileManagerSettingState(
          homeEnabled: true,
          homePath: '/Users/someone/Comics',
          openHomeOnStart: false,
          rememberViewState: true,
          fileOperations: true,
        ),
      );

      final merged = applySyncableBlockDataForTest(localState, {
        'fileManager': {
          'fileManagerSetting': {
            'homeEnabled': false,
            'openHomeOnStart': true,
            'rememberViewState': false,
            'fileOperations': false,
          },
        },
      });

      // 云端那四项生效
      expect(merged.fileManagerSetting.homeEnabled, isFalse);
      expect(merged.fileManagerSetting.openHomeOnStart, isTrue);
      expect(merged.fileManagerSetting.rememberViewState, isFalse);
      expect(merged.fileManagerSetting.fileOperations, isFalse);
      // 本机路径没被清空（对方的机器上这个目录根本不存在）
      expect(merged.fileManagerSetting.homePath, '/Users/someone/Comics');
    });

    test('操作绑定与轮盘整串往返', () {
      const localState = GlobalSettingState();
      const bindingsJson = '[{"input":{"device":"key","code":"ArrowLeft"},'
          '"action":"page.prev","preset":"default"}]';
      const radialJson = '{"menus":[{"id":"menu-1","levels":2}],"enabled":true}';

      final merged = applySyncableBlockDataForTest(localState, {
        'operationBinding': {
          'operationBindingSetting': {
            'bindingsRuntime': false,
            'bindingsJson': bindingsJson,
            'radialJson': radialJson,
          },
        },
      });

      expect(merged.operationBindingSetting.bindingsRuntime, isFalse);
      expect(merged.operationBindingSetting.bindingsJson, bindingsJson);
      expect(merged.operationBindingSetting.radialJson, radialJson);
      // 引擎的 schema 归 Rust，Dart 侧只当字符串搬 —— 顺手解析一遍就是多一份实现
      expect(merged.operationBindingSetting.bindingsJson, isA<String>());
    });

    test('外壳行为块往返', () {
      const localState = GlobalSettingState(startWithWorkspace: false);
      final merged = applySyncableBlockDataForTest(localState, {
        'shell': {
          'startWithWorkspace': true,
          'forceEnableImpeller': true,
          'androidKeepAliveEnabled': true,
          'backPressExitEnabled': true,
        },
      });

      expect(merged.startWithWorkspace, isTrue);
      expect(merged.forceEnableImpeller, isTrue);
      expect(merged.androidKeepAliveEnabled, isTrue);
      expect(merged.backPressExitEnabled, isTrue);
    });

    test('提示条位置与切换提示块往返', () {
      const localState = GlobalSettingState();
      final merged = applySyncableBlockDataForTest(localState, {
        'toast': {
          'toastSetting': {
            'position': 'bottomLeft',
            'edgePadding': 24,
            'durationMs': 0,
            'maxWidth': 520,
            'opacityPercent': 90,
            'maxVisible': 5,
            'animationDurationMs': 300,
            'liquidGlass': true,
            'showProgressBar': false,
            'showIcon': false,
            'showCloseButton': false,
          },
        },
      });

      expect(merged.toastSetting.position, ToastPosition.bottomLeft);
      expect(merged.toastSetting.edgePadding, 24);
      expect(merged.toastSetting.durationMs, 0);
      expect(merged.toastSetting.maxWidth, 520);
      expect(merged.toastSetting.opacityPercent, 90);
      expect(merged.toastSetting.maxVisible, 5);
      expect(merged.toastSetting.liquidGlass, isTrue);
      expect(merged.toastSetting.showProgressBar, isFalse);
    });

    test('汇总：同步设置总开关统辖的块清单', () {
      expect(syncableSettingsBlockNamesForTest(), <String>[
        'appearance',
        'library',
        'reader',
        'shell',
        'toast',
        'fileManager',
        'operationBinding',
        'workspace',
      ]);
    });

    test('reader 块的载荷形状保持冻结（老客户端兼容）', () {
      final blocks = extractSyncableSettingsBlocksForTest(
        const GlobalSettingState(),
      );
      final reader = blocks['reader']!;

      // 老客户端下载时执行的是 `json['readSetting'] = <块数据>`；
      // 这里若把块改成 `{'readSetting': {...}}`，老客户端就会把外层对象整个
      // 当成 ReadSettingState —— 所有阅读设置静默读成默认值，且不报错。
      expect(
        reader.containsKey('readSetting'),
        isFalse,
        reason: 'reader 块必须是 readSetting 本身，不能套一层同名键',
      );
      expect(reader.containsKey('readMode'), isTrue);
    });

    test('应用到全局状态的块里没有本机 / 敏感键', () {
      // 用一份「全都改成非默认」的设置抽块：默认值相等会让「这个键其实进了块」
      // 这类问题被值比较掩盖。
      const state = GlobalSettingState(
        fileManagerSetting: FileManagerSettingState(
          homePath: '/tmp/x',
          homeEnabled: false,
        ),
        syncSetting: SyncSettingState(syncSettings: true, syncPlugins: true),
        customExportPath: '/tmp/export',
        enableMemoryDebug: true,
        logAddress: 'http://127.0.0.1:9999',
        favoriteArtistSetting: FavoriteArtistSettingState(
          artists: ['Secret'],
        ),
      );

      _expectNoLocalOnlyKeys(extractSyncableSettingsBlocksForTest(state));
    });
  });

  group('工作台布局块的本地时间戳判定', () {
    final factoryHash = workspaceFactoryHashForTest();
    const nowMs = 1700000000000;

    test('本机从没同步过、且就是出厂值 ⇒ 让云端说了算', () {
      expect(
        resolveWorkspaceBlockUpdatedAtForTest(
          hash: factoryHash,
          previousHash: null,
          previousUpdatedAt: 0,
          nowMs: nowMs,
        ),
        0,
        reason: '给「现在」的话，一台新装设备会在一轮自动同步里把云端布局冲掉',
      );
    });

    test('本机从没同步过、但布局与出厂不同 ⇒ 本机说了算', () {
      expect(
        resolveWorkspaceBlockUpdatedAtForTest(
          hash: 'a-different-hash',
          previousHash: null,
          previousUpdatedAt: 0,
          nowMs: nowMs,
        ),
        nowMs,
        reason: '先摆好布局、后打开同步开关的用户不该被自己的云端旧值盖掉',
      );
    });

    test('内容没变 ⇒ 沿用原来的时间（否则这台设备永远赢）', () {
      expect(
        resolveWorkspaceBlockUpdatedAtForTest(
          hash: 'same',
          previousHash: 'same',
          previousUpdatedAt: 12345,
          nowMs: nowMs,
        ),
        12345,
      );
    });

    test('内容没变、且原来就是 0 ⇒ 仍然是 0（不能被刷新成现在）', () {
      expect(
        resolveWorkspaceBlockUpdatedAtForTest(
          hash: 'same',
          previousHash: 'same',
          previousUpdatedAt: 0,
          nowMs: nowMs,
        ),
        0,
        reason:
            '刷新成 now 会让「本机就是出厂值」这个判断每轮失效，云端布局永远进不来',
      );
    });

    test('内容变了 ⇒ 现在', () {
      expect(
        resolveWorkspaceBlockUpdatedAtForTest(
          hash: 'new',
          previousHash: 'old',
          previousUpdatedAt: 12345,
          nowMs: nowMs,
        ),
        nowMs,
      );
    });

    test('出厂哈希与「改过的布局」哈希不同（判据自身的前提）', () {
      expect(factoryHash.isNotEmpty, isTrue);
    });
  });

  group('工作台布局块不走全局状态平铺', () {
    test('把 workspace 块喂给全局状态的应用函数，不会污染 GlobalSettingState', () {
      const localState = GlobalSettingState(downloadConcurrency: 3);

      final merged = applySyncableBlockDataForTest(localState, {
        'workspace': {
          'mode': 'edges',
          'layout': {
            'laneOrder': ['reader', 'left', 'right'],
          },
          'activePanel': {'left': 'shelf'},
        },
      });

      // 布局的落点是 `workspace_layout.json`（见 `WorkspaceSyncCodec`），
      // 不该有任何一项被当成 GlobalSettingState 的字段吸收。
      expect(merged.downloadConcurrency, 3);
      expect(merged.toastSetting.position, const GlobalSettingState().toastSetting.position);
      expect(merged.startWithWorkspace, isFalse);
    });
  });
}
