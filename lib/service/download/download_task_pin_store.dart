import 'package:shared_preferences/shared_preferences.dart';

/// 「优先下载哪几章」的落点：设备本地的一份有序 chapterKey 列表。
///
/// 记在这里而不是任务 payload 里，有两个理由：它是这块屏上的调度意图（跟设备走、
/// 跟账号无关，和视图密度同一档）；而 payload 是 freezed 生成的版本化 JSON，
/// 为一条本地排序去动它的 schema、给所有历史任务补字段，代价与收益不成比例。
class DownloadTaskPinStore {
  const DownloadTaskPinStore();

  static const _key = 'download_task_pinned_order';

  /// 队首在前的 key 列表；没置顶过就是空表。
  Future<List<String>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key);
    if (stored == null) return const <String>[];
    return List<String>.unmodifiable(stored);
  }

  Future<void> write(List<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    if (keys.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setStringList(_key, keys);
  }
}
