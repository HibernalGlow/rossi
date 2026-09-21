// 书签 / 历史面板搜索与排序的**纯 Dart** 判据。
//
//   dart run test/workspace/shelf_library_query_check.dart
//
// 钉住几条不看代码想不到的行为：
//
//   1. **空关键词不产生新列表对象之外的任何过滤** —— 一旦写错成
//      `contains('')` 之外的判断，空搜索框会把列表清空；
//   2. **并列项的顺序必须稳定** —— 排序取负的时候容易把 key 兜底也一起取负，
//      那样每次 ObjectBox 流推一遍，同名条目的顺序就自己换位置；
//   3. **未分类 ≠ 全部**：空集与 null 是两种意思；
//   4. **点同一字段翻转方向，换字段回到默认降序**；
//   5. **第二行不重复第一行** —— 本地漫画的「章节名」就是它自己的文件名
//      （`cp.zip` 那一本的章节就叫 `cp.zip`），丢掉这一段之后剩下的段之间
//      也不能留下孤零零的「 · 」。
//   6. **来源标记优先用插件自己报的名字** —— 插件 id 是一串 uuid，摆在行上
//      认不出来；真名字不做 `.toUpperCase()`，查不到名字时 uuid 只留前 8 位。
//
// 没有 package:test 依赖（跟 `shelf_entry_menu_check.dart` 同一套路）。
//
// ignore_for_file: avoid_print

import 'package:zephyr/workspace/model/shelf_library_query.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

ShelfSearchable _item(
  String key, {
  String title = '',
  String author = '',
  String source = '',
  int minutes = 0,
  String? haystack,
}) {
  return ShelfSearchable(
    key: key,
    title: title.isEmpty ? key : title,
    author: author,
    source: source,
    time: DateTime(2026, 1, 1).add(Duration(minutes: minutes)),
    haystack: haystack ?? [title, author, source, key].join(' ').toLowerCase(),
  );
}

List<String> _keys(List<ShelfSearchable> items) =>
    items.map((item) => item.key).toList();

void main() {
  _emptyKeywordKeepsEverything();
  _keywordMatchesAnywhereInHaystack();
  _normalizeAppliesToBothSides();
  _timeDefaultsToNewestFirst();
  _togglingAndSwitchingFields();
  _tiesStayStable();
  _unfiledIsNotEmptySet();
  _searchThenSortPipeline();
  _creatorComesInTwoShapes();
  _haystackCoversEveryField();
  _sourceLabelSaysLocalNotAPath();
  _realPluginNameBeatsTheUuid();
  _nameLookupIgnoresUuidCase();
  _chapterDoesNotRepeatTheBookName();
  _metaLineDropsEmptyParts();

  print('shelf_library_query_check: $_passed checks passed');
}

void _creatorComesInTwoShapes() {
  check('纯文本作者名原样用', shelfCreatorName('尾田荣一郎') == '尾田荣一郎');
  check('JSON 形态取 name', shelfCreatorName('{"name":"岸本齐史","id":7}') == '岸本齐史');
  check('空串还是空串', shelfCreatorName('   ').isEmpty);
  check('坏 JSON 退化为原文而不是吞掉', shelfCreatorName('{"name":') == '{"name":');
  check(
    'JSON 里没有 name ⇒ 没有作者，而不是把 JSON 当名字显示',
    shelfCreatorName('{"id":1}') == '',
  );
}

void _haystackCoversEveryField() {
  final text = shelfHaystack(
    comicId: 'c-1',
    title: '航海王',
    description: '大海贼时代',
    creator: '{"name":"尾田荣一郎"}',
    titleMeta: '浏览：123',
    metadata: '[{"type":"标签","value":["热血"]}]',
  );
  for (final needle in ['c-1', '航海王', '大海贼', '尾田荣一郎', '热血']) {
    check('搜索面覆盖 $needle', text.contains(needle));
  }
}

void _emptyKeywordKeepsEverything() {
  final items = [_item('a'), _item('b'), _item('c')];
  for (final keyword in ['', '   ']) {
    final out = filterShelf(items, keyword: keyword);
    check('空关键词「$keyword」不过滤', _keys(out).join() == 'abc');
  }
}

