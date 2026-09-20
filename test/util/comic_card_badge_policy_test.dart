import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/util/comic/comic_card_badge_policy.dart';

const _plugin = 'plugin-a';
const _comicId = 'comic/1';

void main() {
  group('下载角标：用户开关', () {
    test('默认开着，插件漫画显示', () {
      expect(
        const ComicCardBadgePolicy().showDownloadBadge(
          pluginId: _plugin,
          comicId: _comicId,
        ),
        isTrue,
      );
    });

    test('用户在设置里关掉总开关后不再显示', () {
      expect(
        const ComicCardBadgePolicy(
          downloadBadgeEnabled: false,
        ).showDownloadBadge(pluginId: _plugin, comicId: _comicId),
        isFalse,
      );
    });

    test('两道开关是「与」：用户开着、页面关掉也不显示', () {
      expect(
        const ComicCardBadgePolicy().showDownloadBadge(
          pluginId: _plugin,
          comicId: _comicId,
          cardEnabled: false,
        ),
        isFalse,
      );
    });

    test('两道开关是「与」：页面开着、用户关掉也不显示', () {
      expect(
        const ComicCardBadgePolicy(
          downloadBadgeEnabled: false,
        ).showDownloadBadge(
          pluginId: _plugin,
          comicId: _comicId,
          cardEnabled: true,
        ),
        isFalse,
      );
    });
  });

  group('下载角标：场景约束', () {
    test('多选模式下不显示（右上角让给勾选圈）', () {
      expect(
        const ComicCardBadgePolicy().showDownloadBadge(
          pluginId: _plugin,
          comicId: _comicId,
          selectionMode: true,
        ),
        isFalse,
      );
    });

    test('本地漫画不显示；同一本书换成插件来源就该显示', () {
      const policy = ComicCardBadgePolicy();
      // 来源标记
      expect(
        policy.showDownloadBadge(pluginId: 'local', comicId: '/a/b'),
        isFalse,
      );
      // 本地路径 / 压缩包
      expect(
        policy.showDownloadBadge(pluginId: _plugin, comicId: '/Users/me/x.cbz'),
        isFalse,
      );
      expect(
        policy.showDownloadBadge(pluginId: _plugin, comicId: 'D:/comics/x.zip'),
        isFalse,
      );
      // 反向断言：不是「永远 false」——否则上面三条全是在空转。
      expect(
        policy.showDownloadBadge(pluginId: _plugin, comicId: _comicId),
        isTrue,
      );
    });

    test('插件 id 为空时不显示（拿不到下载目标）', () {
      expect(
        const ComicCardBadgePolicy().showDownloadBadge(
          pluginId: '   ',
          comicId: _comicId,
        ),
        isFalse,
      );
    });
  });

  group('语言角标', () {
    test('默认开着', () {
      expect(const ComicCardBadgePolicy().showTranslationBadge(), isTrue);
    });

    test('用户关掉后不再显示（调用方同时跳过匹配）', () {
      expect(
        const ComicCardBadgePolicy(
          translationBadgeEnabled: false,
        ).showTranslationBadge(),
        isFalse,
      );
    });

    test('页面级开关也能关', () {
      expect(
        const ComicCardBadgePolicy().showTranslationBadge(cardEnabled: false),
        isFalse,
      );
    });

    test('与下载角标彼此独立：关掉下载角标不影响语言角标', () {
      const policy = ComicCardBadgePolicy(downloadBadgeEnabled: false);
      expect(policy.showTranslationBadge(), isTrue);
    });
  });

  group('阅读按钮（封面正中）', () {
    test('默认开着', () {
      expect(
        const ComicCardBadgePolicy().showReadButton(
          pluginId: _plugin,
          comicId: _comicId,
        ),
        isTrue,
      );
    });

    test('用户关掉总开关后不再显示', () {
      expect(
        const ComicCardBadgePolicy(
          readButtonEnabled: false,
        ).showReadButton(pluginId: _plugin, comicId: _comicId),
        isFalse,
      );
    });

    test('两道开关是「与」：页面级开关关掉也不显示', () {
      expect(
        const ComicCardBadgePolicy().showReadButton(
          pluginId: _plugin,
          comicId: _comicId,
          cardEnabled: false,
        ),
        isFalse,
      );
    });

    test('多选模式下不画（中间那颗会误触起读）', () {
      expect(
        const ComicCardBadgePolicy().showReadButton(
          pluginId: _plugin,
          comicId: _comicId,
          selectionMode: true,
        ),
        isFalse,
      );
    });

    test('与下载角标相反：本地漫画一定要画，它才是这条路径最划算的一本', () {
      const policy = ComicCardBadgePolicy();
      expect(policy.showDownloadBadge(pluginId: 'local', comicId: '/a/b'), isFalse);
      expect(policy.showReadButton(pluginId: 'local', comicId: '/a/b'), isTrue);
      expect(
        policy.showReadButton(pluginId: _plugin, comicId: '/Users/me/x.cbz'),
        isTrue,
      );
    });

    test('缺 id 时不画（起读两头都对不上号）', () {
      const policy = ComicCardBadgePolicy();
      expect(policy.showReadButton(pluginId: '  ', comicId: _comicId), isFalse);
      expect(policy.showReadButton(pluginId: _plugin, comicId: ' '), isFalse);
    });

    test('关掉阅读按钮不影响另外两个角标', () {
      const policy = ComicCardBadgePolicy(readButtonEnabled: false);
      expect(
        policy.showDownloadBadge(pluginId: _plugin, comicId: _comicId),
        isTrue,
      );
      expect(policy.showTranslationBadge(), isTrue);
    });
  });

  group('设置的默认值与向后兼容', () {
    test('新装默认全开（不改变既有观感）', () {
      const state = ComicCardSettingState();
      expect(state.downloadBadgeEnabled, isTrue);
      expect(state.translationBadgeEnabled, isTrue);
      expect(state.readButtonEnabled, isTrue);
    });

    test('老配置文件（json 里没有这些键）回落到全开', () {
      final state = ComicCardSettingState.fromJson(const <String, dynamic>{});
      expect(state.downloadBadgeEnabled, isTrue);
      expect(state.translationBadgeEnabled, isTrue);
      expect(state.readButtonEnabled, isTrue);
    });

    test('关掉的偏好存得下、读得回', () {
      const state = ComicCardSettingState(downloadBadgeEnabled: false);
      final restored = ComicCardSettingState.fromJson(
        Map<String, dynamic>.from(state.toJson()),
      );
      expect(restored.downloadBadgeEnabled, isFalse);
      expect(restored.translationBadgeEnabled, isTrue);
    });

    test('挂在 GlobalSettingState 上：默认值、copyWith 都通且不牵连别的字段', () {
      const global = GlobalSettingState();
      expect(global.comicCardSetting.downloadBadgeEnabled, isTrue);

      final off = global.copyWith(
        comicCardSetting: global.comicCardSetting.copyWith(
          downloadBadgeEnabled: false,
        ),
      );
      expect(off.comicCardSetting.downloadBadgeEnabled, isFalse);
      // 「真发生」的反面：同一组里的另一个键没被顺手改掉。
      expect(off.comicCardSetting.translationBadgeEnabled, isTrue);
      // 不牵连其他设置。
      expect(off.dynamicColor, global.dynamicColor);
      expect(
        off.favoriteArtistSetting.highlightEnabled,
        global.favoriteArtistSetting.highlightEnabled,
      );
    });
  });
}
