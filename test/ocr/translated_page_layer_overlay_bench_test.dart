/// 叠层**渲染台**：真页 + 真 OCR，把译文层分别画到「没擦字的原图」与「擦字底图」上，
/// 出图给人看，并把「字压字」量成一个数。
///
/// # 为什么现在只能出图，看不到阅读器里的变化
///
/// 叠层的显示侧还没接进阅读器 —— 那要改 `read_image_widget.dart`（本地 GPU 路那个
/// Stack）和在线那条轨，两处都压在别的会话手里。所以这一条只把「图层 → 画面」这段
/// 单独跑通：**同一份 `TranslatedPageLayer`**，两种底图、两个倍率。
///
/// # 这条验什么
///
/// 1. **位置与烘焙同轨**：同一份图层数据，走 `paintLayer` 与走成品页烘焙，落字像素
///    必须完全一致 —— 两条路共用同一个排版计划，不许各写一套字号策略
///    （ADR-0018 §决定 3 当初否决 overlay-first 的理由就是「做两遍」）。
/// 2. **倍率不漂也不糊**：2× 时墨量按面积走，锐度与 1× 同档。
/// 3. **字压字率**：文字层自己那批墨像素里，有多大比例落在「底图本来就有墨」上。
///    原图底 vs 擦字底 两个数一起报 —— 差值就是「擦字到底帮了多少」，
///    也是「叠层这一档该不该默认还擦字」的依据。
///
/// # 关于译文内容
///
/// 这里**不接真翻译**：译文用确定的占位中文。质量那一头由端点与
/// `parseTranslatedLines` 的单测管（真端点验收见 `ocr-completed-page-acceptance.md`
/// 第 5 条）；这一条判的是「中文放进日文气泡的位置，以及它压在原文上没有」。
/// 接真译文只会把端点抖动一起量进来。
///
/// # 关于 2× 的底图
///
/// 用双线性拉伸而不是真超分：被测的是**文字层**在任意倍率下的位置与锐度，底图是
/// 拉伸来的还是模型跑出来的与它无关（两者都是等比、不改内容），而真超分要先下几百 MB。
///
/// 跑法（缺真权重/真页时**显式 skip 并说明缺什么**）：
///   flutter test test/ocr/translated_page_layer_overlay_bench_test.dart --timeout 600s
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/service/ocr/ocr_service.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/service/ocr/translated_page_layer.dart';
import 'package:zephyr/service/ocr/translated_page_renderer.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

import 'real_page_fixtures.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');
const _pinnedPage = 'mokuro_001a.jpg';

/// 近黑算「有墨」。与原图/擦字底图同一条阈值，两边才可比。
Set<int> _darkPixels(
  Uint8List rgba,
  int stride,
  Iterable<ui.Rect> boxes, {
  int step = 1,
}) {
  final out = <int>{};
  for (final r in boxes) {
    for (var y = r.top ~/ step; y < r.bottom ~/ step; y++) {
      for (var x = r.left ~/ step; x < r.right ~/ step; x++) {
        final i = (y * step * stride + x * step) * 4;
        if (i + 2 >= rgba.length) continue;
        if (rgba[i] < 64 && rgba[i + 1] < 64 && rgba[i + 2] < 64) {
          out.add(y * stride + x);
        }
      }
    }
  }
  return out;
}

/// 「文字层那批墨里有多少落在底图已有的墨上」。空文字层返回 0，不假装完美。
double _collisionRate(Set<int> textInk, Set<int> baseInk) =>
    textInk.isEmpty ? 0 : textInk.intersection(baseInk).length / textInk.length;