void _keywordMatchesAnywhereInHaystack() {
  final items = [
    _item('a', title: '山田花子', author: '渡边', source: 'bika'),
    _item('b', title: 'John Doe', author: 'Smith', source: 'jm'),
  ];
  check('命中标题', _keys(filterShelf(items, keyword: 'john')).join() == 'b');
  check('命中作者', _keys(filterShelf(items, keyword: '渡边')).join() == 'a');
  check('命中来源且不区分大小写', _keys(filterShelf(items, keyword: 'JM')).join() == 'b');
  check('不命中则空', filterShelf(items, keyword: 'zzz').isEmpty);
}

void _normalizeAppliesToBothSides() {
  // 假归一化：把「繁」映射成「简」，模拟 t2s 的角色。
  String fake(String text) => text.replaceAll('書籤', '书签').toLowerCase();
  final items = [_item('a', haystack: '書籤 第一本'), _item('b', haystack: '其他')];
  check(
    '关键词经过同一套归一化',
    _keys(filterShelf(items, keyword: '书签', normalize: fake)).join() == 'a',
  );
  check(
    '排序按归一化后的标题比（大小写不敏感）',
    _keys(
          sortShelf([
            _item('z', title: 'B'),
            _item('y', title: 'a'),
          ], const ShelfSort(field: ShelfSortField.title, ascending: true)),
        ).join() ==
        'yz',
  );
}

void _timeDefaultsToNewestFirst() {
  final items = [_item('old', minutes: 1), _item('new', minutes: 9)];
  final out = sortShelf(items, const ShelfSort(field: ShelfSortField.time));
  check('时间排序默认新的在前', _keys(out).join() == 'newold');
  final asc = sortShelf(
    items,
    const ShelfSort(field: ShelfSortField.time, ascending: true),
  );
  check('升序时旧的在前', _keys(asc).join() == 'oldnew');
}

void _togglingAndSwitchingFields() {
  const initial = ShelfSort(field: ShelfSortField.time);
  final flipped = initial.toggled(ShelfSortField.time);
  check('点同一字段翻转方向', flipped.ascending && flipped.field == initial.field);
  final switched = flipped.toggled(ShelfSortField.title);
  check('换字段回到默认降序', !switched.ascending);
  check('换字段换到了对的字段', switched.field == ShelfSortField.title);
}

void _tiesStayStable() {
  // 三条标题与时间全同，只有 key 不同。
  final items = [
    _item('c', title: '同', minutes: 5),
    _item('a', title: '同', minutes: 5),
    _item('b', title: '同', minutes: 5),
  ];
  final desc = sortShelf(items, const ShelfSort(field: ShelfSortField.title));
  final again = sortShelf(
    items.reversed.toList(),
    const ShelfSort(field: ShelfSortField.title),
  );
  check('降序时 key 兜底仍为升序', _keys(desc).join() == 'abc', _keys(desc).join());
  check('输入顺序不影响结果', _keys(desc).join() == _keys(again).join());
}

void _unfiledIsNotEmptySet() {
  final items = [_item('a'), _item('b')];
  check('null 表示全部', selectShelf(items).length == 2);
  check('空集表示真的没有', selectShelf(items, memberKeys: {}).isEmpty);
  check('按成员集挑', _keys(selectShelf(items, memberKeys: {'b'})).join() == 'b');
}

void _searchThenSortPipeline() {
  final items = [
    _item('a', title: 'zz', source: 'jm', minutes: 1),
    _item('b', title: 'aa', source: 'jm', minutes: 9),
    _item('c', title: 'mm', source: 'bika', minutes: 5),
  ];
  final out = searchAndSortShelf(
    items,
    keyword: 'jm',
    sort: const ShelfSort(field: ShelfSortField.time),
  );
  check('先筛后排', _keys(out).join() == 'ba');
  final byTitle = searchAndSortShelf(
    items,
    keyword: '',
    sort: const ShelfSort(field: ShelfSortField.title, ascending: true),
  );
  check('全量按标题升序', _keys(byTitle).join() == 'bca');
}

void _sourceLabelSaysLocalNotAPath() {
  check(
    '插件来源就是插件 id 大写',
    shelfSourceLabel(source: 'jm', comicId: '123456') == 'JM',
  );
  check(
    '本地归档不显示成 LOCAL',
    shelfSourceLabel(source: 'local', comicId: '/sdcard/cp.zip') == '本地',
  );
  check(
    'source 存成整条路径也算本地',
    shelfSourceLabel(source: '', comicId: r'D:\books\cp.zip') == '本地',
  );
  check(
    '网络地址不算本地',
    shelfSourceLabel(source: 'bika', comicId: 'https://x/1') == 'BIKA',
  );
}

