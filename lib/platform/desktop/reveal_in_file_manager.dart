import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zephyr/i18n/strings.g.dart';

/// 在**系统**文件管理器里定位一个路径：访达 / 资源管理器 / xdg-open。
///
/// # 为什么单独一层，而不是就地 `Process.run`
///
/// 命令在这里拼成「可执行文件 + 参数数组」，交给 `Process.run` 时**不经过 shell**：
/// 路径里的空格、引号、`$`、反引号、中文都不需要转义，也不会被当成命令的一部分。
/// 拼成一条 shell 字符串写法（`sh -c "open -R '$path'"`）在这份代码里是禁止的 ——
/// 单引号本身就是路径里合法的字符，那等于把用户的文件名当代码执行。
///
/// 拼命令的函数按平台当参数传，所以三家的分支在一台机器上就能全部测到
/// （判据见 `test/workspace/reveal_in_file_manager_check.dart`）。
enum RevealHost { macos, windows, linux, unsupported }

/// 当前跑在哪一类宿主上。
RevealHost currentRevealHost() {
  if (Platform.isMacOS) return RevealHost.macos;
  if (Platform.isWindows) return RevealHost.windows;
  if (Platform.isLinux) return RevealHost.linux;
  return RevealHost.unsupported;
}

/// 一条要执行的命令。
class RevealCommand {
  final String binary;

  /// 参数**数组**，不是字符串。见文件头那条注入口径。
  final List<String> args;

  /// 这条命令是「选中这一项」还是「只打开所在目录」。
  ///
  /// 两家能选中（`open -R`、`/select,`），`xdg-open` 没有选中接口 ——
  /// 分开记着，文案就不许把两者说成同一件事。
  final bool selectsEntry;

  const RevealCommand({
    required this.binary,
    required this.args,
    required this.selectsEntry,
  });

  @override
  String toString() =>
      'RevealCommand($binary ${args.join(" ")}, selectsEntry=$selectsEntry)';
}

/// 造出定位 [path] 要执行的命令。`null` = 这个平台做不到，或路径是空的。
RevealCommand? buildRevealCommand({
  required String path,
  required RevealHost host,
}) {
  if (path.trim().isEmpty) return null;
  switch (host) {
    case RevealHost.macos:
      return RevealCommand(
        binary: 'open',
        args: ['-R', path],
        selectsEntry: true,
      );
    case RevealHost.windows:
      // 一个参数、逗号紧跟着 `/select`：`/select,<完整路径>`。这是资源管理器唯一认的
      // 形状（拆成 `['/select,', path]` 两个参数它不认），照 vendored
      // mImageViewer 的 `capture.rs::reveal_path_async` 同一口径。
      return RevealCommand(
        binary: 'explorer.exe',
        args: ['/select,$path'],
        selectsEntry: true,
      );
    case RevealHost.linux:
      // `xdg-open` 只接受「打开哪个目录」，没有选中某一项的参数。有些桌面环境里的
      // nautilus/dolphin 有 `--select`，但要先把桌面环境判出来 —— 这一层不做，
      // 于是老实打开所在目录，并在文案里这么说。
      return RevealCommand(
        binary: 'xdg-open',
        args: [p.dirname(path)],
        selectsEntry: false,
      );
    case RevealHost.unsupported:
      return null;
  }
}

/// 菜单上那一行该写的词。
///
/// 三个平台露出来的东西不一样，文案也不许写成一样的：Linux 那档实际是
/// 「打开所在目录」（`xdg-open` 没有选中接口），照抄访达的说法就是骗人。
String revealMenuLabel(RevealHost host) {
  switch (host) {
    case RevealHost.macos:
      return t.common.showInFinder;
    case RevealHost.windows:
      return t.common.showInExplorer;
    case RevealHost.linux:
      return t.common.revealInFileManagerFolder;
    case RevealHost.unsupported:
      return t.common.showInFileManager;
  }
}

/// 干完这件事之后该说的那句话。
///
/// 与 [buildRevealCommand] 用同一份 `selectsEntry` 判断，不另起一套平台分支：
/// 「已定位到」和「已打开所在目录」是两件不同的事，说成一件就是在骗人
/// （同 `AppLogService.revealFile` 的口径）。
String revealOutcome({required RevealHost host, required String path}) {
  final command = buildRevealCommand(path: path, host: host);
  switch (host) {
    case RevealHost.macos:
      return '已在访达中显示：$path';
    case RevealHost.windows:
      return '已在资源管理器中选中：$path';
    case RevealHost.linux:
      // 只有命令真的存在（非 null）才会走到这里，所以这一句说的一定是目录。
      if (command?.selectsEntry ?? false) return '已显示：$path';
      return '已打开它所在的目录：${p.dirname(path)}（桌面那边没有选中单个文件的接口）';
    case RevealHost.unsupported:
      return '当前平台无法打开文件管理器：$path';
  }
}

/// 在系统文件管理器里定位 [path]。
///
/// 抛出：
/// - [UnsupportedError]：这个平台做不到（移动端、或空路径）；
/// - [ProcessException]：可执行文件起不来；
/// - [StateError]：命令跑了但报了失败（**Windows 不参与这条判断**，见函数内注释）。
Future<String> revealInFileManager(String path, {RevealHost? host}) async {
  final effectiveHost = host ?? currentRevealHost();
  final command = buildRevealCommand(path: path, host: effectiveHost);
  if (command == null) {
    throw UnsupportedError('当前平台无法在文件管理器里显示：$path');
  }
  final result = await Process.run(command.binary, command.args);
  // Windows 不看退出码：`explorer.exe` 复用已经开着的窗口时返回码并不可靠
  // （成功也常常非 0），拿它当失败会把每次做对的操作都报成错。这条本机无法取证
  // （没有 Windows 桌面会话），所以宁可漏报也不误报；起不来的情况仍由
  // `Process.run` 抛的异常兜住。
  if (effectiveHost != RevealHost.windows && result.exitCode != 0) {
    throw StateError(
      '${result.stderr}'.trim().isEmpty
          ? '退出码 ${result.exitCode}'
          : '${result.stderr}',
    );
  }
  return revealOutcome(host: effectiveHost, path: path);
}
