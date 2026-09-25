/// 译文页控制器的状态机验证（不碰 GPU、不碰权重、不碰网络）。
///
/// 这里要守的是三类后果：
/// 1. **虚报成功** —— 注入了不等于上屏了，所以「呈现器说没用增强轨」必须判失败；
/// 2. **超分把译文冲掉** —— 增强图轨一页只有一份，占用关系必须真的写进呈现器那份集合；
/// 3. **失败静默退回原图** —— 用户点了「译」结果什么都没发生，比报错更难查。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/reader/translated_page_controller.dart';
import 'package:zephyr/service/ocr/ocr_models.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_builder.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_builder.dart';
import 'package:zephyr/src/rust/api/ocr.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

const _pageW = 400, _pageH = 300;
final _box = const ui.Rect.fromLTWH(40, 30, 140, 90);

class _FakeSource implements PageSource {
  _FakeSource(this.bytes);

  final Uint8List bytes;
  int directCalls = 0;

  /// 给了就把「取原图字节」这一跳卡住，用来测「关译文关到一半换了书」。
  Completer<void>? bytesGate;

  @override
  List<PageRef> get pages => const [];

  @override
  int get pageCount => 1;

  @override
  String get path => '/fake/book';

  @override
  RasterTargetRef? rasterTargetFor(int index) => null;

  @override
  Future<PageLoadOutcome> load(
    int index, {
    int? targetWidth,
    PageLoadIntent intent = PageLoadIntent.interactive,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async {}

  /// 归档那一类：没有磁盘直路径，控制器必须自己把字节落到临时文件。
  @override
  Future<String?> getPageFilePath(int index) async {
    directCalls++;
    return null;
  }

  @override
  Future<Uint8List?> getPageBytes(int index) async {
    await bytesGate?.future;
    return bytes;
  }
}

class _FakePresenter implements TranslatedPagePresenter {
  _FakePresenter({this.confirmed});

  /// `null` = 呈现器答不上来；`false` = 注入了但画面没换。
  final bool? confirmed;

  final Map<int, String> _owned = <int, String>{};
  final List<(int, String)> injected = <(int, String)>[];
  int redraws = 0;

  @override
  Map<int, String> get translationOwnedPages => _owned;

  @override
  Future<bool> setEnhancedImage(int index, String imagePath) async {
    injected.add((index, imagePath));
    return true;
  }

  @override
  Future<bool> reshowAfterInjection(int index) async {
    redraws++;
    return true;
  }

  @override
  Future<bool?> presenterUsesEnhanced(int index) async => confirmed;
}

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

/// 稀疏文件：只占目录项，不占磁盘。用来让 `OcrModels.status()` 的体积下限过。
void _fakeWeights(Directory dir) {
  const sizes = <String, int>{
    OcrModels.detFile: 5 * 1024 * 1024,
    OcrModels.encoderFile: 343454249,
    OcrModels.decoderFile: 117480262,
    OcrModels.vocabFile: 30216,
    OcrModels.inpaintFile: 206291843,
  };
  for (final e in sizes.entries) {
    final f = File('${dir.path}/${e.key}')..createSync(recursive: true);
    final raf = f.openSync(mode: FileMode.write);
    raf.truncateSync(e.value);
    raf.closeSync();
  }
}

/// 假装产物已经生成、但那个文件其实不在（被清过目录 / 被别的进程删了）。
class _MissingProductBuilder extends TranslatedPageBuilder {
  _MissingProductBuilder(this.path);

  final String path;

  @override
  Future<TranslatedPage> build({
    required String imagePath,
    required int pageIndex,
    required OcrTranslationConfig config,
    void Function(TranslatedPageStage stage)? onStage,
    bool Function()? shouldCancel,
    bool force = false,
  }) async => TranslatedPage(
    path: path,
    fromCache: true,
    hasText: true,
    blockCount: 1,
    truncatedCount: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Uint8List page;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rossi_ocr_ctrl_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => root.path);
    page = await _whitePng(_pageW, _pageH);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await root.delete(recursive: true);
  });

  /// 权重齐 + 端点配好：控制器才允许真的往下走。
  Future<void> seedReady() async {
    _fakeWeights(Directory('${root.path}/files/manga_ocr'));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ocr_base_url', 'http://127.0.0.1:11434/v1');
    await prefs.setString('ocr_model', 'qwen2.5:14b');
  }

