import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/src/rust/frb_generated.dart';

Future<void> initRustLib({bool silent = false}) async {
  try {
    // flutter run 的工作目录是仓库根目录。优先加载本次构建打包的库，
    // 避免 FRB 的开发目录回退误载 rust/target/release 中的旧 ABI。
    ExternalLibrary? library;
    if (Platform.isMacOS) {
      final bundled = p.normalize(
        p.join(
          p.dirname(Platform.resolvedExecutable),
          '../Frameworks/windcore.framework/windcore',
        ),
      );
      if (File(bundled).existsSync()) library = ExternalLibrary.open(bundled);
    }
    await RustLib.init(externalLibrary: library);
  } catch (_) {
    if (!silent) rethrow;
  }
}
