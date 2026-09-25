/// 文件浏览卡片「上次打开的页签」的落盘口。
///
/// 为什么不走 `GlobalSetting`：这一份是**界面状态**而不是设置项 —— 它不进数据
/// 备份、不参与 WebDAV 同步，而且页签一变就得写一次盘。挂进 `FileManagerSettingState`
/// 会让每次开合页签都把整套全局设置重新序列化落库并标脏同步时间戳（同
/// `shelf_view_state_store.dart` 的判断，只是那边写的次数更少）。
/// 开关本身（`restoreTabs`）才是设置项，那个走 `GlobalSetting`。
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/model/file_manager_tab_session.dart';

/// 上次那批页签能读能写。
abstract interface class FileManagerTabSessionStore {
  /// 上次记住的那批页签；没存过、或读不出来 ⇒ null。
  Future<FileManagerTabSession?> read();

  /// 记下这批页签；传 `null` = 清掉（关掉开关、或只剩一个页签时）。
  Future<void> write(FileManagerTabSession? session);
}

/// 落盘实现：一个键存整份文档。
///
/// 不做去抖：写盘只在**页签集合真的变了**的时候发生（见 [FileManagerTabMemory.remember]
/// 的签名判定），量级和「用户点一下新建/关闭页签」一样，而少了那一层
/// 「换完页签立刻杀进程」不会丢。
class PreferencesFileManagerTabSessionStore
    implements FileManagerTabSessionStore {
  PreferencesFileManagerTabSessionStore({
    this.namespace = kFileManagerTabSessionNamespace,
  });

  final String namespace;

  @override
  Future<FileManagerTabSession?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return parseFileManagerTabSession(prefs.getString(namespace));
    } on Object {
      // SharedPreferences 本身不可用 ⇒ 当没存过。恢复不出页签只是回到默认目录，
      // 不该让卡片起不来。
      return null;
    }
  }

  @override
  Future<void> write(FileManagerTabSession? session) async {
    final prefs = await SharedPreferences.getInstance();
    if (session == null) {
      await prefs.remove(namespace);
      return;
    }
    await prefs.setString(namespace, jsonEncode(session.encode()));
  }
}

/// 应用里那一份。
final FileManagerTabSessionStore fileManagerTabSessionStore =
    PreferencesFileManagerTabSessionStore();

/// 卡片侧的那一份记忆：只管「恢复」与「这次该记什么」。
///
/// 挂在**卡片实例**上而不是 store 上（同 `ShelfViewMemory`）：`_signature`
/// 说的是「这一个会话已经落到了哪一步」，store 活得比卡片久，放它上面会让
/// 换布局重建出来的新卡片以为「和上次一样，不用写」。
class FileManagerTabMemory {
  FileManagerTabMemory({FileManagerTabSessionStore? store})
    : _store = store ?? fileManagerTabSessionStore;

  final FileManagerTabSessionStore _store;

  /// 已经落盘那一份的签名，`null` = 盘上什么都没有。
  String? _signature;

  /// 读回上次那批页签。开关关掉时连读都不读：这条路的开销不该由没启用的功能付。
  Future<FileManagerTabSession?> restore({required bool enabled}) async {
    if (!enabled) return null;
    final FileManagerTabSession? saved;
    try {
      saved = await _store.read();
    } on Object {
      return null;
    }
    // 打底：恢复完的这一次会话和盘上是同一份，别为了「重放回来的页签」再写一遍。
    _signature = saved?.signature;
    return saved;
  }

  /// 记下当前这批页签。
  ///
  /// [activeIndex] 越界会被夹回来（调用方的快照与路径表本就是同一份，正常不会越界；
  /// 夹一下是为了「恢复出一个不存在的页签」这种状态不可能被写进盘里）。
  void remember({
    required bool enabled,
    required List<String> paths,
    required int activeIndex,
  }) {
    if (!enabled || paths.length < kFileManagerTabSessionMinTabs) {
      _persist(null);
      return;
    }
    // 超出上限的部分直接丢：核心的第 9 个 `new_tab` 会当场报错，
    // 把 9 个都存下来只是把「恢复」变成一次「恢复失败」。
    final capped = List<String>.unmodifiable(
      paths.take(kFileManagerTabSessionMaxTabs),
    );
    _persist(
      FileManagerTabSession(
        paths: capped,
        activeIndex: activeIndex.clamp(0, capped.length - 1),
      ),
    );
  }

  /// 只在**内容真的变了**的时候落盘 —— [paths] 来自每一份快照，
  /// 导航、排序、搜索这些不动页签的改动都该在这里被挡掉。
  void _persist(FileManagerTabSession? session) {
    final signature = session?.signature;
    if (signature == _signature) return;
    _signature = signature;
    unawaited(
      _store.write(session).catchError((Object _) {
        // 写失败就把签名退回「盘上什么都没有」，下一次页签变化会再试一次。
        // 不声张：页签记忆丢了只是回到默认目录，不值得弹提示。
        _signature = null;
      }),
    );
  }
}