/// 插件 id 是一串 uuid，行上光靠大写认不出来 —— 名字由调用方查表传进来。
void _realPluginNameBeatsTheUuid() {
  const uuid = 'A16835E9-D405-4E01-8019-08E30BA6CDE2';
  check(
    '有名字就用名字，且不做大写（BikaACG 不该变成 BIKAACG）',
    shelfSourceLabel(source: uuid, comicId: '42', pluginName: 'BikaACG') ==
        'BikaACG',
  );
  check(
    '中文名照原样',
    shelfSourceLabel(source: uuid, comicId: '42', pluginName: '禁漫公寓') ==
        '禁漫公寓',
  );
  check(
    '名字只有空白 ⇒ 退回 id',
    shelfSourceLabel(source: 'jm', comicId: '42', pluginName: '   ') == 'JM',
  );
  check(
    '查不到名字退回 uuid 前 8 位（整串会吃掉行宽，完整 id 右键复制）',
    shelfSourceLabel(source: uuid, comicId: '42') == 'A16835E9',
  );
  check(
    '不是 uuid 的短 id 照旧大写',
    shelfSourceLabel(source: 'jm', comicId: '42') == 'JM',
  );
  check(
    'uuid 小写写法也只留前 8 位，并按老口径大写',
    shelfSourceLabel(source: uuid.toLowerCase(), comicId: '42') == 'A16835E9',
  );
  check(
    '本地优先于名字：存过名字的本地条目不该被标成插件',
    shelfSourceLabel(
      source: 'local',
      comicId: '/sdcard/cp.zip',
      pluginName: '某个插件',
    ) == '本地',
  );
}

/// 名字表按小写键存，记录里的 `source` 不保证同一写法。
void _nameLookupIgnoresUuidCase() {
  const names = <String, String>{
    'a16835e9-d405-4e01-8019-08e30ba6cde2': '禁漫公寓',
  };
  check(
    '库里小写、记录里大写也能命中',
    shelfPluginName(names, 'A16835E9-D405-4E01-8019-08E30BA6CDE2') == '禁漫公寓',
  );
  check(
    '两侧空白不算内容',
    shelfPluginName(names, '  a16835e9-d405-4e01-8019-08e30ba6cde2 ') ==
        '禁漫公寓',
  );
  check('查不到返回 null（不是空串）', shelfPluginName(names, 'jm') == null);
  check('空 source 返回 null', shelfPluginName(names, '   ') == null);
  check(
    '查到 null 时行上退回 uuid 前缀',
    shelfSourceLabel(
      source: 'A16835E9-D405-4E01-8019-08E30BA6CDE2',
      comicId: '42',
      pluginName: shelfPluginName(names, 'A16835E9-D405-4E01-8019-08E30BA6CDE2'),
    ) == '禁漫公寓',
  );
}

void _chapterDoesNotRepeatTheBookName() {
  check(
    '本地归档：章节名 = 文件名 ⇒ 不显示',
    shelfChapterLabel(title: 'cp', chapterTitle: 'cp.zip') == '',
  );
  check(
    '本地目录：章节名 = 目录名（无后缀）⇒ 不显示',
    shelfChapterLabel(title: 'pages', chapterTitle: 'pages') == '',
  );
  check(
    '章节名存成整条路径也算重复',
    shelfChapterLabel(title: 'cp', chapterTitle: '/sdcard/Download/cp.zip') ==
        '',
  );
  check(
    '大小写与后缀写法不同仍是同一个名字',
    shelfChapterLabel(title: 'CP', chapterTitle: 'cp.ZIP') == '',
  );
  check(
    '插件给的章节名照原样留',
    shelfChapterLabel(title: '航海王', chapterTitle: '全1话 (37P)') == '全1话 (37P)',
  );
  check(
    '本地漫画里的真章节（子目录名）要留',
    shelfChapterLabel(title: '某本', chapterTitle: '第3话') == '第3话',
  );
  check('没有章节 ⇒ 空串', shelfChapterLabel(title: 'x', chapterTitle: '   ') == '');
}

void _metaLineDropsEmptyParts() {
  check('丢掉重复章节后不留空段', joinShelfMeta(['本地', '', 'P.3']) == '本地 · P.3');
  check(
    '照旧拼三段',
    joinShelfMeta(['JM', '全1话 (37P)', 'P.14']) == 'JM · 全1话 (37P) · P.14',
  );
  check('全空 ⇒ 空串', joinShelfMeta(['', '  ']).isEmpty);
}
