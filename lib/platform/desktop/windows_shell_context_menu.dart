import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win32;

/// Windows 资源管理器右键菜单「用 Rossi 打开」的注册与注销。
///
/// 全部写在 `HKCU\Software\Classes` 下：这一棵是**当前用户**的类注册表，系统会把它
/// 合并进 `HKCR`，所以不需要管理员权限，也不影响别的用户。口径与安装器现有的卸载项
/// 一致（它同样写 HKCU）。
///
/// # 为什么状态的真源是注册表，不是 GlobalSetting
/// 这颗开关的语义是「这台机器上有没有这些键」，不是「用户想要什么」：
/// 用户在 regedit 里手工删掉，菜单项就真没了 —— 设置页若还显示"开"就是在撒谎。
/// 所以这里既不读也不写持久化，每次现查。
///
/// # 为什么同时注册两处
/// - `*\shell\Rossi` 与 `Directory\shell\Rossi`：经典注册表动词。Windows 11 的精简
///   右键菜单把它们放进「显示更多选项」，而 Windows 10 与 Shift+右键是一级可见。
/// - `Applications\zephyr.exe`：让 Rossi 进入**「打开方式」候选列表** —— 那一项在
///   Windows 11 的新菜单里一级可见，用户还能由此把它设成默认程序。
/// 两条都注册，是因为「进不进一级菜单」由系统说了算，不随我们的意愿变。
class WindowsShellContextMenu {
  WindowsShellContextMenu._();

  static const _classesRoot = r'Software\Classes';

  /// 右键菜单里那一行的文字。注册表存的是**写进去那一刻**的值，之后换界面语言不会
  /// 自动改写已注册的值 —— 把开关关掉再打开即刷新。
  static const verbLabel = '用 Rossi 打开';

  /// 注册到「打开方式」时顺带声明能接的后缀。
  ///
  /// `.zip` 在里面是有意为之：压缩包是本地漫画最常见的载体。但 `Applications` 这一棵
  /// 只**增加候选**，不改任何后缀的默认程序 —— 用户要的是「右键能选到 Rossi」，
  /// 不是「以后所有 zip 都归 Rossi」。
  static const _supportedExtensions = [
    '.zip',
    '.cbz',
    '.cbr',
    '.rar',
    '.7z',
    '.tar',
  ];

  /// 三个挂载点：选中文件 / 选中文件夹 / 在文件夹空白处右键。
  ///
  /// `%1` 与 `%V` 都展开成被选中项的完整路径；区别在 `Directory\Background` 下
  /// `%1` 不展开（会留下字面量 `%1`），必须用 `%V`。
  static const _targets = [
    _ShellTarget(subKeySuffix: r'*\shell\Rossi', argument: '%1'),
    _ShellTarget(subKeySuffix: r'Directory\shell\Rossi', argument: '%V'),
    _ShellTarget(
      subKeySuffix: r'Directory\Background\shell\Rossi',
      argument: '%V',
    ),
  ];

  /// 当前进程自己的 exe —— 命令里要写的程序。
  ///
  /// Flutter 桌面端 `Platform.resolvedExecutable` 返回的就是应用可执行文件本身
  /// （不是 flutter 工具链），所以不需要额外的路径探测。
  static String get executablePath => Platform.resolvedExecutable;

  /// 现在的注册状态。见类注释「为什么每次现查」。
  static WindowsShellIntegrationStatus readStatus() {
    final exe = executablePath;
    final commands = <String>[];
    for (final target in _targets) {
      final command = _readDefaultValue(
        '$_classesRoot\\${target.subKeySuffix}\\command',
      );
      if (command != null && command.isNotEmpty) commands.add(command);
    }
    if (commands.isEmpty) {
      return const WindowsShellIntegrationStatus(registered: false);
    }
    // 只要有一条指向的不是现在这个 exe，就当作「需要重写」：移动过安装目录时
    // 菜单项点了没反应，比少一个菜单项难排查得多。
    final pointsHere = commands.every(
      (command) =>
          command == _commandLine(exe, '%1') ||
          command == _commandLine(exe, '%V'),
    );
    return WindowsShellIntegrationStatus(
      registered: true,
      pointsToCurrentExecutable: pointsHere,
      commandLine: commands.first,
      executablePath: exe,
    );
  }

