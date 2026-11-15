import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_info/bloc/get_comic_info_bloc.dart';
import 'package:zephyr/type/enum.dart';

import 'test_helper.dart';

Map<String, dynamic> _detail({
  required String title,
  required String coverPath,
}) => <String, dynamic>{
  'comicInfo': <String, dynamic>{
    'id': 'c1',
    'title': title,
    'titleMeta': <dynamic>[],
    'creator': <String, dynamic>{
      'id': '',
      'name': '',
      'avatar': <String, dynamic>{'id': '', 'url': '', 'name': ''},
    },
    'description': '',
    'cover': <String, dynamic>{
      'id': 'cover',
      'url': '',
      'name': '',
      'path': coverPath,
      'extern': <String, dynamic>{'path': coverPath},
    },
    'metadata': <dynamic>[],
    'extern': <String, dynamic>{},
  },
  'eps': <Map<String, dynamic>>[],
  'recommend': <Map<String, dynamic>>[],
  'extern': <String, dynamic>{},
};

void main() {
  setUpAll(() async {
    await TestObjectBoxHelper.setUpTestObjectBox();
  });
  tearDownAll(() async {
    await TestObjectBoxHelper.tearDownTestObjectBox();
  });
  tearDown(TestObjectBoxHelper.cleanComicFolderBoxes);

  test('下载详情重新加载会读到编辑后的 detailJson', () async {
    final record = createTestDownload('test:c1')
      ..comicId = 'c1'
      ..detailJson = jsonEncode(_detail(title: 'Old', coverPath: 'old.jpg'));
    objectbox.unifiedDownloadBox.put(record);

    final bloc = GetComicInfoBloc();
    addTearDown(bloc.close);

    bloc.add(
      const GetComicInfoEvent(
        comicId: 'c1',
        from: 'test',
        type: ComicEntryType.download,
      ),
    );
    var state = await bloc.stream.firstWhere(
      (s) => s.status == GetComicInfoStatus.success,
    );
    expect(state.allInfo!.comicInfo.title, 'Old');
    expect(state.allInfo!.comicInfo.cover.path, 'old.jpg');

    record.detailJson = jsonEncode(_detail(title: 'New', coverPath: 'new.jpg'));
    objectbox.unifiedDownloadBox.put(record);

    bloc.add(
      const GetComicInfoEvent(
        comicId: 'c1',
        from: 'test',
        type: ComicEntryType.download,
      ),
    );
    state = await bloc.stream.firstWhere(
      (s) => s.status == GetComicInfoStatus.success,
    );
    expect(state.allInfo!.comicInfo.title, 'New');
    expect(state.allInfo!.comicInfo.cover.path, 'new.jpg');
  });
}
