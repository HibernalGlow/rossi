import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/network/http/wind_http.dart';
import 'package:zephyr/page/setting/real_sr/service/image_denoise_model.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

/// 显式启用的真实下载检查：走应用 WindHttp/Rust 流式传输，不安装或替换用户模型。
/// flutter test --dart-define=RUN_DENOISE_DOWNLOAD_SMOKE=true <本文件>
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'denoise weights download through the production Rust client and pass SHA-256',
    () async {
      await RustLib.init();
      final directory = Directory.systemTemp.createTempSync(
        'denoise-download-',
      );
      try {
        final output = File('${directory.path}/model.onnx');
        await WindHttp(
          // 该冒烟只验证直连传输，避免测试宿主的代理环境干扰。
          noProxy: true,
          receiveTimeout: const Duration(seconds: 60),
          headers: {'User-Agent': 'Breeze', 'Accept-Encoding': 'identity'},
        ).download(ImageDenoiseModel.url, output.path);
        expect(await output.length(), ImageDenoiseModel.expectedBytes);
        expect(
          (await sha256.bind(output.openRead()).first).toString(),
          ImageDenoiseModel.digest,
        );
        expect(File('${output.path}.part').existsSync(), isFalse);
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('RUN_DENOISE_DOWNLOAD_SMOKE'),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