  /// 写入全部键值。可重复调用（幂等）：`RegCreateKeyEx` 存在即打开，值一律覆盖。
  ///
  /// 失败抛 [WindowsShellIntegrationException]，这里不吞：半途失败会留下
  /// 「菜单项在、指向错地方」的脏状态，必须让调用方看见并告诉用户。
  static void register() {
    final exe = executablePath;
    // 先确认这个路径上真的躺着一个文件再写。写出去一个不存在的 exe 路径，得到的是
    // 「菜单里有一行、点了什么都不发生」—— 比注册失败难查得多，因为它看起来是成功的。
    // 这是兜底，不是对 `resolvedExecutable` 的验证：那个数还是要到 Windows 真机上现读。
    if (!File(exe).existsSync()) {
      throw WindowsShellIntegrationException('本程序不在 $exe');
    }
    for (final target in _targets) {
      final verbKey = '$_classesRoot\\${target.subKeySuffix}';
      _withKey(verbKey, (key) {
        _setDefaultValue(key, verbLabel);
        // 不给 Icon，菜单项就是一个空白方块，和系统项摆在一起很显眼。
        _setValue(key, 'Icon', '"$exe",0');
      });
      _withKey('$verbKey\\command', (key) {
        _setDefaultValue(key, _commandLine(exe, target.argument));
      });
    }
    _registerOpenWithApplication(exe);
  }

  /// 注销。键本来就不存在不算失败（用户手工删过，或从没开过）。
  static void unregister() {
    for (final target in _targets) {
      _deleteTree('$_classesRoot\\${target.subKeySuffix}');
    }
    _deleteTree('$_classesRoot\\Applications\\${p.basename(executablePath)}');
  }

  /// 让 Rossi 进入「打开方式」候选列表。
  ///
  /// `Applications\<exe 文件名>` 是按可执行文件名索引的应用登记，写这里不会改动
  /// 任何后缀的默认程序。
  static void _registerOpenWithApplication(String exe) {
    final appKey = '$_classesRoot\\Applications\\${p.basename(exe)}';
    _withKey(appKey, (key) {
      _setValue(key, 'FriendlyAppName', 'Rossi');
      _setValue(key, 'DefaultIcon', '"$exe",0');
    });
    _withKey('$appKey\\SupportedTypes', (key) {
      for (final ext in _supportedExtensions) {
        _setValue(key, ext, '');
      }
    });
    _withKey('$appKey\\shell\\open\\command', (key) {
      _setDefaultValue(key, _commandLine(exe, '%1'));
    });
  }

  static String _commandLine(String exe, String argument) =>
      '"$exe" "$argument"';

  static void _withKey(String subKey, void Function(win32.HKEY key) body) {
    final subKeyPtr = subKey.toNativeUtf16();
    final phk = calloc<Pointer>();
    try {
      final rc = win32.RegCreateKeyEx(
        win32.HKEY_CURRENT_USER,
        win32.PCWSTR(subKeyPtr),
        null,
        win32.REG_OPTION_NON_VOLATILE,
        win32.KEY_WRITE,
        null,
        phk,
        null,
      );
      if (rc != 0) throw WindowsShellIntegrationException('打开 $subKey', rc);
      final key = win32.HKEY(phk.value);
      try {
        body(key);
      } finally {
        win32.RegCloseKey(key);
      }
    } finally {
      calloc.free(subKeyPtr);
      calloc.free(phk);
    }
  }

  /// 写一个具名 REG_SZ 值。空串是有意义的值（`SupportedTypes` 的下标项就是空值），
  /// 所以这里不把空串当"没值"。
  static void _setValue(win32.HKEY key, String name, String value) {
    final namePtr = name.toNativeUtf16();
    try {
      _setStringValue(key, namePtr, value);
    } finally {
      calloc.free(namePtr);
    }
  }

