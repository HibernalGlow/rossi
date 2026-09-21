// 共享视图层（`library_view`）的 widget 判据。
//
// 这一层刻意不碰 ObjectBox、不碰 FRB、也不碰全局设置 —— 它只认
// `LibraryEntry`。所以这个测试不需要 `file_manager_card_test.dart` 那套
// cubit 替身，也不受那些跨会话生成物（freezed / i18n）的影响。
//
// 钉的是抽取过程中最容易悄悄改掉的东西：
//
//   1. **六档视图都要画得出全部条目** —— 抽取时漏掉一档不会报错，只会那一档空；
//   2. **详细信息表头点哪列就把那一列的 key 交出去**，且当前列带方向箭头；
//   3. **enabled=false 必须真的不接点击**（文件管理器在 `_busy` 下靠这个）；
//   4. **wrapRow 逐行生效** —— 书签与历史的右键菜单宿主挂在它上面，
//      只在第一行生效的 bug 在界面上几乎看不出来；
//   5. **缩略图只在 thumbModes 列出的档位出现** —— 书签全档画封面、文件管理器
//      紧凑档只画图标，两边靠这一个集合区分。
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view.dart';

class _Marker extends StatelessWidget {
  const _Marker(this.tag);
  final String tag;

  @override
  Widget build(BuildContext context) => SizedBox(key: ValueKey('media:$tag'));
}

class _WrapMarker extends StatelessWidget {
  const _WrapMarker({required this.tag, required this.child});
  final String tag;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Stack(key: ValueKey('wrap:$tag'), children: [child]);
}

List<LibraryEntry> _entries({int count = 3, Set<LibraryViewMode>? thumbModes}) {
  return [
    for (var i = 0; i < count; i++)
      LibraryEntry(
        key: 'k$i',
        title: '标题$i',
        subtitle: '副标题$i',
        metaText: '元$i',
        media:
            (
              context, {
              required width,
              required height,
              required radius,
              required fit,
            }) => _Marker('k$i'),
        badge: const Icon(Icons.book_outlined),
        thumbModes: thumbModes ?? LibraryViewMode.values.toSet(),
        detailCells: ['列A$i', '列B$i', '列C$i'],
      ),
  ];
}

const _columns = [
  LibraryColumn(key: 'author', label: '作者', width: 90),
  LibraryColumn(key: 'source', label: '来源', width: 70),
  LibraryColumn(key: 'time', label: '时间', width: 90),
];

/// [settle] 为假时只推一帧 —— 忙遮罩里的 `CircularProgressIndicator` 是
/// 无限动画，`pumpAndSettle` 收不住尾。
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 340,
  double height = 500,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      // `Material` 是必须的：行用的是 `InkWell`，它要求最近的 LookupBoundary
      // 之内有 Material。真实宿主（文件管理器卡片自己带圆角 Material，
      // 书签/历史卡片住在泳道面板里）都提供，测试这里补上同样的一层。
      home: Material(
        child: SizedBox(width: width, height: height, child: child),
      ),
    ),
  );
  settle ? await tester.pumpAndSettle() : await tester.pump();
}

