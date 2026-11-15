import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_edit/method/comic_edit_document.dart';

Map<String, dynamic> _detail() => <String, dynamic>{
  'comicInfo': <String, dynamic>{
    'id': 'c1',
    'title': 'Original',
    'description': 'desc',
    'cover': <String, dynamic>{
      'id': 'cover1',
      'url': 'https://example.com/cover.jpg',
      'name': 'cover.jpg',
      'path': 'cover.jpg',
      'extern': <String, dynamic>{'path': 'cover.jpg'},
    },
  },
  'eps': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'ch1',
      'name': '第1话',
      'order': 1,
      'requestId': 'r1',
      'storageChapterId': 's1',
      'logicalKey': 'ch1',
      'groupTitle': '',
      'extern': <String, dynamic>{'k': 'v'},
    },
    <String, dynamic>{
      'id': 'ch2',
      'name': '第2话',
      'order': 2,
      'requestId': 'r2',
      'storageChapterId': 's2',
      'logicalKey': 'ch2',
      'groupTitle': '',
      'extern': <String, dynamic>{},
    },
  ],
  'extern': <String, dynamic>{
    'chapterCatalog': <Map<String, dynamic>>[
      <String, dynamic>{'id': 'ch1', 'logicalKey': 'ch1', 'order': 1},
    ],
  },
};

List<Map<String, dynamic>> _chapters() => <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 's1',
    'name': '第1话',
    'order': 1,
    'logicalKey': 'ch1',
    'taskChapterId': 'r1',
    'storageChapterId': 's1',
    'groupTitle': '',
    'images': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'i1',
        'name': '1.jpg',
        'path': 'p1',
        'url': 'u1',
        'extern': <String, dynamic>{},
      },
      <String, dynamic>{
        'id': 'i2',
        'name': '2.jpg',
        'path': 'p2',
        'url': 'u2',
        'extern': <String, dynamic>{},
      },
    ],
  },
  <String, dynamic>{
    'id': 's2',
    'name': '第2话',
    'order': 2,
    'logicalKey': 'ch2',
    'taskChapterId': 'r2',
    'storageChapterId': 's2',
    'groupTitle': '',
    'images': <Map<String, dynamic>>[],
  },
];

ComicEditDocument _document() =>
    ComicEditDocument.fromMaps(detail: _detail(), chapters: _chapters());

List<String> _paths(Map<String, dynamic> chapter) => (chapter['images'] as List)
    .whereType<Map>()
    .map((image) => image['path'].toString())
    .toList();

