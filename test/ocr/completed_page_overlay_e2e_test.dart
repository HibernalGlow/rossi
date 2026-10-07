/// 叠层档的**端到端**验证：真权重、真过桥、真采色，只有翻译那一跳是假的。
///
/// 与 `completed_page_e2e_test.dart` 的分工：那条走的是烘焙档（出一张 `p<N>.png`），
/// 这条走 `retainErasedBase: true` 那一支 —— 它验的是**产物形态**：
/// 图层必须落盘、烘焙 PNG 必须**不**落盘、擦字底图只在「采不到平色」时才存在、
/// 而 LaMa 那一段（实测 4.2 s/页）在 analyze 里必须真的没跑。
/// 这几条正是验收 §9c 第 1、2、3 条要在真机上数的东西，能在机器上数就不留给人。
///
/// 翻译那一跳照旧是假的：端点要网络要 key，而「条数对不对」由单测钉住。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/service/ocr/ocr_log.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_builder.dart';
import 'package:zephyr/service/ocr/translated_page_cache.dart';
import 'package:zephyr/service/ocr/translated_page_layer.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

import 'real_page_fixtures.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var ready = false;
  var reason = '';
  var page = '';
  late Directory appRoot;

  setUpAll(() async {
    appRoot = await Directory.systemTemp.createTemp('rossi_ocr_overlay_e2e_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => appRoot.path);
    final missing = await linkRealWeights();
    try {
      // 与烘焙那条同一个前置：桥接不上就直接判「没准备好」，不要让它红成「叠层坏了」。
      await RustLib.init();
    } catch (e) {
      missing.add('原生库：$e');
    }
    const pinnedPage = 'mokuro_001a.jpg';
    final found = realPages();
    final wanted = found.where((p) => p.split('/').last == pinnedPage);
    page =
        Platform.environment['ROSSI_OCR_TEST_PAGE'] ??
        (wanted.isEmpty ? '' : wanted.first);
    if (page.isEmpty) missing.add('没有 $pinnedPage');
    ready = missing.isEmpty;
    reason = ready ? '' : '缺权重或页图（${missing.join('、')}）';
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OcrSettings.saveConfig(
      const OcrTranslationConfig(
        baseUrl: 'http://127.0.0.1:11434/v1',
        model: 'fake-for-overlay-e2e',
      ),
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await OcrLog.flush();
    await appRoot.delete(recursive: true);
  });

  test('叠层档：图层落盘、不烤 PNG、LaMa 整段没跑，命中缓存后那一维还读得回来', () async {
    if (!ready) {
      markTestSkipped(reason);
      return;
    }
    final config = (await OcrSettings.loadConfig())!;
    final builder = TranslatedPageBuilder(
      translate: (texts, _) async =>
          texts.map((t) => '〔译〕$t').toList(growable: false),
    );

    final sw = Stopwatch()..start();
    final out = await builder.build(
      imagePath: page,
      pageIndex: 0,
      config: config,
      retainErasedBase: true,
      force: true,
    );
    sw.stop();
    expect(out.hasText, isTrue);
    expect(out.blockCount, greaterThan(0));

    final layerFile = await TranslatedPageCache.layerFile(
      label: out.label,
      pageIndex: 0,
    );
    final pngFile = await TranslatedPageCache.pageFile(
      label: out.label,
      pageIndex: 0,
    );
    final baseFile = await TranslatedPageCache.baseFile(
      label: out.label,
      pageIndex: 0,
    );

    // 1) 图层是这一档唯一的「字」的载体：没有它，叠层 widget 什么也画不出来。
    expect(layerFile.existsSync(), isTrue, reason: '叠层档没写图层 = 画面上没有中文');
    final layer = TranslatedPageLayer.tryDecode(
      await layerFile.readAsString(),
    );
    expect(layer, isNotNull, reason: '图层解坏了（写出去的那份自己读不回来）');
    expect(layer!.boxes.length, out.blockCount);
    expect(
      layer.boxes.where((b) => b.text.trim().isEmpty).length,
      0,
      reason: '有空译文框 —— 叠上去就是一个空气泡',
    );

    // 2) 不烤 PNG：这条判据钉的是「叠层不占增强图轨」在产物上的样子。
    //    盘上出现 p<N>.png 就意味着这一页走的是烘焙那条路，超分会为它让路。
    expect(
      pngFile.existsSync(),
      isFalse,
      reason: '叠层档不该产出成品页 PNG（那是烘焙档的产物，且要占轨）',
    );

    // 3) LaMa 那一段在 analyze 里必须真的没跑（擦字只可能走独立那一跳）。
    //    这一段是最容易「悄悄还在跑」的：省下的 4.2 s/页 就没了，而画面看起来是对的。
    expect(
      out.stageEps?.inpaint,
      isNull,
      reason: 'analyze 里 inpaint 报了 EP ⇒ 叠层这条路还在跑 LaMa，省时间的前提不成立',
    );

    // 4) 擦字底图的有无 ⇔ 构建器报出的那一维，且两侧口径要一致。
    final filled = layer.boxes.every((b) => b.fill != null);
    expect(
      filled,
      isNot(out.overlayNeedsBase),
      reason: '「每框都有填色」与「需要擦字底图」必须互斥（同一条件的两面）',
    );
    expect(
      baseFile.existsSync(),
      out.overlayNeedsBase,
      reason: filled
          ? '全填色还落了擦字底图 = 白跑一遍 LaMa 并占一份盘'
          : '说要擦字底图，盘上却没有 —— 控制器会把这一页判成能叠层而画出日文',
    );
    expect(
      await TranslatedPageCache.overlayDisplayable(
        label: out.label,
        pageIndex: 0,
      ),
      isTrue,
    );
    expect(
      await TranslatedPageCache.overlayNeedsErasedBase(
        label: out.label,
        pageIndex: 0,
      ),
      out.overlayNeedsBase,
    );

    // 5) 命中缓存那一趟：构建器什么都没算，报不出这一维，而控制器现在去现读图层。
    //    这一条量的就是「翻回来不许露出日文」在产物层成立。
    final again = await builder.build(
      imagePath: page,
      pageIndex: 0,
      config: config,
      retainErasedBase: true,
    );
    expect(again.fromCache, isTrue, reason: '第二次没命中缓存 = 每次翻回来重跑十几秒');
    expect(again.label, out.label);
    expect(
      await TranslatedPageCache.overlayNeedsErasedBase(
        label: again.label,
        pageIndex: 0,
      ),
      out.overlayNeedsBase,
      reason: '缓存命中后读回来的那一维与第一次报的不一致',
    );

    // ignore: avoid_print
    print(
      '叠层 e2e：${layer.boxes.length} 框，填色 ${layer.boxes.where((b) => b.fill != null).length} 框，'
      'needsBase=${out.overlayNeedsBase}，底图=${baseFile.existsSync() ? '擦字底图' : '原图'}，'
      'EP=${out.stageEps?.detect}/${out.stageEps?.recognize}/inpaint=${out.stageEps?.inpaint ?? '未跑'}，'
      '首跑 ${sw.elapsedMilliseconds} ms（第二次命中缓存）',
    );
    // ignore: avoid_print
    print(OcrLog.log.entries.value.map((e) => '  日志｜$e').join('\n'));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
