import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:zephyr/service/app_identity/data_migration.dart';

/// Windows 继续随程序便携存储，但给 Rossi 单独的数据根，避免解压到同一目录时共库。
Future<String> applicationDataRoot() async {
  if (Platform.isWindows) {
    return p.normalize(
      p.join(p.dirname(Platform.resolvedExecutable), '..', appIdentity),
    );
  }
  if (Platform.isLinux) {
    // 不采用 path_provider 的 executable-name 历史回退，避免重新落回 Breeze。
    final home = Platform.environment['HOME']!;
    final xdg = Platform.environment['XDG_DATA_HOME'];
    return p.join(
      xdg == null || xdg.isEmpty ? p.join(home, '.local', 'share') : xdg,
      appIdentity,
    );
  }
  final support = await getApplicationSupportDirectory();
  return Platform.isAndroid
      ? p.normalize(p.join(support.path, '..'))
      : support.path;
}

List<LegacyAppData> legacyDesktopData({
  required String target,
  required String operatingSystem,
  required Map<String, String> environment,
  String? legacyWindowsSupport,
}) {
  if (operatingSystem == 'windows') {
    final installRoot = p.dirname(target);
    final extra = <String, String>{
      if (legacyWindowsSupport != null)
        'zephyr': p.join(legacyWindowsSupport, 'zephyr'),
      if (legacyWindowsSupport != null)
        'shared_preferences.json': p.join(
          legacyWindowsSupport,
          'shared_preferences.json',
        ),
    };
    return [
      LegacyAppData(installRoot, extraEntries: extra),
      LegacyAppData(
        p.join(p.dirname(installRoot), 'breeze'),
        extraEntries: extra,
      ),
    ];
  }
  if (operatingSystem == 'macos') {
    return [LegacyAppData(p.join(p.dirname(target), legacyAppIdentity))];
  }
  if (operatingSystem == 'linux') {
    final home = environment['HOME']!;
    final data = environment['XDG_DATA_HOME'];
    final base = data == null || data.isEmpty
        ? p.join(home, '.local', 'share')
        : data;
    return [
      for (final name in [
        'io.github.windy.breeze',
        legacyAppIdentity,
        'breeze',
        'zephyr',
      ])
        LegacyAppData(p.join(base, name)),
      // Flatpak 的宿主旧目录若当前沙盒无权访问，走原有备份导入，不扩大沙盒权限。
      for (final name in [
        'io.github.windy.breeze',
        legacyAppIdentity,
        'breeze',
        'zephyr',
      ])
        LegacyAppData(
          p.join(home, '.var', 'app', 'io.github.windy.breeze', 'data', name),
        ),
    ];
  }
  return const [];
}