void main() {
  test('改标题只动 comicInfo.title，保留其它字段', () {
    final doc = _document().setTitle('  新标题  ');

    expect(doc.title, '新标题');
    expect(doc.comicInfo['description'], 'desc');
    expect(doc.comicInfo['cover'], isA<Map>());
    expect(doc.chapterMaps, _chapters());
  });

  test('改封面只动 comicInfo.cover', () {
    final doc = _document().setCover(<String, dynamic>{
      'id': 'local_cover',
      'url': '',
      'name': 'cover_1.jpg',
      'path': 'cover_1.jpg',
      'extern': <String, dynamic>{'path': 'cover_1.jpg', 'local': true},
    });

    expect(doc.cover['path'], 'cover_1.jpg');
    expect(doc.cover['url'], '');
    expect(doc.comicInfo['title'], 'Original');
    expect(doc.chapterMaps, _chapters());
  });

  test('改章节名同步 chapters / eps / downloadChapters 镜像', () {
    final doc = _document().renameChapter('ch1', '  改名后  ');

    expect(doc.chapterMaps[0]['name'], '改名后');
    expect(doc.eps[0]['name'], '改名后');
    final mirror = doc.detail['extern']['downloadChapters'] as List;
    expect((mirror[0] as Map)['name'], '改名后');
    // 章节原有图片与 ep extern 不能被重写。
    expect(_paths(doc.chapterMaps[0]), <String>['p1', 'p2']);
    expect(doc.eps[0]['extern'], <String, dynamic>{'k': 'v'});
    // 原实例不变。
    expect(_document().chapterMaps[0]['name'], '第1话');
  });

  test('老数据 id 与 logicalKey 不同时，两者都能定位章节', () {
    final doc = ComicEditDocument.fromMaps(
      detail: _detail(),
      chapters: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'Gallery',
          'name': '第1话',
          'order': 1,
          'logicalKey': 'chunk-1',
          'taskChapterId': 'req-1',
          'storageChapterId': 'Gallery',
          'images': <Map<String, dynamic>>[],
        },
      ],
    );

    expect(doc.renameChapter('chunk-1', 'A').chapterMaps[0]['name'], 'A');
    expect(doc.renameChapter('Gallery', 'B').chapterMaps[0]['name'], 'B');
    expect(doc.renameChapter('req-1', 'C').chapterMaps[0]['name'], 'C');
  });

  test('新增章节追加到末尾，id/logicalKey/storageId 一致且图片为空', () {
    final doc = _document().addChapter(id: 'local:1', name: '新章节');

    expect(doc.chapterMaps.length, 3);
    final chapter = doc.chapterMaps[2];
    expect(chapter['id'], 'local:1');
    expect(chapter['logicalKey'], 'local:1');
    expect(chapter['storageChapterId'], 'local:1');
    expect(chapter['order'], 3);
    expect(chapter['images'], isEmpty);

    expect(doc.eps.length, 3);
    expect(doc.eps[2]['id'], 'local:1');
    expect(doc.eps[2]['logicalKey'], 'local:1');
    expect(doc.eps[2]['order'], 3);

    final mirror = doc.detail['extern']['downloadChapters'] as List;
    expect(mirror.length, 3);
    expect((mirror[2] as Map)['id'], 'local:1');

    final second = doc.addChapter(id: 'local:2', name: '再一章');
    expect(second.chapterMaps[3]['order'], 4);
  });

  test('新增章节拒绝重复身份', () {
    expect(
      () => _document().addChapter(id: 'ch1', name: '重复'),
      throwsStateError,
    );
  });

  test('图片排序按 path 重排，未传的图片保留在末尾', () {
    final doc = _document().reorderImages('ch1', <String>['p2', 'p1']);

    expect(_paths(doc.chapterMaps[0]), <String>['p2', 'p1']);
    final mirror = doc.detail['extern']['downloadChapters'] as List;
    expect(_paths(Map<String, dynamic>.from(mirror[0] as Map)), <String>[
      'p2',
      'p1',
    ]);

    final partial = _document().reorderImages('ch1', <String>['p2']);
    expect(_paths(partial.chapterMaps[0]), <String>['p2', 'p1']);
  });

  test('跨章移动从源章删除并按目标顺序插入', () {
    final doc = _document().moveImages(
      sourceChapterId: 'ch1',
      targetChapterId: 'ch2',
      imagePaths: <String>['p1'],
      targetIndex: 0,
    );

    expect(_paths(doc.chapterMaps[0]), <String>['p2']);
    expect(_paths(doc.chapterMaps[1]), <String>['p1']);
    final mirror = doc.detail['extern']['downloadChapters'] as List;
    expect(_paths(Map<String, dynamic>.from(mirror[0] as Map)), <String>['p2']);
    expect(_paths(Map<String, dynamic>.from(mirror[1] as Map)), <String>['p1']);
  });

  test('跨章移动保持传入顺序，未知 path 被忽略', () {
    final doc = _document().moveImages(
      sourceChapterId: 'ch1',
      targetChapterId: 'ch2',
      imagePaths: <String>['p2', 'missing', 'p1'],
    );

    expect(_paths(doc.chapterMaps[0]), isEmpty);
    expect(_paths(doc.chapterMaps[1]), <String>['p2', 'p1']);
  });

  test('移动到同一章等价于按目标位置重排', () {
    final doc = _document().moveImages(
      sourceChapterId: 'ch1',
      targetChapterId: 'ch1',
      imagePaths: <String>['p2'],
      targetIndex: 0,
    );

    expect(_paths(doc.chapterMaps[0]), <String>['p2', 'p1']);
  });

  test('replaceImagePath 只改指定图片并同步镜像', () {
    final doc = _document().replaceImagePath('ch1', 'p1', 'p1_moved');

    expect(_paths(doc.chapterMaps[0]), <String>['p1_moved', 'p2']);
    final mirror = doc.detail['extern']['downloadChapters'] as List;
    expect(_paths(Map<String, dynamic>.from(mirror[0] as Map)), <String>[
      'p1_moved',
      'p2',
    ]);
  });

  test('章节身份 helper 优先 logicalKey / storageChapterId', () {
    final chapter = <String, dynamic>{
      'id': 'Gallery',
      'logicalKey': 'chunk-1',
      'storageChapterId': 'Gallery',
    };

    expect(comicEditChapterId(chapter), 'chunk-1');
    expect(comicEditChapterStorageId(chapter), 'Gallery');
  });

  test('章节重排后 order 连续，eps 与镜像同步', () {
    final doc = _document().reorderChapters(<String>['ch2', 'ch1']);

    expect(doc.chapterMaps.map((chapter) => chapter['order']).toList(), <int>[
      1,
      2,
    ]);
    expect(doc.chapterMaps[0]['logicalKey'], 'ch2');
    expect(doc.chapterMaps[1]['logicalKey'], 'ch1');
    expect(doc.eps.map((ep) => ep['order']).toList(), <int>[1, 2]);
    expect(doc.eps[0]['logicalKey'], 'ch2');
    final mirror = doc.detail['extern']['downloadChapters'] as List;
    expect((mirror[0] as Map)['logicalKey'], 'ch2');
  });

  test('章节重排保留未传章节并追加到末尾', () {
    final doc = _document().reorderChapters(<String>['ch2']);

    expect(doc.chapterMaps[0]['logicalKey'], 'ch2');
    expect(doc.chapterMaps[1]['logicalKey'], 'ch1');
  });

  test('删除图片只移除指定 path 并同步镜像', () {
    final doc = _document().removeImages('ch1', <String>['p1']);

    expect(_paths(doc.chapterMaps[0]), <String>['p2']);
    final mirror = doc.detail['extern']['downloadChapters'] as List;
    expect(_paths(Map<String, dynamic>.from(mirror[0] as Map)), <String>['p2']);
  });

  test('toJson 往返后镜像与章节一致', () {
    final doc = _document()
        .renameChapter('ch1', '改名')
        .addChapter(id: 'local:1', name: '新章')
        .reorderImages('ch1', <String>['p2', 'p1']);

    final restored = ComicEditDocument.fromJson(
      chaptersJson: doc.toChaptersJson(),
      detailJson: doc.toDetailJson(),
    );

    expect(restored.chapterMaps, doc.chapterMaps);
    expect(restored.eps, doc.eps);
    final mirror = restored.detail['extern']['downloadChapters'] as List;
    expect(mirror.length, doc.chapterMaps.length);
    expect(jsonEncode(mirror), jsonEncode(jsonDecode(doc.toChaptersJson())));
  });

  test('非法 JSON 直接抛 FormatException', () {
    expect(
      () => ComicEditDocument.fromJson(chaptersJson: '[]', detailJson: '[]'),
      throwsFormatException,
    );
    expect(
      () => ComicEditDocument.fromJson(chaptersJson: '{}', detailJson: '{}'),
      throwsFormatException,
    );
  });
}
