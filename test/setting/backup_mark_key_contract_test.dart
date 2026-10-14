import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 备份/恢复里章节标记那张表的键名，必须三处一致：
/// 快照收集器（生产方）→ codec 白名单 → 恢复时的取数。
///
/// 为什么用源码扫描尺而不是功能测试：这条链要造真 zip、解压、还要过
/// `WorkspaceLayoutBridge` 与 path_provider，单测里只能靠 mock 撑起来，
/// 而它真正的失败模式很朴素 —— **某处键名改了、另两处没改**。
/// 那种不一致不会让任何测试变红，只会让「恢复备份后手动标记全没了」静默发生。
///
/// 尺子本身配了阳性对照：故意改一个字母必须扫不出来，否则这把尺是瞎的。
const _key = 'comicChapterReadMark';
const _syncKey = 'chapterReadMarks';

String _src(String path) => File(path).readAsStringSync();

void main() {
  group('章节标记的表必须被同步全链路登记', () {
    test('快照收集器写出的键 == codec 认的键 == 恢复取的键', () {
      final snapshot = _src('lib/object_box/object_box.dart');
      final codec = _src('lib/page/setting/data_backup/backup_codec.dart');
      final restore = _src('lib/page/setting/data_backup/method.dart');

      expect(
        snapshot,
        contains("'$_key': readBox("),
        reason: '启动快照/备份的取数处没有再带上这张表',
      );
      expect(
        codec,
        contains("'$_key': ComicChapterReadMark.fromJson"),
        reason: '恢复前的全量反序列化白名单漏了它 —— 清库后这类行会直接丢',
      );
      expect(
        restore,
        contains("json['$_key'] as List?"),
        reason: '恢复时没把它塞回 box',
      );
      expect(
        restore,
        contains('objectbox.${_key}Box.removeAll()'),
        reason: '恢复前的清库没清这张表',
      );
    });

    test('同步载荷的键在导出与合并两侧一致', () {
      final sync = _src('lib/network/sync/comic_sync_core.dart');
      expect(sync, contains("'$_syncKey': chapterReadMarks"));
      expect(sync, contains("data['$_syncKey']"));
    });

    test('阳性对照：改一个字母的键扫不出来（这把尺不是恒真）', () {
      final snapshot = _src('lib/object_box/object_box.dart');
      expect(snapshot, isNot(contains("'${_key}X': readBox(")));
      expect(snapshot, isNot(contains("'comicChapterReadmarks': readBox(")));
    });
  });
}