  TranslatedPageController controllerWith({List<OcrBlock> blocks = const []}) =>
      TranslatedPageController(
        builder: TranslatedPageBuilder(
          analyze: (imagePath, erasedPath, ep) async {
            await File(erasedPath).writeAsBytes(page, flush: true);
            return OcrPageResult(
              blocks: blocks,
              pageWidth: _pageW,
              pageHeight: _pageH,
              detectMs: BigInt.one,
              recognizeMs: BigInt.one,
              inpaintMs: BigInt.one,
              erasedPath: erasedPath,
            );
          },
          translate: (texts, config) async => List.filled(texts.length, '是蜥蜴啊'),
        ),
      );

  final blocks = [
    OcrBlock(
      quad: Float32List.fromList([
        _box.left,
        _box.top,
        _box.right,
        _box.top,
        _box.right,
        _box.bottom,
        _box.left,
        _box.bottom,
      ]),
      text: 'トカゲじゃ',
      boxes: 1,
      truncated: false,
    ),
  ];

  test('端点没配：报「去设置」，不悄悄什么都不做', () async {
    final c = controllerWith(blocks: blocks);
    final presenter = _FakePresenter();
    final ok = await c.toggle(
      source: _FakeSource(page),
      presenter: presenter,
      index: 0,
    );
    expect(ok, isFalse);
    expect(c.phase, TranslatedPagePhase.failed);
    expect(c.lastError, contains('端点'));
    expect(presenter.injected, isEmpty);
  });

