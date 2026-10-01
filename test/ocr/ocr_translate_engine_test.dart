/// 翻译**引擎**这一档的验证：枚举、缓存指纹、端侧后端的错误形状、以及编排层有没有走对门。
///
/// 为什么单独立一个文件：这一档的全部风险都在「切了引擎却看不出切了」——
/// 端点按 token 花钱、端侧免费离线，用户为了省钱切过去，如果缓存指纹里没有引擎，
/// 他会看到**旧引擎翻的那张页**继续躺在那儿，而且界面上一切正常。
/// 那是本 ADR 一路在防的静默陈旧，不是「少个刷新按钮」那种小毛病。
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/service/ocr/ocr_log.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/service/ocr/ocr_translate_engine.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_builder.dart';
import 'package:zephyr/service/ocr/translated_page_cache.dart';
import 'package:zephyr/src/rust/api/ocr.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

Future<Uint8List> _whitePng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

OcrBlock _block() => OcrBlock(
  quad: Float32List.fromList([40, 30, 180, 30, 180, 120, 40, 120]),
  text: 'かえして〜',
  boxes: 1,
  truncated: false,
);

class _FakeAnalyze {
  int calls = 0;

  Future<OcrPageResult> call(
    String imagePath,
    String erasedPath,
    String ep,
  ) async {
    calls++;
    await File(erasedPath).writeAsBytes(await _whitePng(400, 300), flush: true);
    return OcrPageResult(
      blocks: [_block()],
      pageWidth: 400,
      pageHeight: 300,
      detectMs: BigInt.from(190),
      recognizeMs: BigInt.from(3700),
      inpaintMs: BigInt.from(1700),
      erasedPath: erasedPath,
      stageEps: const OcrStageEps(
        detect: 'cpu',
        recognize: 'cpu',
        inpaint: 'cpu',
      ),
    );
  }
}

const _endpoint = OcrTranslationConfig(
  baseUrl: 'https://api.example.com/v1',
  model: 'some-model',
  targetLanguage: 'zh-Hans',
  glossary: '危機契約=危机契约',
);

