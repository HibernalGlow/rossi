import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_info/method/export_and_delete.dart';
import 'package:zephyr/page/comic_info/method/export_comic.dart';

Uint8List _buildZip() {
  final payload = '{"id":"abc"}'.codeUnits;
  final archive = Archive()
    ..addFile(ArchiveFile('comic_info.json', payload.length, payload))
    ..addFile(ArchiveFile('01.jpg', 3, const [0xff, 0xd8, 0xff]));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  group('zip 完整性判据', () {
    test('完整 zip 判真（阳性对照）', () async {
      final dir = await Directory.systemTemp.createTemp('export_gate_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/full.zip');
      await file.writeAsBytes(_buildZip());

      expect(await hasZipEndOfCentralDirectory(file), isTrue);
    });

    test('砍掉尾部的半截 zip 判假', () async {
      final dir = await Directory.systemTemp.createTemp('export_gate_');
      addTearDown(() => dir.delete(recursive: true));
      final bytes = _buildZip();
      final file = File('${dir.path}/truncated.zip');
      // 中央目录结束记录在最后，砍掉 5 字节就一定砍掉了它，而文件仍然非空。
      await file.writeAsBytes(bytes.sublist(0, bytes.length - 5));

      expect(await file.length(), greaterThan(0));
      expect(await hasZipEndOfCentralDirectory(file), isFalse);
    });

    test('非 zip 内容判假', () async {
      final dir = await Directory.systemTemp.createTemp('export_gate_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/junk.zip');
      await file.writeAsBytes(List.filled(1024, 0x41));

      expect(await hasZipEndOfCentralDirectory(file), isFalse);
    });
  });

  group('导出完整度', () {
    test('有缺页就不算完整', () {
      expect(_makeResult(exported: 30, missing: 2).complete, isFalse);
    });

    test('一页都没有不算完整', () {
      expect(_makeResult(exported: 0, missing: 0).complete, isFalse);
    });

    test('页页齐才算完整', () {
      expect(_makeResult(exported: 32, missing: 0).complete, isTrue);
    });
  });
}

ComicExportResult _makeResult({required int exported, required int missing}) {
  return ComicExportResult(
    path: '/tmp/whatever.zip',
    title: 't',
    exportedPages: exported,
    missingPages: missing,
    missingChapters: missing > 0 ? const ['第 1 话'] : const [],
  );
}
