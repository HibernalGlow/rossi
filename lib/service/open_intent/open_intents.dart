import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:zephyr/util/path_util.dart';

/// 系统文件管理器递进来的「打开这个路径」请求。
///
/// # 为什么需要一个队列，而不是收到就直接导航
/// 请求到达的时机比首页可用**早**：Windows 的命令行参数在 `main()` 第一行就拿到了，
/// macOS 的 `application(_:open:)` 在原生侧把方法通道挂上之前就来了。那时候还没有
/// 能用的 `BuildContext`，push 不了任何路由。所以先在进程里存着，首页挂载后一次取走。
///
/// # 为什么不做扩展名白名单
/// 「什么算能打开的东西」判定在 Rust（`rossi_local_core`：散图文件夹、zip/cbz、
/// rar/cbr、7z/cb7、tar 系列，以及 pdf），Dart 这边再抄一份必然抄漏 ——
/// 漏掉的类型会在菜单里被拒成「打不开这种类型」，而那是假话。
/// 这里只挡两件事：**网络地址**（`http://…` 不是磁盘路径）和**根本不存在的路径**。
/// 类型不对的一律放进阅读器，由核心的拒绝原因去说。
class OpenIntents {
  OpenIntents._();

  static final OpenIntents instance = OpenIntents._();

  /// 与 `macos/Runner/AppDelegate.swift` 里那条通道同名。
  static const MethodChannel _macChannel = MethodChannel(
    'com.breeze.macos/openIntent',
  );

  static final RegExp _windowsDrivePath = RegExp(r'^[a-zA-Z]:[\\/]');

  final List<String> _pending = <String>[];
  final StreamController<List<String>> _arrivals =
      StreamController<List<String>>.broadcast(sync: true);

  /// 新到的一条路径（用于「应用已经开着时被再次右键打开」）。
  Stream<List<String>> get arrivals => _arrivals.stream;

  /// Windows：右键菜单把被选中项作为命令行参数递进来。
  ///
  /// `windows/runner/utils.cpp` 的 `GetCommandLineArguments` 已经跳过 argv[0]
  /// （可执行文件自己），所以这里的每一项都是 Explorer 传的参数。
  void collectFromCommandLine(List<String> arguments) {
    if (kIsWeb || !Platform.isWindows) return;
    for (final raw in arguments) {
      offer(raw);
    }
  }

  /// macOS：装好原生 → Dart 的入站通道，并把「在装好之前就已经到达」的路径取回来。
  ///
  /// 这一次主动 `takePending` 是必须的：Finder 触发的启动里，`application(_:open:)`
  /// 可能早于 `main()` 跑起来，那些路径只存在原生侧的队列里，没人来取就永远不会打开。
  Future<void> attachMacChannel() async {
    if (kIsWeb || !Platform.isMacOS) return;
    _macChannel.setMethodCallHandler((call) async {
      if (call.method != 'openPaths') return;
      final args = call.arguments;
      if (args is! List) return;
      for (final path in args.whereType<String>()) {
        offer(path);
      }
    });
    await pullMacQueue();
  }

  /// 取回原生侧已经攒下的路径。可重复调用，取到即清。
  ///
  /// 吞掉 [MissingPluginException]：原生要先摸到 `FlutterViewController` 才挂得上
  /// 通道，而那一步可能比这里晚。路径**没有丢** —— 它还躺在原生的队列里，
  /// 首页挂载时会再来取一次（见 `bindOpenIntents`）。
  Future<void> pullMacQueue() async {
    if (kIsWeb || !Platform.isMacOS) return;
    try {
      final queued = await _macChannel.invokeMethod<List<Object?>>(
        'takePending',
      );
      for (final path in queued ?? const <Object?>[]) {
        if (path is String) offer(path);
      }
    } on MissingPluginException {
      // 原生侧还没挂上处理器；下一次取会拿到。
    }
  }

  /// 取走当前攒着的全部路径并清空。
  ///
  /// 「取完即清」是有意的：首页会被换语言、换主题重建，如果不清，同一条路径会被
  /// 再开一次阅读器。
  List<String> takeAll() {
    if (_pending.isEmpty) return const <String>[];
    final taken = List<String>.of(_pending);
    _pending.clear();
    return taken;
  }

  /// 登记一条外部递来的请求。参数可以是任何东西 —— 网络地址、相对路径、空串都会
  /// 被丢掉，只有像本地绝对路径的才进队列。
  ///
  /// 平台判定（Windows 命令行 / macOS 通道）**不在这个函数里**，而在两个调用点上：
  /// 这条判定本身与平台无关，得能被测试覆盖（见 `test/service/open_intents_test.dart`）。
  void offer(String raw) {
    final trimmed = raw.trim();
    // 顺序是这里的要点：**网络地址必须在归一之前判**。
    // `p.normalize` 会把 `//img.cdn/a.cbz` 塌成 `/img.cdn/a.cbz`，而 `isNetworkAddress`
    // 认的是开头那对 `//` —— 归一之后再判，协议相对地址就变成一个合法绝对路径，
    // 队列会高高兴兴收下它，然后开成一本打不开的书（这条是测试抓出来的）。
    if (trimmed.isEmpty || isNetworkAddress(trimmed)) return;
    final path = normalizeLocalComicPath(trimmed);
    if (path.isEmpty || !_isAbsolute(path)) return;
    // 一次右键选中几十个文件时 Explorer 会把它们全传进来；重复项按路径去重。
    if (_pending.contains(path)) return;
    _pending.add(path);
    _arrivals.add(<String>[path]);
  }

  bool _isAbsolute(String path) =>
      path.startsWith('/') ||
      path.startsWith(r'\\') ||
      _windowsDrivePath.hasMatch(path);
}
