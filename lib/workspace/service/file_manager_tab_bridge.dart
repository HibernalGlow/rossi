import 'dart:async';

import 'package:flutter/foundation.dart';

/// 一次「新页签打开」请求的结局。
///
/// 分三档而不是一个 `bool`：因为**该弹哪句提示**由结局决定。
/// 只有 `bool` 时调用方只能一律说「打不开」，而真实原因可能是「会话还没起来」
/// 也可能是「核心拒绝了这次导航、卡片已经弹过具体错误了」——后者再补一句
/// 笼统的失败提示，就是把用户从「知道原因」推回「什么都不知道」。
enum FileManagerTabOpenOutcome {
  opened,

  /// 等不到活着的文件管理会话（面板从没打开过，或者刚被拆掉）。
  noSession,

  /// 会话接下了请求但失败了。**具体原因由文件管理卡片自己弹**（它才知道异常是什么），
  /// 调用方不要再补一刀。
  failed,
}

/// 「在文件管理的**新页签**里打开某个目录」的通道。
///
/// # 为什么需要这一层
///
/// 文件管理的会话（Rust `FileManagerState`）是**卡片自己**建的：卡片 `initState`
/// 调 `fileManagerCreate` 拿到一个 `BigInt` 会话 id，`dispose` 时 `fileManagerClose`。
/// 于是「收藏 / 历史卡片的右键 → 在文件管理新页签打开」这件事，发起方（左泳道的
/// 卡片）手里**没有**那个 id —— 它在右泳道另一张卡片的 `State` 里。
///
/// 直接把会话提成全局单例是更大的改动（卡片、面板保活、退出清理都要跟着改），
/// 而这里真正需要的只是一件事：**把一条路径交给当前活着的那个文件管理会话**。
/// 所以照 `WorkspaceNavigationBridge` 的做法收一个窄口子：
///
/// - 卡片在会话就绪时 [attach] 自己，`dispose` 时 [detach]；
/// - 发起方调 [openInNewTab]，拿回一个 [FileManagerTabOpenOutcome] 决定提示什么。
///
/// # 为什么要等
///
/// 用户第一次点这个菜单项时，右泳道很可能**还停在「发现」面板上** —— 文件管理
/// 卡片根本没建过，自然也没登记过。调用方（见 `workspace/method/shelf_entry_actions.dart`）
/// 会先把右泳道切到文件管理面板，卡片随之挂载并开始建会话；建会话是异步的（一次
/// FRB 调用）。所以这里给它一个有上限的等待，而不是「这一刻没有就永远没有」。
///
/// 上限必须有：桥没接上时绝不能让调用方一直挂着 —— 那样用户看到的是「点了没反应」，
/// 比弹一句「文件管理还没准备好」糟得多。
class FileManagerTabBridge {
  FileManagerTabBridge._();

  static final FileManagerTabBridge instance = FileManagerTabBridge._();

  Object? _owner;
  Future<FileManagerTabOpenOutcome> Function(String path)? _opener;

  /// 现在有没有活着的文件管理会话。菜单据此置灰「在文件管理新页签打开」。
  bool get isAttached => _opener != null;

  /// 文件管理卡片在会话就绪后登记自己。
  ///
  /// [owner] 只用来认「登记的是谁」——注销时必须拿同一个对象来，否则一个正在
  /// 退出动画里的旧卡片会把刚上来的新卡片的登记抹掉（与
  /// `WorkspaceNavigationBridge.detachLaneHost` 同一条纪律）。
  void attach(
    Object owner,
    Future<FileManagerTabOpenOutcome> Function(String path) opener,
  ) {
    _owner = owner;
    _opener = opener;
  }

  /// 卡片卸载时注销。只注销自己的那一份。
  void detach(Object owner) {
    if (identical(_owner, owner)) {
      _owner = null;
      _opener = null;
    }
  }

  /// 把 [path] 交给当前（或即将就绪的）文件管理会话，新开一个页签。
  Future<FileManagerTabOpenOutcome> openInNewTab(
    String path, {
    Duration timeout = const Duration(milliseconds: 2000),
    Duration pollInterval = const Duration(milliseconds: 40),
  }) async {
    final deadline = DateTime.now().add(timeout);
    // 先看一眼再等：桥已经接上时不该白等一个 pollInterval（菜单连点两次就是这个路径）。
    while (_opener == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
    }
    final opener = _opener;
    if (opener == null) return FileManagerTabOpenOutcome.noSession;
    return opener(path);
  }

  /// 单例在 widget 测试里跨用例会串味（每个用例一棵新树）⇒ 收尾用。
  @visibleForTesting
  void resetForTest() {
    _owner = null;
    _opener = null;
  }
}