  test('权重没下全：列出缺哪些，且一次注入都不做', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ocr_base_url', 'https://x/v1');
    await prefs.setString('ocr_model', 'm');

    final c = controllerWith(blocks: blocks);
    final presenter = _FakePresenter();
    final ok = await c.toggle(
      source: _FakeSource(page),
      presenter: presenter,
      index: 0,
    );
    expect(ok, isFalse);
    expect(c.lastError, contains(OcrModels.detFile));
    expect(presenter.injected, isEmpty);
  });

  test('成功：注入成品页、核对上屏、并把这一页登记给超分让路', () async {
    await seedReady();
    final c = controllerWith(blocks: blocks);
    final presenter = _FakePresenter(confirmed: true);
    final source = _FakeSource(page);

    final ok = await c.toggle(source: source, presenter: presenter, index: 4);
    expect(ok, isTrue);
    expect(c.phase, TranslatedPagePhase.showing);
    expect(presenter.injected, hasLength(1));
    expect(await File(presenter.injected.single.$2).exists(), isTrue);
    expect(presenter.redraws, 1, reason: '注入之后必须重画一次，否则画面还是原图');
    expect(presenter.translationOwnedPages.keys, {4});
    // 归属里必须带着「归的是哪张图」：翻回来时呈现器可能已经把增强图轨淘汰掉，
    // 那时要靠这个路径把同一张成品页重新注回去，而不是让芯片继续说「译文页」。
    expect(presenter.translationOwnedPages[4], endsWith('p4.png'));
    expect(c.isOwned(4), isTrue);
    expect(c.isOwned(5), isFalse);
  });

  test('呈现器说这一帧还是原图轨：判失败，不声称已显示译文', () async {
    await seedReady();
    final c = controllerWith(blocks: blocks);
    final presenter = _FakePresenter(confirmed: false);

    final ok = await c.toggle(
      source: _FakeSource(page),
      presenter: presenter,
      index: 0,
    );
    expect(ok, isFalse);
    expect(c.phase, TranslatedPagePhase.failed);
    expect(c.lastError, contains('画面没换'));
    expect(
      presenter.translationOwnedPages,
      isEmpty,
      reason: '没换上就别占着，否则超分会永久让路',
    );
  });

  test('再点一次：把原图注回去并让出这一页', () async {
    await seedReady();
    final c = controllerWith(blocks: blocks);
    final presenter = _FakePresenter(confirmed: true);
    final source = _FakeSource(page);

    await c.toggle(source: source, presenter: presenter, index: 2);
    expect(presenter.translationOwnedPages.keys, {2});

    final off = await c.toggle(source: source, presenter: presenter, index: 2);
    expect(off, isTrue);
    expect(c.phase, TranslatedPagePhase.off);
    expect(presenter.translationOwnedPages, isEmpty);
    expect(presenter.injected, hasLength(2));
    // 第二次注入的必须是**原图**（归档页 = 控制器自己落的那份临时文件）。
    final reverted = presenter.injected.last.$2;
    expect(await File(reverted).length(), page.length);
    expect(source.directCalls, 2, reason: '开一次、关一次，各问一遍有没有直路径');
  });

  test('这一页没识别到文字：如实说，不显示空白成品页', () async {
    await seedReady();
    final c = controllerWith();
    final presenter = _FakePresenter(confirmed: true);

    final ok = await c.toggle(
      source: _FakeSource(page),
      presenter: presenter,
      index: 0,
    );
    expect(ok, isFalse);
    expect(c.lastError, contains('没识别到文字'));
    expect(presenter.injected, isEmpty);
  });

  test('构建途中换书：旧产物既不注入，也不把失败顶到新页脸上', () async {
    // 一页要十几秒，这期间用户完全可能翻到另一本书。
    // 不认过期，旧书第 3 页的成品页就会被注到新书第 3 页上 —— 同一序号，不同内容。
    await seedReady();
    final gate = Completer<void>();
    final presenter = _FakePresenter(confirmed: true);
    final c = TranslatedPageController(
      builder: TranslatedPageBuilder(
        analyze: (imagePath, erasedPath, ep) async {
          await gate.future;
          await File(erasedPath).writeAsBytes(page, flush: true);
          return OcrPageResult(
            blocks: [
              OcrBlock(
                quad: Float32List.fromList([
                  _box.left,
                  _box.top,
                  _box.right,
                  _box.top,
                  _box.right,
                  _box.bottom,
                  _box.left,
                  _box.bottom,
                ]),
                text: 'トカゲじゃ',
                boxes: 1,
                truncated: false,
              ),
            ],
            pageWidth: _pageW,
            pageHeight: _pageH,
            detectMs: BigInt.one,
            recognizeMs: BigInt.one,
            inpaintMs: BigInt.one,
            erasedPath: erasedPath,
          );
        },
        translate: (texts, config) async => ['是蜥蜴啊'],
      ),
    );

    final running = c.toggle(
      source: _FakeSource(page),
      presenter: presenter,
      index: 3,
    );
    // 进到 building 之前还有几次 await（读配置、查权重），逐帧让路。
    for (var i = 0; i < 20 && c.phase != TranslatedPagePhase.building; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      c.phase,
      TranslatedPagePhase.building,
      reason: '没进入生成中就说明这条测的不是在飞构建',
    );

    c.reset(); // 换书
    gate.complete();
    expect(await running, isFalse);
    expect(presenter.injected, isEmpty, reason: '过期产物不许注到新书上');
    expect(presenter.translationOwnedPages, isEmpty);
    expect(c.phase, TranslatedPagePhase.off, reason: '旧构建的收尾不许把新页脸改成 failed');
    expect(c.lastError, isEmpty);
  });

  test('关译文关到一半换书：旧书的原图也不许注到新书上', () async {
    await seedReady();
    final presenter = _FakePresenter(confirmed: true);
    final source = _FakeSource(page);
    final c = controllerWith(blocks: blocks);

    await c.toggle(source: source, presenter: presenter, index: 2);
    expect(presenter.injected, hasLength(1));

    source.bytesGate = Completer<void>();
    final turningOff = c.toggle(source: source, presenter: presenter, index: 2);
    for (var i = 0; i < 20 && presenter.injected.length != 1; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    c.reset(); // 换书
    source.bytesGate!.complete();

    expect(await turningOff, isFalse);
    expect(presenter.injected, hasLength(1), reason: '第二次注入属于旧书，必须作废');
  });

  test('产物在注入前消失：静默回落原图，不弹错', () async {
    // ADR-0018 §决定 3：「Reader 在产物缺失/损坏时静默回落到原图而不是报错」。
    await seedReady();
    final presenter = _FakePresenter(confirmed: true);
    final c = TranslatedPageController(
      builder: _MissingProductBuilder('/tmp/rossi_gone/p0.png'),
    );

    expect(
      await c.toggle(source: _FakeSource(page), presenter: presenter, index: 1),
      isFalse,
    );
    expect(c.phase, TranslatedPagePhase.off, reason: '缺产物不该显示成失败态');
    expect(c.lastError, isEmpty, reason: '静默回落 = 不弹一条用户无法行动的错');
    expect(presenter.injected, isEmpty);
    expect(presenter.translationOwnedPages, isEmpty);
  });

  test('换书 reset：清掉归属，否则新书那几页会被旧译文占着', () async {
    await seedReady();
    final c = controllerWith(blocks: blocks);
    final presenter = _FakePresenter(confirmed: true);
    await c.toggle(source: _FakeSource(page), presenter: presenter, index: 1);
    expect(presenter.translationOwnedPages.keys, {1});

    c.reset();
    expect(presenter.translationOwnedPages, isEmpty);
    expect(c.phase, TranslatedPagePhase.off);
  });
}
