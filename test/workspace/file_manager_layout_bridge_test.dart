import 'dart:io';
import 'dart:ffi' show Abi;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/src/rust/api/file_manager/browse.dart';
import 'package:zephyr/src/rust/api/file_manager/search.dart';
import 'package:zephyr/src/rust/api/file_manager/settings.dart';
import 'package:zephyr/src/rust/api/file_manager/tree.dart';
import 'package:zephyr/src/rust/api/file_manager/types.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

void main() {
  setUpAll(() async {
    // flutter test 已编好当前源码的 debug native asset；内容哈希照常校验。
    final host = switch (Abi.current()) {
      Abi.macosArm64 => 'aarch64-apple-darwin',
      Abi.macosX64 => 'x86_64-apple-darwin',
      Abi.linuxArm64 => 'aarch64-unknown-linux-gnu',
      Abi.linuxX64 => 'x86_64-unknown-linux-gnu',
      Abi.windowsArm64 => 'aarch64-pc-windows-msvc',
      Abi.windowsX64 => 'x86_64-pc-windows-msvc',
      _ => null,
    };
    final library = Platform.isMacOS
        ? 'libwindcore.dylib'
        : Platform.isWindows
        ? 'windcore.dll'
        : 'libwindcore.so';
    final debugAsset = 'rust/target/native-assets/$host/debug/$library';
    await RustLib.init(
      externalLibrary: host != null && File(debugAsset).existsSync()
          ? ExternalLibrary.open(debugAsset)
          : null,
    );
  });

  test('真实桥接：普通树融合文件卡片，只有文件的目录仍能收起再展开', () async {
    final root = await Directory.systemTemp.createTemp('rossi_tree_content_');
    final child = await Directory('${root.path}/pages').create();
    await File('${root.path}/parent.cbz').writeAsBytes([1]);
    await File('${child.path}/page.png').writeAsBytes([2]);
    final id = await fileManagerCreate(
      initialPath: root.path,
      rememberViewState: true,
      searchSubfoldersDefault: false,
    );
    try {
      await fileManagerSetLayoutMode(id: id, mode: FileManagerLayoutMode.tree);
      await fileManagerSetViewMode(id: id, mode: FileManagerViewMode.coverGrid);
      FileManagerTreeSnapshot tree = await fileManagerTreeSnapshot(id: id);
      for (var attempt = 0; tree.hasPending && attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        tree = await fileManagerTreeSnapshot(id: id);
      }
      expect(
        tree.rows
            .singleWhere((row) => row.path == '${root.path}/parent.cbz')
            .entry!
            .isArchive,
        isTrue,
      );
      expect(
        tree.rows.singleWhere((row) => row.path == child.path).entry!.isDir,
        isTrue,
      );
      tree = await fileManagerTreeToggle(id: id, path: child.path);
      for (var attempt = 0; tree.hasPending && attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        tree = await fileManagerTreeSnapshot(id: id);
      }
      expect(
        tree.rows
            .singleWhere((row) => row.path == '${child.path}/page.png')
            .entry!
            .isImage,
        isTrue,
      );
      tree = await fileManagerTreeToggle(id: id, path: child.path);
      expect(
        tree.rows.any((row) => row.path == '${child.path}/page.png'),
        isFalse,
      );
      expect(
        tree.rows.singleWhere((row) => row.path == child.path).mayHaveChildren,
        isTrue,
      );
      tree = await fileManagerTreeToggle(id: id, path: child.path);
      expect(
        tree.rows.any((row) => row.path == '${child.path}/page.png'),
        isTrue,
      );
      final navigated = await fileManagerNavigate(id: id, path: child.path);
      expect(navigated.viewMode, FileManagerViewMode.coverGrid);
      await fileManagerSetLayoutMode(
        id: id,
        mode: FileManagerLayoutMode.columns,
      );
      final snapshot = await fileManagerSnapshot(id: id);
      final parent = snapshot.directoryColumns.singleWhere(
        (column) => column.path == root.path,
      );
      expect(
        parent.entries
            .singleWhere((entry) => entry.name == 'parent.cbz')
            .entry!
            .size,
        BigInt.one,
      );
    } finally {
      fileManagerClose(id: id);
      await root.delete(recursive: true);
    }
  });

  test('真实桥接：启动预设、搜索独立页签、层级及未激活触发来源', () async {
    final root = await Directory.systemTemp.createTemp('rossi_layout_bridge_');
    BigInt? id;
    try {
      for (final branch in ['author/short', 'author/long']) {
        await Directory('${root.path}/$branch').create(recursive: true);
        await File('${root.path}/$branch/match.png').writeAsBytes([]);
      }
      const options = FileManagerNewTabOptions(
        policy: FileManagerNewTabPolicy.triggering,
        viewMode: FileManagerViewMode.details,
        layoutMode: FileManagerLayoutMode.tree,
        penetrationEnabled: false,
        showHiddenFiles: false,
        showChildNames: true,
        searchIncludeSubfolders: true,
      );
      id = await fileManagerCreate(
        initialPath: root.path,
        rememberViewState: false,
        searchSubfoldersDefault: true,
        newTabOptions: options,
      );
      final initial = await fileManagerSnapshot(id: id);
      expect(initial.layoutMode, FileManagerLayoutMode.tree);
      expect(initial.viewMode, FileManagerViewMode.details);
      final source = initial.activeTabId;
      final pending = await fileManagerSearchInNewTab(id: id, query: 'match');
      expect(pending.tabs.length, 2);
      expect(pending.activeTabId, isNot(source));
      final found = await fileManagerSearch(id: id);
      expect(found.searchActive, isTrue);
      expect(found.entries.length, 2);
      final tree = await fileManagerTreeSnapshot(id: id);
      expect(tree.rows.where((r) => r.entry != null).length, 2);
      expect(tree.rows.any((r) => r.name == 'author'), isTrue);
      await fileManagerSetLayoutMode(
        id: id,
        mode: FileManagerLayoutMode.columns,
      );
      final columns = await fileManagerSelectSearchDirectory(
        id: id,
        path: '${root.path}/author/short',
      );
      expect(columns.directoryColumns.length, 3);
      expect(columns.viewMode, FileManagerViewMode.details);
      final origin = await fileManagerActivateTab(id: id, tabId: source);
      expect(origin.searchQuery, isEmpty);
      expect(origin.searchActive, isFalse);
      await fileManagerActivateTab(id: id, tabId: found.activeTabId);
      final child = await fileManagerNewTab(
        id: id,
        path: root.path,
        sourceTabId: source,
      );
      expect(child.layoutMode, FileManagerLayoutMode.tree);
      expect(child.searchQuery, isEmpty);
      expect(child.searchActive, isFalse);
      final retained = await fileManagerActivateTab(
        id: id,
        tabId: found.activeTabId,
      );
      expect(retained.entries.length, 2);
      expect(retained.layoutMode, FileManagerLayoutMode.columns);
    } finally {
      if (id != null) fileManagerClose(id: id);
      await root.delete(recursive: true);
    }
  });
}
