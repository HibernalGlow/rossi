import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';

/// 工作台布局的**存取口**。
///
/// 抽成接口而不是直接写文件，是为了让判据能在**内存**里跑完往返：
/// 「重启回来的是不是同一套布局」这件事与「磁盘在哪儿」无关，
/// 用文件系统去验它只会让判据在 CI / 沙箱里变成偶发失败。
abstract class WorkspaceLayoutStore {
  /// 读出快照；`null` = 还没有存过（或存的东西不可用）。
  Future<WorkspaceLayoutSnapshot?> load();

  /// 写入快照。
  Future<void> save(WorkspaceLayoutSnapshot snapshot);

  /// 清掉已存的快照（「重置布局」用）。
  Future<void> clear();
}

/// 内存实现（判据 / widget 测试用）。
class WorkspaceLayoutMemoryStore implements WorkspaceLayoutStore {
  WorkspaceLayoutSnapshot? _stored;
  int saveCount = 0;

  /// 让判据能断言「写了几次」——去抖做错时表现为写入次数暴涨。
  int get writes => saveCount;

  @override
  Future<WorkspaceLayoutSnapshot?> load() async => _stored;

  @override
  Future<void> save(WorkspaceLayoutSnapshot snapshot) async {
    _stored = snapshot;
    saveCount++;
  }

  @override
  Future<void> clear() async {
    _stored = null;
  }
}

/// 文件实现（应用里用）。
///
/// 写入是**原子的**（先写 `.tmp` 再 `rename`）：直接覆写时，一次崩溃 / 断电
/// 留下的半截 JSON 会让下次启动**整套布局回到出厂** —— 而这正是本次要修的
/// 那个问题本身。`rename` 在同一文件系统上是原子的，于是「要么旧快照、要么新快照」。
class WorkspaceLayoutFileStore implements WorkspaceLayoutStore {
  WorkspaceLayoutFileStore(this.directory);

  final Directory directory;

  static const String fileName = 'workspace_layout.json';

  File get file => File('${directory.path}${Platform.pathSeparator}$fileName');

  File get _tempFile =>
      File('${directory.path}${Platform.pathSeparator}$fileName.tmp');

  @override
  Future<WorkspaceLayoutSnapshot?> load() async {
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final json = WorkspaceLayoutSnapshot.decode(jsonDecode(raw));
      if (json == null) return null;
      return WorkspaceLayoutSnapshot.fromJson(json);
    } on Object {
      // 读不出来就当没存过：布局是**可重建**的东西，为它挡住启动不值得。
      // （注意这里不能只捕 IOException —— 手改坏的 JSON 抛的是 FormatException。）
      return null;
    }
  }

  @override
  Future<void> save(WorkspaceLayoutSnapshot snapshot) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    await _tempFile.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
    await _tempFile.rename(file.path);
  }

  @override
  Future<void> clear() async {
    if (await file.exists()) await file.delete();
    if (await _tempFile.exists()) await _tempFile.delete();
  }
}

/// 把「状态变了」翻译成「存一次」，并**去抖**。
///
/// 去抖是必须的：拖分隔条时状态每帧都在变，逐次落盘会一边拖一边写盘。
/// 去抖的窗口取 [debounce]，并且**退出前必须 flush**（见 [flush]）——
/// 否则「拖完立刻关窗口」这一下正好落在窗口里，改动丢掉。
class WorkspaceLayoutPersistence {
  WorkspaceLayoutPersistence({
    required this.store,
    this.debounce = const Duration(milliseconds: 420),
  });

  final WorkspaceLayoutStore store;
  final Duration debounce;

  WorkspaceLayoutSnapshot? _pending;
  Timer? _timer;

  /// 还压着没写盘的快照（判据用）。
  WorkspaceLayoutSnapshot? get pending => _pending;

  /// 排一次写盘。连续调用只会落最后一次。
  void schedule(WorkspaceLayoutSnapshot snapshot) {
    _pending = snapshot;
    _timer?.cancel();
    _timer = Timer(debounce, flush);
  }

  /// 立刻把压着的快照写掉。没有压着的就什么都不做。
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final snapshot = _pending;
    if (snapshot == null) return;
    _pending = null;
    await store.save(snapshot);
  }

  Future<void> reset() async {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    await store.clear();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
