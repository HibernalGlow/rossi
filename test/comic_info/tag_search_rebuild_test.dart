import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/page/comic_info/widgets/all_chip.dart';
import 'package:zephyr/page/discover/service/discover_tab_scope.dart';
import 'package:zephyr/page/search/model/plugin_search_history_store.dart';

class _MemorySettings extends GlobalSettingCubit {
  @override
  void updateState(GlobalSettingState Function(GlobalSettingState) updates) =>
      emit(updates(state));
}

class _Tabs implements DiscoverTabActions {
  WidgetBuilder? content;
  String? source;
  String? label;

  @override
  void openPage({
    required String label,
    required String source,
    required WidgetBuilder content,
    Glyph? icon,
  }) {
    this.source = source;
    this.label = label;
    this.content = content;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('真实标签点击保留搜索参数；历史写入不重建标签，收藏变化仍生效', (tester) async {
    final settings = _MemorySettings();
    addTearDown(settings.close);
    final tabs = _Tabs();
    await tester.pumpWidget(
      BlocProvider<GlobalSettingCubit>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: DiscoverTabScope(
              actions: tabs,
              child: Builder(
                builder: (context) {
                  return const AllChipWidget(
                    comicId: 'book',
                    from: 'plugin-a',
                    inline: true,
                    metadata: ComicInfoMetadata(
                      type: 'tag:artist',
                      name: '作者',
                      value: [
                        ComicInfoActionItem(
                          name: 'ArtistOne',
                          onTap: {
                            'type': 'openSearch',
                            'payload': {
                              'keyword': 'artist:ArtistOne',
                              'extern': {'category': 'artist'},
                            },
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    // 没有初始化 ObjectBox：标签显示不得为每段文字重新解码全局设置。
    expect(tester.takeException(), isNull);
    final chip = tester.widget<AllChipItem>(find.byType(AllChipItem));
    expect(chip.isFavorite, isFalse);
    await tester.tap(find.text('ArtistOne'));
    await tester.pump();
    expect(tabs.source, 'plugin-a');
    expect(tabs.label, 'artist:ArtistOne');
    expect(tabs.content, isNotNull);
    await PluginSearchHistoryStore(
      settings,
      'plugin-a',
    ).record('artist:ArtistOne');
    await tester.pump();
    expect(tester.widget<AllChipItem>(find.byType(AllChipItem)), same(chip));
    settings.updateState(
      (state) => state.copyWith(
        favoriteArtistSetting: const FavoriteArtistSettingState(
          artists: ['ArtistOne'],
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<AllChipItem>(find.byType(AllChipItem)).isFavorite,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