void main() {
  testWidgets('六档视图都画得出全部条目', (tester) async {
    for (final mode in LibraryViewMode.values) {
      await _pump(
        tester,
        LibraryEntryList(mode: mode, entries: _entries(), onTap: (_) {}),
      );
      for (var i = 0; i < 3; i++) {
        expect(find.text('标题$i'), findsWidgets, reason: '$mode 这一档没把条目标题画出来');
      }
    }
  });

  testWidgets('缩略图只在 thumbModes 列出的档位出现', (tester) async {
    const only = {LibraryViewMode.coverList};
    await _pump(
      tester,
      LibraryEntryList(
        mode: LibraryViewMode.coverList,
        entries: _entries(thumbModes: only),
        onTap: (_) {},
      ),
    );
    expect(find.byKey(const ValueKey('media:k0')), findsOneWidget);

    await _pump(
      tester,
      LibraryEntryList(
        mode: LibraryViewMode.compact,
        entries: _entries(thumbModes: only),
        onTap: (_) {},
      ),
    );
    expect(
      find.byKey(const ValueKey('media:k0')),
      findsNothing,
      reason: '紧凑档被排除了，就该退化成语义图标而不是偷偷画封面',
    );
  });

  testWidgets('缩略图槽永远拿得到有限尺寸', (tester) async {
    // `CoverWidget` 会拿宽高算 `(width * dpr * 1.2).round()`，无限值会
    // 直接抛「Unsupported operation: Infinity or NaN toInt」，在界面上
    // 变成一整片红色异常块。网格两档的格子尺寸只有布局时才知道，
    // 所以必须由宿主用 LayoutBuilder 把真实宽高交出去，而不是传 infinity。
    for (final mode in LibraryViewMode.values) {
      final received = <String>[];
      await _pump(
        tester,
        LibraryEntryList(
          mode: mode,
          entries: [
            LibraryEntry(
              key: 'k0',
              title: '标题0',
              media:
                  (
                    context, {
                    required width,
                    required height,
                    required radius,
                    required fit,
                  }) {
                    received.add('$width x $height');
                    return _Marker('k0');
                  },
              thumbModes: LibraryViewMode.values.toSet(),
            ),
          ],
          onTap: (_) {},
        ),
      );
      expect(received, isNotEmpty, reason: '$mode 这一档根本没画缩略图，测了个空');
      for (final size in received) {
        final parts = size.split(' x ');
        for (final value in parts) {
          expect(
            double.parse(value).isFinite,
            isTrue,
            reason: '$mode 给缩略图槽传了非有限尺寸：$size',
          );
        }
      }
    }
  });

  testWidgets('详细信息表头点击把列 key 交出去', (tester) async {
    String? sorted;
    await _pump(
      tester,
      width: 520,
      LibraryEntryList(
        mode: LibraryViewMode.details,
        entries: _entries(),
        onTap: (_) {},
        titleColumn: const LibraryColumn(key: 'title', label: '标题'),
        columns: _columns,
        sortKey: 'author',
        sortAscending: true,
        onSort: (key) => sorted = key,
      ),
    );

    expect(find.text('作者'), findsOneWidget);
    expect(find.text('来源'), findsOneWidget);
    await tester.tap(find.text('来源'));
    await tester.pumpAndSettle();
    expect(sorted, 'source');

    // 当前排序列带方向箭头，别的列不带 —— 用户靠它认出现在排的是哪一列。
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
  });

  testWidgets('sortable=false 的列表头不接排序', (tester) async {
    // 历史面板的「章节」没有对应的排序字段。画成能点的样子只会让人
    // 点一下什么都没发生。
    String? sorted;
    await _pump(
      tester,
      width: 520,
      LibraryEntryList(
        mode: LibraryViewMode.details,
        entries: _entries(),
        onTap: (_) {},
        columns: const [
          LibraryColumn(
            key: 'chapter',
            label: '章节',
            width: 90,
            sortable: false,
          ),
          LibraryColumn(key: 'source', label: '来源', width: 70),
        ],
        onSort: (key) => sorted = key,
      ),
    );
    await tester.tap(find.text('章节'));
    await tester.pumpAndSettle();
    expect(sorted, isNull);

    await tester.tap(find.text('来源'));
    await tester.pumpAndSettle();
    expect(sorted, 'source');
  });

  testWidgets('enabled=false 时行不接点击', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      LibraryEntryList(
        mode: LibraryViewMode.compact,
        entries: _entries(),
        onTap: (_) => taps++,
        enabled: false,
      ),
    );
    await tester.tap(find.text('标题1'));
    await tester.pumpAndSettle();
    expect(taps, 0);
  });

  testWidgets('点击行交出的是原始实体', (tester) async {
    LibraryEntry? tapped;
    await _pump(
      tester,
      LibraryEntryList(
        mode: LibraryViewMode.compact,
        entries: _entries(),
        onTap: (row) => tapped = row,
      ),
    );
    await tester.tap(find.text('标题2'));
    await tester.pumpAndSettle();
    expect(tapped?.key, 'k2');
  });

  testWidgets('wrapRow 给每一行都套上壳', (tester) async {
    await _pump(
      tester,
      LibraryEntryList(
        mode: LibraryViewMode.compact,
        entries: _entries(),
        onTap: (_) {},
        wrapRow: (context, row, child) =>
            _WrapMarker(tag: row.key, child: child),
      ),
    );
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('wrap:k$i')), findsOneWidget);
    }
  });

  testWidgets('busy 时盖一层进度遮罩', (tester) async {
    await _pump(
      tester,
      LibraryEntryList(
        mode: LibraryViewMode.compact,
        entries: _entries(),
        onTap: (_) {},
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await _pump(
      tester,
      LibraryEntryList(
        mode: LibraryViewMode.compact,
        entries: _entries(),
        onTap: (_) {},
        busy: true,
      ),
      settle: false,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('空列表：standalone 撑满，卡片内给固定高度', (tester) async {
    await _pump(
      tester,
      LibraryEntryList(
        mode: LibraryViewMode.compact,
        entries: const [],
        emptyText: '一个也没有',
        onTap: (_) {},
      ),
    );
    expect(find.text('一个也没有'), findsOneWidget);
    final box = tester.getSize(find.text('一个也没有'));
    expect(box.width, lessThan(340));

    await _pump(
      tester,
      LibraryEntryList(
        mode: LibraryViewMode.compact,
        entries: const [],
        emptyText: '一个也没有',
        standalone: true,
        onTap: (_) {},
      ),
    );
    expect(find.text('一个也没有'), findsOneWidget);
  });
}