const _apple = OcrTranslationConfig(
  baseUrl: '',
  model: '',
  targetLanguage: 'zh-Hans',
  glossary: '危機契約=危机契约',
  engine: OcrTranslateEngine.appleOnDevice,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('rossi_ocr_engine_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => root.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppleTranslateBackend.channel, null);
    await OcrLog.flush();
    await root.delete(recursive: true);
  });

  Future<({String fingerprint, String label})> fp(OcrTranslationConfig c) =>
      TranslatedPageCache.describe(config: c, modelTag: 'fixed');

  group('缓存指纹里的引擎维度', () {
    test('同配置两次算出来必须一样（否则下面几条都是噪声）', () async {
      final a = await fp(_endpoint);
      final b = await fp(_endpoint);
      expect(a.fingerprint, b.fingerprint);
      expect(a.label, b.label);
    });

    test('换引擎必须让指纹与目录都变', () async {
      final a = await fp(_endpoint);
      final b = await fp(_apple);
      expect(
        a.fingerprint,
        isNot(b.fingerprint),
        reason: '指纹里没有引擎 = 切了引擎还端旧译文，而且没人知道',
      );
      expect(a.label, isNot(b.label), reason: '标签相同会直接撞进同一个缓存目录');
      expect(b.fingerprint, contains('engine=apple'));
    });

    test('端点档改术语表要失效；端侧档改术语表**不该**失效', () async {
      final epA = await fp(_endpoint);
      final epB = await fp(_endpoint.copyWith(glossary: '危機契約=危机合同'));
      expect(epA.fingerprint, isNot(epB.fingerprint));

      final apA = await fp(_apple);
      final apB = await fp(_apple.copyWith(glossary: '完全不同的一份'));
      expect(
        apA.fingerprint,
        apB.fingerprint,
        reason: '端侧没有术语表接口，让它去失效一份「本来就没用术语表」的产物是多算',
      );
    });

    test('端侧档的目录名不留空段', () async {
      final b = await fp(_apple);
      expect(b.label, startsWith('zh-Hans_apple_'));
    });
  });

  group('引擎枚举与设置', () {
    test('未知 id 回落到端点，不抛', () {
      expect(OcrTranslateEngine.fromId('没有这个东西'), OcrTranslateEngine.endpoint);
      expect(OcrTranslateEngine.fromId(null), OcrTranslateEngine.endpoint);
      expect(
        OcrTranslateEngine.fromId('apple'),
        OcrTranslateEngine.appleOnDevice,
      );
    });

    test('端点档没填 baseUrl 就是「未配置」；端侧档不是', () async {
      await OcrSettings.saveConfig(_endpoint.copyWith(baseUrl: '', model: ''));
      expect(await OcrSettings.loadConfig(), isNull);

      await OcrSettings.saveConfig(_apple);
      final cfg = await OcrSettings.loadConfig();
      expect(cfg, isNotNull, reason: '拿端点的要求去问端侧，用户会被一句「先填端点」挡在门外');
      expect(cfg!.engine, OcrTranslateEngine.appleOnDevice);
    });

    test('引擎随配置往返（存进去就要读得回来）', () async {
      await OcrSettings.saveConfig(_apple);
      expect(await OcrSettings.loadEngine(), OcrTranslateEngine.appleOnDevice);
      expect(
        (await OcrSettings.loadDraft()).engine,
        OcrTranslateEngine.appleOnDevice,
      );
      await OcrSettings.saveConfig(_endpoint);
      expect(await OcrSettings.loadEngine(), OcrTranslateEngine.endpoint);
    });

    test('toJson 带引擎、不带 key', () {
      final j = _apple.copyWith(apiKey: 'sk-secret').toJson();
      expect(j['engine'], 'apple');
      expect(j.values.map((v) => '$v'), isNot(contains('sk-secret')));
    });
  });

  group('端侧后端（mock 桥）', () {
    void mockChannel(Future<Object?> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppleTranslateBackend.channel, handler);
    }

    test('status 把系统状态原样带回来', () async {
      mockChannel(
        (call) async =>
            call.method == 'status' ? {'status': 'installed'} : null,
      );
      expect(await AppleTranslateBackend.status(), 'installed');
    });

    test('桥不存在时 status 回 unavailable，而不是抛', () async {
      // 不设 mock：真机上是 MissingPluginException / Windows 上是这条码路根本不存在。
      final s = await AppleTranslateBackend.status();
      expect(
        s,
        anyOf('unavailable', 'unsupported', 'supported', 'installed'),
        reason: '只要求「不抛」—— 设置页每次 build 都要问它',
      );
    });

    test('条数不符必须抛（按块下标回填，错位就是整页串行）', () async {
      mockChannel((call) async {
        if (call.method == 'translate')
          return {
            'texts': ['只有一条'],
          };
        return null;
      });
      await expectLater(
        AppleTranslateBackend.translate(
          texts: const ['a', 'b', 'c'],
          target: 'zh-Hans',
        ),
        throwsA(isA<PlatformException>()),
      );
    });

    test('任何桥侧失败都要塌成 OcrTranslationException（编排层只认这一种来决定降级）', () async {
      mockChannel((call) async {
        if (call.method == 'translate') {
          throw PlatformException(code: 'translate', message: '没装语言包');
        }
        return null;
      });
      await expectLater(
        AppleTranslateBackend.translateBlocks(
          texts: const ['かえして〜'],
          config: _apple,
        ),
        throwsA(
          isA<OcrTranslationException>().having(
            (e) => e.message,
            'message',
            contains('Apple 系统翻译不可用'),
          ),
        ),
      );
    });
  });

  test('编排层按引擎分流：端侧档取的是桥的译文，不是端点的', () async {
    var channelCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppleTranslateBackend.channel, (call) async {
          if (call.method == 'translate') {
            channelCalls++;
            final texts = (call.arguments as Map)['texts'] as List;
            return {'texts': List.generate(texts.length, (_) => '还给我！')};
          }
          return {'status': 'installed'};
        });

    final analyze = _FakeAnalyze();
    // 不注入 translate：这条测的就是**默认的**分流代码，注入等于把被测对象换掉。
    final out = await TranslatedPageBuilder(
      analyze: analyze.call,
    ).build(imagePath: '/nonexistent/page.jpg', pageIndex: 0, config: _apple);

    expect(channelCalls, 1, reason: '端侧档没走桥 = 引擎选择器是个骗人的控件');
    expect(analyze.calls, 1);
    expect(out.hasText, isTrue);
    expect(out.path, isNotEmpty);
  });
}