/// 锐度：近黑墨 vs 被抗锯齿摊开的中间灰。比值越高越锐。
({int ink, int mid, double ratio}) _sharpness(
  Uint8List rgba,
  int stride,
  Iterable<ui.Rect> boxes, {
  int step = 1,
}) {
  var ink = 0, mid = 0;
  ink = _darkPixels(rgba, stride, boxes, step: step).length;
  for (final r in boxes) {
    for (var y = r.top ~/ step; y < r.bottom ~/ step; y++) {
      for (var x = r.left ~/ step; x < r.right ~/ step; x++) {
        final v = rgba[(y * step * stride + x * step) * 4];
        if (v >= 64 && v <= 192) mid++;
      }
    }
  }
  return (ink: ink, mid: mid, ratio: ink == 0 ? 0 : ink / (ink + mid));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var ready = false;
  var reason = '';
  var pagePath = '';
  late Directory appRoot;
  late Directory outDir;

  setUpAll(() async {
    appRoot = await Directory.systemTemp.createTemp('rossi_overlay_bench_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => appRoot.path);
    final missing = <String>[];
    missing.addAll(await linkRealWeights());
    try {
      await RustLib.init();
    } catch (e) {
      missing.add('原生库：$e');
    }
    final found = realPages().where((x) => p.basename(x) == _pinnedPage);
    pagePath = found.isEmpty ? '' : found.first;
    if (pagePath.isEmpty) missing.add('没有 $_pinnedPage');
    // 出图落点：仓库内 .local（已 gitignore），**不放 $TMPDIR** ——
    // macOS 的 dirhelper 每天 03:35 扫一次，跑完想看第二眼就没了。
    outDir = Directory(
      Platform.environment['ROSSI_OVERLAY_BENCH_DIR'] ??
          '${Directory.current.path}/.local/overlay-bench',
    )..createSync(recursive: true);
    ready = missing.isEmpty;
    reason = missing.isEmpty ? '' : '缺：${missing.join('、')}';
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    if (ready) {
      // ignore: avoid_print
      print('叠层渲染台出图目录：${outDir.path}');
    }
  });

  Future<ui.Image> load(String path) async {
    final codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
    );
    return (await codec.getNextFrame()).image;
  }

  Future<Uint8List> rgba(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<void> savePng(ui.Image image, String name) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(p.join(outDir.path, name)).writeAsBytes(
      data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }

  test('真页图层：叠原图与叠擦字底同一条排版计划，倍率不漂不糊，字压字量得出来', () async {
    if (!ready) {
      markTestSkipped('渲染台没跑（$reason）—— 这条不是通过，是没执行');
      return;
    }
    await TranslatedPageRenderer.ensureFontLoaded();
    final erased = p.join(appRoot.path, 'erased.png');
    final result = await OcrService.instance.analyzePage(
      imagePath: pagePath,
      inpaint: true,
      erasedOutput: erased,
      ep: await OcrSettings.loadEp(),
    );
    expect(result.blocks.length, greaterThan(2), reason: '这页没认出几块，比不了');
    final boxes = result.blocks
        .map((b) => TranslatedPageLayer.rectForQuad(b.quad))
        .toList(growable: false);

    TranslatedBox boxAt(int i) => TranslatedBox(
      quad: result.blocks[i].quad.map((v) => v.toDouble()).toList(),
      source: result.blocks[i].text,
      text: '〔译〕${(() {
        final t = result.blocks[i].text.trim();
        return t.length <= 5 ? t : t.substring(0, 5);
      })()}了吗',
      truncated: result.blocks[i].truncated,
    );
    final layer = TranslatedPageLayer(
      pageWidth: result.pageWidth,
      pageHeight: result.pageHeight,
      boxes: [for (var i = 0; i < result.blocks.length; i++) boxAt(i)],
    );
    // 画的是**将来显示侧要读的那份文件**，不是内存里的对象：先编再解回来。
    final decoded = TranslatedPageLayer.tryDecode(layer.encode());
    expect(decoded, isNotNull, reason: '图层 JSON 自己解不回来');

    Future<ui.Image> compose(ui.Image base, TranslatedPageLayer l, double s) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.scale(s);
      canvas.drawImage(base, ui.Offset.zero, ui.Paint());
      TranslatedPageRenderer.paintLayer(canvas, l);
      canvas.restore();
      return recorder.endRecording().toImage(
        (base.width * s).round(),
        (base.height * s).round(),
      );
    }

    final original = await load(pagePath);
    final erasedBase = await load(erased);
    final overlay1 = await compose(original, decoded!, 1);
    final overlay2 = await compose(original, decoded, 2);
    await savePng(overlay1, 'overlay_on_original_1x.png');
    await savePng(overlay2, 'overlay_on_original_2x.png');

    // ① 位置同轨：同一个擦字底、同一份数据，**两个绘制入口**画出来的落字像素必须
    //    一模一样 —— 一边是成品页烘焙那条（`render`，它自己算 AABB 与字号），
    //    一边是叠层这条（`paintLayer`，吃图层数据）。将来叠层接上显示之后，
    //    这一条就是「两条路没有各写一套排版计划」的证据。
    final stride = erasedBase.width;
    final texts = [for (final b in decoded.boxes) b.text];
    final bakedPng = await TranslatedPageRenderer.render(
      erasedPng: await File(erased).readAsBytes(),
      blocks: result.blocks,
      translations: texts,
    );
    final bakedImage = await _decodePng(bakedPng);
    final bakedRgba = await rgba(bakedImage);
    final overlayErased = await compose(erasedBase, decoded, 1);
    final overlayErasedRgba = await rgba(overlayErased);
    expect(
      _darkPixels(overlayErasedRgba, stride, boxes),
      equals(_darkPixels(bakedRgba, stride, boxes)),
      reason: '叠层与烘焙的落字位置分叉了 —— 两条路必须共用同一个排版计划',
    );
    await savePng(bakedImage, 'erased_base_via_render.png');
    await savePng(overlayErased, 'erased_base_via_paintLayer.png');

    // ② 倍率：墨量按面积走（抗锯齿栅格不可能精确 ×4，给 2–8 倍区间），锐度不掉档。
    //    两边都按**各自图像的像素网格**全采样，框在 2× 那张上跟着放大两倍。
    //    （早先这里用 step=2 在 2× 图上按原图坐标数格子 —— 那格子只有 1/4 密，
    //    墨点数天然掉四倍，于是断言量的是采样步长而不是渲染。）
    final o1 = await rgba(overlay1);
    final o2 = await rgba(overlay2);
    final s1 = _sharpness(o1, original.width, boxes);
    final boxes2x = [
      for (final r in boxes)
        ui.Rect.fromLTRB(r.left * 2, r.top * 2, r.right * 2, r.bottom * 2),
    ];
    final s2 = _sharpness(o2, original.width * 2, boxes2x);
    expect(s1.ink, greaterThan(300), reason: '1× 就没画出多少字，尺子无效');
    expect(
      s2.ink,
      inInclusiveRange(s1.ink * 2, s1.ink * 8),
      reason: '2× 墨量没按面积走：${s1.ink} → ${s2.ink}',
    );
    expect(
      s2.ratio,
      greaterThan(s1.ratio * 0.85),
      reason: '2× 失锐：${s1.ratio.toStringAsFixed(3)} → ${s2.ratio.toStringAsFixed(3)}',
    );

    // ③ 字压字率：先拿到「文字层自己」那批墨 —— 把同一份层画到纯白底上就是它，
    //    这样统计里不掺底图原有的字，两边（原图底 / 擦字底）比的才是同一批像素。
    final white = await _solidWhite(original.width, original.height);
    final textOnly = await compose(white, decoded, 1);
    final textInk = _darkPixels(await rgba(textOnly), original.width, boxes);
    expect(
      textInk,
      isNotEmpty,
      reason: '文字层在纯白底上一个墨点都没有 —— 那下面两个数都是 0，是假绿',
    );
    final rateOnOriginal = _collisionRate(
      textInk,
      _darkPixels(await rgba(original), original.width, boxes),
    );
    final rateOnErased = _collisionRate(
      textInk,
      // 底图是 **LaMa 交出来的那张擦字底**，不是 `render()` 的输出 —— 后者已经把
      // 字画上去了，拿它当「底图原有的墨」会得到一个假真的 1.000（第一版就红在这里）。
      _darkPixels(await rgba(erasedBase), stride, boxes),
    );
    // 尺子先自证两端：完全重叠必须读成 1，完全不相交必须读成 0。
    // 少了这两句，`_collisionRate` 写坏了（比如永远返回 0）也能让下面那条比较全绿。
    expect(
      _collisionRate(textInk, textInk),
      1.0,
      reason: '完全重叠读不出 1 —— 这把尺子看不见重叠',
    );
    expect(
      _collisionRate(
        textInk,
        {for (final px in textInk) px + stride * original.height * 4},
      ),
      0.0,
      reason: '毫不相交的两批像素读不出 0 —— 分子分母写反了',
    );
    expect(
      rateOnOriginal,
      greaterThan(rateOnErased),
      reason: '不擦字那底的字压字率(${rateOnOriginal.toStringAsFixed(3)}) 没有高于'
          '擦字底(${rateOnErased.toStringAsFixed(3)}) —— 要么擦字白擦，'
          '要么这把尺子看不见重叠',
    );
    // ignore: avoid_print
    print(
      '叠层渲染台：${result.pageWidth}x${result.pageHeight}，${boxes.length} 框；'
      '字压字率 原图底=${rateOnOriginal.toStringAsFixed(3)} '
      '擦字底=${rateOnErased.toStringAsFixed(3)}；'
      '锐度 1x=${s1.ratio.toStringAsFixed(3)} 2x=${s2.ratio.toStringAsFixed(3)}；'
      '文字层墨 ${textInk.length} px',
    );

    for (final i in [
      original,
      erasedBase,
      overlay1,
      overlay2,
      bakedImage,
      overlayErased,
      white,
      textOnly,
    ]) {
      i.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Future<ui.Image> _decodePng(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  return (await codec.getNextFrame()).image;
}

Future<ui.Image> _solidWhite(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(w, h);
}
