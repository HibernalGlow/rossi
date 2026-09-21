import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/setting/real_sr/model/upscale_condition_import.dart';

void main() {
  group('parseUpscaleConditionImport', () {
    test('导入标准当前格式 JSON 数组', () {
      final jsonStr = jsonEncode([
        {
          'id': 'cond-1',
          'name': '条件一',
          'enabled': true,
          'priority': 0,
          'match': {'minWidth': 600, 'maxWidth': 1200, 'dimensionMode': 'and'},
          'action': {'skip': false, 'modelId': 'realcugan', 'scale': 2},
        },
      ]);

      final result = parseUpscaleConditionImport(jsonStr);
      expect(result.conditions.length, 1);
      final c = result.conditions.first;
      expect(c.id, 'cond-1');
      expect(c.name, '条件一');
      expect(c.match.minWidth, 600);
      expect(c.match.maxWidth, 1200);
      expect(c.action.modelId, 'realcugan');
      expect(c.action.scale, 2);
      expect(result.warnings, isEmpty);
    });

    test('导入包裹在对象中的备份格式（如 preferences.conditions）', () {
      final jsonStr = jsonEncode({
        'preferences': {
          'conditions': [
            {
              'id': 'cond-nested',
              'name': '嵌套条件',
              'match': {'maxMegapixels': 4.0},
              'action': {'skip': true},
            },
          ],
        },
      });

      final result = parseUpscaleConditionImport(jsonStr);
      expect(result.conditions.length, 1);
      expect(result.conditions.first.id, 'cond-nested');
      expect(result.conditions.first.match.maxMegapixels, 4.0);
      expect(result.conditions.first.action.skip, isTrue);
    });

    test('兼容旧版格式字段迁移（minPixels/maxPixels/regexBookPath/MODEL_*）', () {
      final jsonStr = jsonEncode([
        {
          'id': 'legacy',
          'name': '旧版条件',
          'enabled': true,
          'priority': 8,
          'match': {
            'maxPixels': 12.4,
            'dimensionMode': 'or',
            'regexBookPath': r'^/comic/',
          },
          'action': {
            'model': 'MODEL_REALESRGAN_ANIMAVIDEOV3_UP2X',
            'scale': 2,
            'noiseLevel': -1,
            'skip': false,
          },
        },
      ]);

      final result = parseUpscaleConditionImport(jsonStr);
      expect(result.conditions.length, 1);
      final c = result.conditions.first;
      expect(c.match.maxMegapixels, 12.4);
      expect(c.match.bookPathRegex, r'^/comic/');
      expect(c.match.dimensionMode, 'or');
      expect(c.action.modelId, 'realesr-animevideov3');
      expect(c.action.noise, -1);
    });

    test('非法输入抛出友好异常', () {
      expect(() => parseUpscaleConditionImport(''), throwsFormatException);
      expect(
        () => parseUpscaleConditionImport('not a json'),
        throwsFormatException,
      );
      expect(() => parseUpscaleConditionImport('[]'), throwsFormatException);
    });
  });
}
