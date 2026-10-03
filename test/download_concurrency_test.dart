import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/download/image_download.dart';

void main() {
  group('图片并发取值', () {
    test('插件没表态时按用户的数字走', () {
      expect(
        resolveEffectiveImageConcurrency(pluginLimit: null, userTarget: 12),
        12,
      );
    });

    test('插件声明了上限就把它当天花板', () {
      expect(
        resolveEffectiveImageConcurrency(pluginLimit: 2, userTarget: 16),
        2,
      );
      expect(
        resolveEffectiveImageConcurrency(pluginLimit: 32, userTarget: 4),
        4,
      );
    });

    test('两边都越界时钳回 1..kMaxImageConcurrency', () {
      expect(
        resolveEffectiveImageConcurrency(pluginLimit: 99, userTarget: 0),
        1,
      );
      expect(
        resolveEffectiveImageConcurrency(
          pluginLimit: null,
          userTarget: kMaxImageConcurrency + 50,
        ),
        kMaxImageConcurrency,
      );
    });
  });
}
