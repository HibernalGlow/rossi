import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_list/view/discover_library_entries.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';

void main() {
  test('发现展墙复用标签匹配，徽标开关不会改变偏好，中文不冒充汉化', () {
    const settings = GlobalSettingState(
      chineseConvertMode: ChineseConvertMode.off,
      favoriteTagSetting: FavoriteTagSettingState(
        highlightEnabled: false,
        tags: [FavoriteTag(name: 'adventure')],
      ),
      favoriteArtistSetting: FavoriteArtistSettingState(
        highlightEnabled: false,
        artists: ['artistName'],
      ),
    );
    const info = ComicSimplifyEntryInfo(
      title: '作品 [汉化]',
      id: 'id',
      fileServer: '',
      path: '',
      pictureType: PictureType.cover,
      from: 'plugin',
      tags: ['adventure'],
      artistTags: ['artistName'],
    );
    final entry = discoverLibraryEntry(info, settings);
    expect(entry.tags, ['adventure']);
    expect(entry.subtitle, 'artistName');
    expect(entry.metaText, 'plugin');
    expect(entry.weightSignals, {
      'favoriteTag': 1.0,
      'favoriteArtist': 1.0,
      'translated': 1.0,
    });
    final chinese = discoverLibraryEntry(
      info.copyWith(title: '中文作品', tags: []),
      settings,
    );
    expect(chinese.weightSignals['translated'], 0);
    final raw = discoverLibraryEntry(
      info.copyWith(title: '未知', tags: ['raw']),
      settings,
    );
    expect(raw.weightSignals['translated'], 0);
  });
}
