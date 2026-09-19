import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/network/sync/sync_service.dart';

void main() {
  group('WebDAV / S3 Settings Sync Blocks', () {
    test('extracts newly added download, library and appearance settings into blocks', () {
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
        readSetting: ReadSettingState(
          readWhileDownloading: false,
        ),
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

      // 明确断言：收藏作者名单绝对不出现在任何同步块中
      for (final blockEntry in blocks.entries) {
        expect(
          blockEntry.value.containsKey('favoriteArtistSetting'),
          isFalse,
          reason: 'favoriteArtistSetting should NOT be in block ${blockEntry.key}',
        );
        expect(
          blockEntry.value.containsKey('artists'),
          isFalse,
          reason: 'artists should NOT be in block ${blockEntry.key}',
        );
      }
    });

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
        'reader': {
          'readWhileDownloading': false,
        },
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
}
