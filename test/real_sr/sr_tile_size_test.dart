import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';

/// 「分块大小」这条设置在每条超分路线上的画法。
///
/// 要防的两件事都是真发生过的：
/// 1. f5b523a8 把这条行跟「NCNN 模型下载 / 导入」捆在一起隐藏，于是 mImage ONNX
///    用户眼看着分块设置消失、值却仍在被读 —— 门禁得按「这条引擎读不读这个值」给。
/// 2. 反过来，Rossi 原生 CoreML 的分块是编译进模型的输入张量边长，运行期改不了，
///    给它一个可改的下拉等于界面上撒谎。
///
/// 两个判据都是纯函数，`hasEngineChoice` 显式传入，才能在这台机器上验证
/// Android（无引擎选择）与 Apple（CoreML）那两支。
void main() {
  const onnx = SuperResolutionEngine.mimageOnnx;
  const coreml = SuperResolutionEngine.breezeCoreML;
  const ncnn = SuperResolutionEngine.desktopNcnn;

  group('分块大小行按引擎读不读这个值来画', () {
    test('有引擎选择的平台上，只有 Rossi 原生 CoreML 不画', () {
      expect(
        RealSrSettings.tileSizeRowApplies(
          engine: coreml,
          hasEngineChoice: true,
        ),
        isFalse,
      );
      expect(
        RealSrSettings.tileSizeRowApplies(engine: onnx, hasEngineChoice: true),
        isTrue,
      );
      expect(
        RealSrSettings.tileSizeRowApplies(engine: ncnn, hasEngineChoice: true),
        isTrue,
      );
    });

    test('Android 那类没有引擎选择的平台一律画（内置 CLI 走 -t）', () {
      // 存储的引擎值在这种平台上是默认值 mimageOnnx，但它跑的是内置 CLI，
      // 0 的语义是「不分块」而不是「自动」，所以必须画、且按 CLI 那套管。
      expect(
        RealSrSettings.tileSizeRowApplies(engine: onnx, hasEngineChoice: false),
        isTrue,
      );
    });
  });

  group('分块档位与 0 的含义按路线给', () {
    test('ONNX 不给 1024（Rust 侧夹到 64..512），0 显示为「自动」', () {
      final labels = RealSrSettings.tileSizeLabelsFor(
        engine: onnx,
        hasEngineChoice: true,
      );
      expect(labels.containsKey(1024), isFalse);
      expect(labels[0], '自动');
    });

    test('NCNN 与 Android 内置 CLI 保留 1024，0 就是不分块', () {
      for (final engine in const [ncnn, onnx]) {
        final labels = RealSrSettings.tileSizeLabelsFor(
          engine: engine,
          hasEngineChoice: engine == ncnn,
        );
        expect(labels[1024], '1024');
        expect(labels[0], '0');
      }
    });
  });

  test('存储值落到本路线没有的档位时回退，不给下拉画一个非法值', () {
    expect(
      RealSrSettings.effectiveTileSize(
        engine: onnx,
        hasEngineChoice: true,
        stored: 1024,
      ),
      0,
    );
    expect(
      RealSrSettings.effectiveTileSize(
        engine: onnx,
        hasEngineChoice: true,
        stored: 256,
      ),
      256,
    );
    expect(
      RealSrSettings.effectiveTileSize(
        engine: ncnn,
        hasEngineChoice: true,
        stored: 999,
      ),
      0,
    );
  });
}