  static void _setDefaultValue(win32.HKEY key, String value) =>
      _setStringValue(key, null, value);

  static void _setStringValue(
    win32.HKEY key,
    Pointer<Utf16>? namePtr,
    String value,
  ) {
    final valuePtr = value.toNativeUtf16();
    try {
      // REG_SZ 要求带上终止符，所以长度是「码元数 + 1」再乘 2。
      final rc = win32.RegSetValueEx(
        key,
        namePtr == null ? null : win32.PCWSTR(namePtr),
        win32.REG_SZ,
        valuePtr.cast<Uint8>(),
        (value.codeUnits.length + 1) * 2,
      );
      if (rc != 0) {
        throw WindowsShellIntegrationException('写入注册表值', rc);
      }
    } finally {
      calloc.free(valuePtr);
    }
  }

  static String? _readDefaultValue(String subKey) {
    final subKeyPtr = subKey.toNativeUtf16();
    final phk = calloc<Pointer>();
    try {
      if (win32.RegOpenKeyEx(
            win32.HKEY_CURRENT_USER,
            win32.PCWSTR(subKeyPtr),
            0,
            win32.KEY_READ,
            phk,
          ) !=
          0) {
        return null;
      }
      final key = win32.HKEY(phk.value);
      try {
        return _queryDefaultValue(key);
      } finally {
        win32.RegCloseKey(key);
      }
    } finally {
      calloc.free(subKeyPtr);
      calloc.free(phk);
    }
  }

  static String? _queryDefaultValue(win32.HKEY key) {
    final cb = calloc<Uint32>();
    try {
      // 第一遍传空缓冲只问长度，第二遍按长度取。
      if (win32.RegQueryValueEx(key, null, null, null, cb) != 0) return null;
      final bytes = cb.value;
      if (bytes == 0) return null;
      final buffer = calloc<Uint8>(bytes);
      try {
        cb.value = bytes;
        if (win32.RegQueryValueEx(key, null, null, buffer, cb) != 0) {
          return null;
        }
        return buffer.cast<Utf16>().toDartString();
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(cb);
    }
  }

  static void _deleteTree(String subKey) {
    final subKeyPtr = subKey.toNativeUtf16();
    try {
      final rc = win32.RegDeleteTree(
        win32.HKEY_CURRENT_USER,
        win32.PCWSTR(subKeyPtr),
      );
      // 2 = ERROR_FILE_NOT_FOUND：本来就没有，等于删成功了。
      if (rc != 0 && rc != 2) {
        throw WindowsShellIntegrationException('删除 $subKey', rc);
      }
    } finally {
      calloc.free(subKeyPtr);
    }
  }
}

class _ShellTarget {
  const _ShellTarget({required this.subKeySuffix, required this.argument});

  /// 相对 `HKCU\Software\Classes` 的键路径。
  final String subKeySuffix;

  /// Explorer 的传参写法：`%1`（选中项）或 `%V`（目录 / 目录背景）。
  final String argument;
}

class WindowsShellIntegrationStatus {
  const WindowsShellIntegrationStatus({
    required this.registered,
    this.pointsToCurrentExecutable = true,
    this.commandLine,
    this.executablePath,
  });

  final bool registered;

  /// 已注册，但命令值指向别的 exe（换过安装目录 / 重装到别处）。
  final bool pointsToCurrentExecutable;

  final String? commandLine;
  final String? executablePath;

  bool get isOn => registered;
}

class WindowsShellIntegrationException implements Exception {
  /// [errorCode] 缺席 = 这不是 Win32 调用失败，而是我们自己拒了（比如本程序
  /// 不在它说的那个路径上）。硬塞一个 0 会读成「错误码 0 = 成功」，那是假话。
  const WindowsShellIntegrationException(this.action, [this.errorCode]);

  final String action;
  final int? errorCode;

  @override
  String toString() =>
      errorCode == null ? '$action 失败' : '$action 失败（Win32 错误码 $errorCode）';
}
