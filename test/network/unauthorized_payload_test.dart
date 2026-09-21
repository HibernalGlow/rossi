import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/network/http/plugin/unauthorized_payload.dart';

/// 载荷由插件 JS 抛出、跨 FRB（Rust `anyhow`）回来，
/// 所以真实样例里它总在 [AnyhowException.message] 里。
String _payloadJson({
  String type = 'unauthorized',
  String? source,
  String? message,
  String? scheme,
  String? data,
}) {
  final parts = <String>['"type":"$type"'];
  if (source != null) parts.add('"source":"$source"');
  if (message != null) parts.add('"message":"$message"');
  if (scheme != null) parts.add('"scheme":$scheme');
  if (data != null) parts.add('"data":$data');
  return '{${parts.join(',')}}';
}

void main() {
  group('parseUnauthorizedPayload 不会被非 AnyhowException 噎住', () {
    // 回归：Screenshot 里的
    // 「type 'StateError' is not a subtype of type 'AnyhowException' in type cast」
    // 就是这个硬转造成的 —— 它在调用方的 catch 里抛出，把真实错误顶替掉了。
    final nonFrbErrors = <String, Object>{
      'StateError': StateError('plugin_not_found:bika'),
      'FormatException': const FormatException('插件返回格式错误: String'),
      'Exception': Exception('取消 QJS 任务组失败'),
      'ArgumentError': ArgumentError('fnPath 不能为空'),
    };

    nonFrbErrors.forEach((name, error) {
      test('$name → 返回 null 且不抛异常', () {
        expect(
          () => parseUnauthorizedPayload(error, fallbackPluginId: 'bika'),
          returnsNormally,
          reason: '嗅探函数没资格把真实错误改写成 TypeError',
        );
        expect(
          parseUnauthorizedPayload(error, fallbackPluginId: 'bika'),
          isNull,
        );
      });
    });

    test('错误文本里带 JSON 也不该被非 AnyhowException 误判成 unauthorized', () {
      final error = StateError(_payloadJson(source: 'bika'));
      expect(
        parseUnauthorizedPayload(error, fallbackPluginId: 'bika'),
        isNull,
        reason: '否则会给用户弹一个假的「登录过期，请重新登录」',
      );
    });
  });

  group('parseUnauthorizedPayload 正常路径', () {
    test('裸 JSON 载荷', () {
      final result = parseUnauthorizedPayload(
        AnyhowException(
          _payloadJson(
            source: 'bika',
            message: '登录已过期',
            scheme: '{"login":"bika://login"}',
            data: '{"reason":"401"}',
          ),
        ),
        fallbackPluginId: 'fallback',
      );

      expect(result, isNotNull);
      expect(result!.pluginId, 'bika');
      expect(result.message, '登录已过期');
      expect(result.scheme?['login'], 'bika://login');
      expect(result.data?['reason'], '401');
    });

    test('bundle:…cjs] 前缀的载荷能被正则抠出来', () {
      final result = parseUnauthorizedPayload(
        AnyhowException(
          'Error: bundle:app://bika/main.cjs] '
          '${_payloadJson(source: 'bika', message: '登录已过期')}',
        ),
        fallbackPluginId: 'fallback',
      );

      expect(result, isNotNull);
      expect(result!.pluginId, 'bika');
      expect(result.message, '登录已过期');
    });

    test('只取错误文本的首行参与匹配', () {
      final result = parseUnauthorizedPayload(
        AnyhowException(
          '${_payloadJson(source: 'bika', message: '登录已过期')}\n'
          '    at <anonymous> (bundle:app://bika/main.cjs:1:1)',
        ),
        fallbackPluginId: 'fallback',
      );

      expect(result, isNotNull);
      expect(result!.message, '登录已过期');
    });

    test('缺少 source 时回退到 fallbackPluginId，缺少 message 时给默认文案', () {
      final result = parseUnauthorizedPayload(
        AnyhowException(_payloadJson()),
        fallbackPluginId: 'fallback-plugin',
      );

      expect(result, isNotNull);
      expect(result!.pluginId, 'fallback-plugin');
      expect(result.message, '登录过期，请重新登录');
    });

    test('type 不是 unauthorized 时返回 null', () {
      expect(
        parseUnauthorizedPayload(
          AnyhowException(_payloadJson(type: 'error', source: 'bika')),
          fallbackPluginId: 'bika',
        ),
        isNull,
      );
    });

    test('错误文本不是 JSON 时返回 null', () {
      expect(
        parseUnauthorizedPayload(
          AnyhowException('network unreachable'),
          fallbackPluginId: 'bika',
        ),
        isNull,
      );
    });

    test('空 message 时返回 null，不崩', () {
      expect(
        parseUnauthorizedPayload(AnyhowException(''), fallbackPluginId: 'bika'),
        isNull,
      );
    });
  });
}
