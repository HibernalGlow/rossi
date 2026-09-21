/// 书架卡片视图状态（视图档位 + 排序）的落盘口。
///
/// 为什么不走 `GlobalSetting`：那两个值是**界面状态**而不是设置项 —— 它不进
/// 数据备份、不参与 WebDAV 同步、也不该出现在设置页里，为一个「上次用的是
/// 哪一档视图」去加 freezed 字段并把整套生成物拖进来，代价与收益不成比例。
/// 文件管理器的视图记忆住在 Rust 的 `settings.db` 里（按目录记），书签与历史
/// 没有目录可言，所以这里是一条独立的 Dart 侧通道。
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/model/shelf_view_state.dart';

/// 一张卡片的视图状态能读能写。
abstract interface class ShelfViewStateStore {
  /// 这张卡片上次用的视图与排序；没存过 ⇒ null。
  Future<ShelfViewState?> read(String cardId);

  /// 记下这次用的视图与排序。
  Future<void> write(String cardId, ShelfViewState state);
}

/// 落盘实现：一个键存整份文档（卡片 id ⇒ 状态）。
///
/// 写是用户点一下工具栏才发生一次，量级是「一天几十次」，所以不做去抖 ——
/// 少了那层，「换完视图立刻杀进程」也不会丢。
class PreferencesShelfViewStateStore implements ShelfViewStateStore {
  PreferencesShelfViewStateStore({this.namespace = kShelfViewStateNamespace});

  final String namespace;

  final Map<String, ShelfViewState> _states = <String, ShelfViewState>{};
  Future<void>? _loading;

  Future<void> _ensureLoaded() {
    return _loading ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        _states.addAll(parseShelfViewStates(prefs.getString(namespace)));
      } on Object {
        // 兜的是 SharedPreferences 本身不可用，不是坏 JSON（后者在
        // [parseShelfViewStates] 里就已经退成空文档了）。读不到就当没存过。
      }
    }();
  }

  @override
  Future<ShelfViewState?> read(String cardId) async {
    await _ensureLoaded();
    return _states[cardId];
  }

  @override
  Future<void> write(String cardId, ShelfViewState state) async {
    // 先确保读过：整份文档是整体覆写的，没打底就把另一张卡片那一条冲掉了。
    await _ensureLoaded();
    _states[cardId] = state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      namespace,
      jsonEncode(encodeShelfViewStates(_states)),
    );
  }
}

/// 应用里那一份。书签与历史共用一个键空间，各自只写自己那一条。
final ShelfViewStateStore shelfViewStateStore =
    PreferencesShelfViewStateStore();

/// 卡片侧的那一份记忆：只管「恢复」与「用户改动」谁说了算。
///
/// 恢复是异步的（读偏好），而用户手快完全可能在它就绪之前就把档位换了 ——
/// 这时候以他的操作为准，不能让一次迟到的恢复把刚选的东西盖回去。这个守卫
/// 必须挂在**卡片实例**上（所以是一个由 State 持有的对象，而不是 store 的字段）：
/// store 活得比卡片久，把标记放它上面会让下次打开这张卡时恢复被错误地压掉。
class ShelfViewMemory {
  ShelfViewMemory(this.cardId);

  final String cardId;
  bool _touched = false;

  /// 该恢复回来的那一组值。用户已经动过、或这一张卡没存过 ⇒ null。
  Future<ShelfViewState?> restore() {
    if (_touched) return Future<ShelfViewState?>.value();
    return shelfViewStateStore.read(cardId);
  }

  /// 记下当前这一组值。写失败不声张：视图状态丢了只是回到默认档。
  void remember(ShelfViewState state) {
    _touched = true;
    unawaited(shelfViewStateStore.write(cardId, state));
  }
}
