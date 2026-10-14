import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/src/rust/api/file_manager/types.dart';
import 'package:zephyr/workspace/widgets/cards/file_manager_inline_details.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

FileManagerEntry entry(String name, {bool folder = false}) => FileManagerEntry(
  name: name,
  path: '/books/$name',
  isDir: folder,
  isArchive: !folder,
  isImage: false,
  isVideo: false,
  isAudio: false,
  hasChildren: folder,
  penetratable: false,
  size: BigInt.from(1024),
  modifiedSecs: 1700000000,
  childNames: const [],
);
FileManagerTreeRow row(
  FileManagerEntry entry,
  int depth, {
  bool expanded = false,
}) => FileManagerTreeRow(
  path: entry.path,
  name: entry.name,
  entry: entry,
  depth: depth,
  expanded: expanded,
  loading: false,
  mayHaveChildren: entry.isDir,
  isActive: false,
);

void main() {
  testWidgets('子目录箭头仅展开；名字打开；展开内容沿用树快照和层级', (tester) async {
    final parent = entry('series', folder: true);
    final child = entry('subfolder', folder: true);
    final volume = entry('volume.cbz');
    var opened = '';
    var toggled = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FileManagerInlineDetails(
              entry: parent,
              tree: FileManagerTreeSnapshot(
                rows: [
                  row(parent, 1, expanded: true),
                  row(child, 2, expanded: true),
                  row(volume, 3),
                ],
                hasPending: false,
              ),
              onClose: () {},
              onOpen: (e) => opened = e.path,
              onToggle: (path) => toggled = path,
              rowBuilder: (e) => LibraryEntry(key: e.path, title: e.name),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('volume.cbz'), findsOneWidget);
    await tester.tap(find.byTooltip('收起子文件夹'));
    expect(toggled, child.path);
    expect(opened, isEmpty);
    await tester.tap(find.text(child.name));
    expect(opened, child.path);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索树未包含目标时给出进入入口，不持续显示忙状态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileManagerInlineDetails(
            entry: entry('series', folder: true),
            tree: const FileManagerTreeSnapshot(rows: [], hasPending: false),
            onClose: () {},
            onOpen: (_) {},
            onToggle: (_) {},
            rowBuilder: (e) => LibraryEntry(key: e.path, title: e.name),
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('进入文件夹'), findsOneWidget);
    expect(find.textContaining('快照未包含'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
