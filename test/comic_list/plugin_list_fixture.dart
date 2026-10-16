import 'package:zephyr/page/comic_list/cubit/plugin_paged_comic_list_cubit.dart';

Map<String, dynamic> response(
  int page, {
  int? total,
  bool end = false,
  int count = 3,
}) => {
  'source': 'plugin',
  'data': {
    'items': [
      for (var i = 0; i < count; i++)
        {
          'source': 'plugin',
          'id': '$page-$i',
          'title': 'Book $page-$i',
          'cover': {'id': '$page-$i', 'url': '', 'path': '', 'extern': {}},
          'metadata': [],
        },
    ],
    'hasReachedMax': end,
    'totalPages': ?total,
  },
};

PluginPagedComicListCubit cubit(
  Future<Map<String, dynamic>> Function(int) fetch,
) => PluginPagedComicListCubit(
  pluginId: 'plugin',
  fnPath: 'getList',
  coreBuilder: (page) => {'page': page},
  externBuilder: (_) => {},
  pageFetcher: fetch,
);
