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

import 'package:zephyr/service/ocr/ocr_log.dart';
import 'package:zephyr/reader/page_display_source.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/reader/translated_page_controller.dart';
import 'package:zephyr/service/ocr/ocr_models.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_builder.dart';
import 'package:zephyr/service/ocr/translated_page_cache.dart';
import 'package:zephyr/service/ocr/translated_page_display_mode.dart';
import 'package:zephyr/service/ocr/translated_page_layer.dart';
import 'package:zephyr/src/rust/api/ocr.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

const _pageW = 400, _pageH = 300;
final _box = const ui.Rect.fromLTWH(40, 30, 140, 90);

/// 假的「三段实际生效」：取本机（Apple）上 `auto` 的真实落点。
const _fakeStageEps = OcrStageEps(
  detect: 'cpu',
  recognize: 'cpu',
  inpaint: 'cpu',
);

class _FakeSource implements PageSource {
  _FakeSource(this.bytes);

  final Uint8List bytes;
  int directCalls = 0;

  /// 给了就把「问有没有磁盘直路径」这一跳卡住，用来测「关译文关到一半换了书」。
  ///
  /// 卡点必须落在 `getPageFilePath` 而不是 `getPageBytes`：开译文时那页的原图字节
  /// 已经落进临时目录并记进缓存，关译文走的是缓存命中，根本不会再要字节 ——
  /// 卡在那儿的话这条测试等的其实是一个不会发生的挂起。
  Completer<void>? pathGate;
  int pathHits = 0;

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
    pathHits++;
    await pathGate?.future;
    return null;
  }

  @override
  Future<Uint8List?> getPageBytes(int index) async => bytes;
}

class _FakePresenter implements TranslatedPagePresenter {
  _FakePresenter({this.confirmed, this.bypassed = false});

  /// `null` = 呈现器答不上来；`false` = 注入了但画面没换。
  final bool? confirmed;

  /// 呈现器是否在跑「原图对比」旁路 —— 开着时 `confirmed` 必然为 `false`，
  /// 而那句 false 描述的是旁路，不是注入失败。
  final bool bypassed;

  final Map<int, String> _owned = <int, String>{};
  final List<(int, String)> injected = <(int, String)>[];
  int redraws = 0;

  @override
  Map<int, String> get translationOwnedPages => _owned;

  @override
  bool get bypassesEnhancedTrack => bypassed;

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

/// 等到条件成立，最多 5 s。
///
/// 不用 `for (i < 20) await Future.delayed(Duration.zero)`：那几条 await 后面是
/// **真文件 IO**（读配置、查权重体积），整机负载高时 20 个空转微任务根本等不到，
/// 测试就会在满负载的那次运行里假红。
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for a controller state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
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
    bool retainErasedBase = false,
  }) async => TranslatedPage(
    path: path,
    fromCache: true,
    hasText: true,
    blockCount: 1,
    truncatedCount: 0,
    label: 'test-label',
  );
}

/// 假装这次构建在**翻译那一跳**上失败（真机上的成因：语言包没装 / 端点没起 / 漏译）。
/// 这一档现在没有「降级产物」兜着了 —— 失败就是失败，界面得如实说。
class _ThrowingBuilder extends TranslatedPageBuilder {
  _ThrowingBuilder(this.message);

  final String message;

  @override
  Future<TranslatedPage> build({
    required String imagePath,
    required int pageIndex,
    required OcrTranslationConfig config,
    void Function(TranslatedPageStage stage)? onStage,
    bool Function()? shouldCancel,
    bool force = false,
    bool retainErasedBase = false,
  }) async {
    throw OcrTranslationException(message);
  }
}

/// 一台「按叠层交回产物」的构建器。
///
/// 图层 JSON 由它自己写进缓存档，于是控制器的 `overlayReady` 判得出来；
/// `overlayNeedsBase` 由用例指定 —— 那一维正是「这一页要不要替它占增强图轨」的唯一入口。
class _OverlayBuilder extends TranslatedPageBuilder {
  _OverlayBuilder({
    required this.needsBase,
    required this.basePath,
    this.fromCache = false,
    this.layerFilled,
  });

  final bool needsBase;
  final String basePath;

  /// 图层里那框有没有填色。默认与 `needsBase` 相反（真链路里就是这一个条件），
  /// 只有「构建器报不出这一维」那一条要单独拧。
  final bool? layerFilled;

  bool get boxHasFill => layerFilled ?? !needsBase;

  /// 命中缓存那一趟：构建器什么都没算，报不出 `overlayNeedsBase`。
  final bool fromCache;
  static const label = 'overlay-test档';

  @override
  Future<TranslatedPage> build({
    required String imagePath,
    required int pageIndex,
    required OcrTranslationConfig config,
    void Function(TranslatedPageStage stage)? onStage,
    bool Function()? shouldCancel,
    bool force = false,
    bool retainErasedBase = false,
  }) async {
    await TranslatedPageCache.writeLayer(
      label: label,
      pageIndex: pageIndex,
      json: TranslatedPageLayer(
        pageWidth: _pageW,
        pageHeight: _pageH,
        boxes: [
          TranslatedBox(
            quad: [
              _box.left,
              _box.top,
              _box.right,
              _box.top,
              _box.right,
              _box.bottom,
              _box.left,
              _box.bottom,
            ],
            source: 'トカゲじゃ',
            text: '是蜥蜴啊',
            fill: boxHasFill
                ? const ui.Color.fromARGB(255, 255, 255, 255)
                : null,
          ),
        ],
      ).encode(),
    );
    return TranslatedPage(
      path: basePath,
      hasText: true,
      blockCount: 1,
      truncatedCount: 0,
      label: label,
      overlayNeedsBase: needsBase,
      fromCache: fromCache,
    );
  }
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
    await OcrLog.flush();
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
            await File(erasedPath!).writeAsBytes(page, flush: true);
            return OcrPageResult(
              blocks: blocks,
              pageWidth: _pageW,
              pageHeight: _pageH,
              detectMs: BigInt.one,
              recognizeMs: BigInt.one,
              inpaintMs: BigInt.one,
              erasedPath: erasedPath,
              stageEps: _fakeStageEps,
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

  test('原图对比开着：核对回 false 也判「已注入」，不谎报译文失败', () async {
    // 这就是 2026-10-03 那次「翻译全都失败」的现场：旁路按设计不参显增强图轨
    // （`enhance.rs` 的 `prefers_enhanced` = `!bypass && 有增强图`），
    // 于是开着它的每一页，核对都必然回 false。
    await seedReady();
    final c = controllerWith(blocks: blocks);
    final presenter = _FakePresenter(confirmed: false, bypassed: true);

    final ok = await c.toggle(
      source: _FakeSource(page),
      presenter: presenter,
      index: 6,
    );
    expect(
      ok,
      isTrue,
      reason: '产物已经生成并注入 —— 报成失败只会让用户反复重跑那十几秒',
    );
    expect(c.lastError, isEmpty);
    expect(c.phase, TranslatedPagePhase.showing);
    expect(presenter.injected, hasLength(1));
    expect(
      presenter.translationOwnedPages.keys,
      {6},
      reason: '不登记归属，超分就会来抢这一页的增强图轨',
    );
  });

  test('原图对比开着时点第二下：译文关得掉，归属要让出来', () async {
    // 关译文走的是同一条核对。旁路期间关不掉的话，用户只能看着芯片一直停在
    // 「译文页」，而画面上从头到尾都是原图。
    await seedReady();
    final c = controllerWith(blocks: blocks);
    final presenter = _FakePresenter(confirmed: false, bypassed: true);
    final source = _FakeSource(page);

    expect(
      await c.toggle(source: source, presenter: presenter, index: 1),
      isTrue,
    );
    expect(presenter.translationOwnedPages.keys, {1});

    expect(
      await c.toggle(source: source, presenter: presenter, index: 1),
      isTrue,
    );
    expect(presenter.translationOwnedPages, isEmpty);
    expect(c.phase, TranslatedPagePhase.off);
    expect(presenter.injected, hasLength(2));
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
          await File(erasedPath!).writeAsBytes(page, flush: true);
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
            stageEps: _fakeStageEps,
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
    await _until(() => c.phase == TranslatedPagePhase.building);
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

  test('换书之后剩下的阶段不该接着跑：取消要落在阶段之间', () async {
    // 「结果回来再丢弃」只保证不贴错图，代价是那十几秒 CPU 照样烧完。
    // 控制器必须把 shouldCancel 传下去：翻译这一跳回来时书已经换了，
    // 排版与落盘都不该再发生（粒度只能到阶段 —— Rust 侧一次调用没有取消点）。
    await seedReady();
    final gate = Completer<void>();
    var translateHits = 0;
    final presenter = _FakePresenter(confirmed: true);
    final c = TranslatedPageController(
      builder: TranslatedPageBuilder(
        analyze: (imagePath, erasedPath, ep) async {
          await File(erasedPath!).writeAsBytes(page, flush: true);
          return OcrPageResult(
            blocks: blocks,
            pageWidth: _pageW,
            pageHeight: _pageH,
            detectMs: BigInt.one,
            recognizeMs: BigInt.one,
            inpaintMs: BigInt.one,
            erasedPath: erasedPath,
            stageEps: _fakeStageEps,
          );
        },
        translate: (texts, config) async {
          translateHits++;
          await gate.future;
          return List.filled(texts.length, '是蜥蜴啊');
        },
      ),
    );

    final running = c.toggle(
      source: _FakeSource(page),
      presenter: presenter,
      index: 4,
    );
    await _until(() => translateHits > 0);
    c.reset(); // 换书就发生在翻译等待期间
    gate.complete();

    expect(await running, isFalse);
    expect(c.phase, TranslatedPagePhase.off);
    expect(c.lastError, isEmpty, reason: '自己取消的构建不该变成一条错误');
    expect(presenter.injected, isEmpty);
    final outDir = Directory('${root.path}/files/manga_translated');
    final written = outDir.existsSync()
        ? outDir.listSync(recursive: true).whereType<File>().toList()
        : const <File>[];
    expect(written, isEmpty, reason: '取消之后排版与落盘都不该发生');
  });

  test('换书把临时输入删了：在飞构建因此抛出的异常也算过期', () async {
    // `reset()` 会 deleteSync 掉临时输入目录，在飞的那次构建于是以「文件不见了」收场，
    // 走的是 `_turnOn` 的 catch 那一路。那里的顺序很要紧：先 `_fail` 再比号的话，
    // 新书第 3 页脸上会弹出一条「成品页构建失败：PathNotFoundException」。
    await seedReady();
    final gate = Completer<void>();
    final presenter = _FakePresenter(confirmed: true);
    final c = TranslatedPageController(
      builder: TranslatedPageBuilder(
        analyze: (imagePath, erasedPath, ep) async {
          await gate.future;
          throw const FileSystemException('输入文件已经不在了');
        },
        translate: (texts, config) async => ['是蜥蜴啊'],
      ),
    );

    final running = c.toggle(
      source: _FakeSource(page),
      presenter: presenter,
      index: 3,
    );
    await _until(() => c.phase == TranslatedPagePhase.building);
    c.reset(); // 换书：顺手删掉临时输入
    gate.complete();

    expect(await running, isFalse);
    expect(c.phase, TranslatedPagePhase.off);
    expect(c.lastError, isEmpty, reason: '过期任务的异常不该顶成新页脸上的错误条');
    expect(presenter.injected, isEmpty);
  });

  test('关译文关到一半换书：旧书的原图也不许注到新书上', () async {
    await seedReady();
    final presenter = _FakePresenter(confirmed: true);
    final source = _FakeSource(page);
    final c = controllerWith(blocks: blocks);

    await c.toggle(source: source, presenter: presenter, index: 2);
    expect(presenter.injected, hasLength(1));

    source.pathHits = 0;
    source.pathGate = Completer<void>();
    final turningOff = c.toggle(source: source, presenter: presenter, index: 2);
    await _until(() => source.pathGate != null && source.pathHits > 0);
    c.reset(); // 换书
    source.pathGate!.complete();

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

  test('翻译那一跳失败：整页按失败处理，不占增强图轨、不谎报译文页', () async {
    // 这一档以前会端出一张「擦掉日文又画回日文」的降级页 —— 页面看着像处理完了，
    // 只是没有一个字是译文。现在没有那条路了：失败必须显形，而且**不登记归属**，
    // 否则超分会一直给一张根本没上屏的译文页让路。
    await seedReady();
    final presenter = _FakePresenter(confirmed: true);
    final c = TranslatedPageController(
      builder: _ThrowingBuilder('系统翻译的语言包还没装（ja→zh-Hans：supported）'),
    );

    expect(
      await c.toggle(source: _FakeSource(page), presenter: presenter, index: 3),
      isFalse,
    );
    expect(c.phase, TranslatedPagePhase.failed);
    expect(c.lastError, contains('语言包还没装'));
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

  test('叠层档、每框都有填色：不注入、不占轨 —— 超分照常生效', () async {
    await seedReady();
    await TranslatedPageDisplayMode.save(TranslatedPageDisplayChoice.overlay);
    final base = '${root.path}/overlay_fill_only.png';
    await File(base).writeAsBytes(page, flush: true);
    final c = TranslatedPageController(
      builder: _OverlayBuilder(needsBase: false, basePath: base),
    );
    final presenter = _FakePresenter(confirmed: true);

    final ok = await c.toggle(
      source: _FakeSource(page),
      presenter: presenter,
      index: 2,
    );

    expect(ok, isTrue);
    expect(c.phase, TranslatedPagePhase.showing);
    expect(c.isOverlayActive(2), isTrue);
    expect(
      presenter.injected,
      isEmpty,
      reason: '这一页的底就是画面本来那张，占轨等于白白压掉超分',
    );
    expect(presenter.translationOwnedPages, isEmpty);
  });

  test('叠层档、需要擦字底图：登记档名，同时替这一页占轨', () async {
    await seedReady();
    await TranslatedPageDisplayMode.save(TranslatedPageDisplayChoice.overlay);
    // 底图必须真的在缓存档里：控制器是先问 `overlayReady` 才走叠层分支的，
    // 而「有框没填色」那一类页的底只能是这张擦字底图。
    final erasedBase = await TranslatedPageCache.baseFile(
      label: _OverlayBuilder.label,
      pageIndex: 3,
    );
    await erasedBase.create(recursive: true);
    await erasedBase.writeAsBytes(page, flush: true);
    final c = TranslatedPageController(
      builder: _OverlayBuilder(needsBase: true, basePath: erasedBase.path),
    );
    final presenter = _FakePresenter(confirmed: true);

    final ok = await c.toggle(
      source: _FakeSource(page),
      presenter: presenter,
      index: 3,
    );

    expect(ok, isTrue);
    expect(
      c.isOverlayActive(3),
      isTrue,
      reason: '占轨是为了把底图换上屏，字仍然由叠层那一层画',
    );
    expect(
      presenter.injected,
      hasLength(1),
      reason: '底图不占轨就没人换上屏 —— 中文会压在日文下面（§决定 4 那条 0.085）',
    );
    expect(presenter.injected.single.$2, erasedBase.path);
    expect(presenter.translationOwnedPages.keys, {3});
  });

  test('叠层档、命中缓存：构建器报不出这一维，控制器现读图层', () async {
    // 占不占轨必须是这一页的**属性**。第一次建的时候替它占了轨，翻回来命中缓存就不占了，
    // 画面会从「擦干净的底 + 中文」变回「日文压在中文下面」—— 同一页两种画面，
    // 而这种错只有翻回来才看得见。
    await seedReady();
    await TranslatedPageDisplayMode.save(TranslatedPageDisplayChoice.overlay);
    final erasedBase = await TranslatedPageCache.baseFile(
      label: _OverlayBuilder.label,
      pageIndex: 5,
    );
    await erasedBase.create(recursive: true);
    await erasedBase.writeAsBytes(page, flush: true);
    final c = TranslatedPageController(
      builder: _OverlayBuilder(
        needsBase: false,
        fromCache: true,
        layerFilled: false,
        basePath: erasedBase.path,
      ),
    );
    final presenter = _FakePresenter(confirmed: true);

    final ok = await c.toggle(
      source: _FakeSource(page),
      presenter: presenter,
      index: 5,
    );

    expect(ok, isTrue);
    expect(c.isOverlayActive(5), isTrue);
    expect(
      presenter.translationOwnedPages.keys,
      {5},
      reason: '图层里那框没有填色 ⇒ 这一页的底只能是擦字底图，命中缓存也一样要占轨',
    );
  });

  test('「对比原图」开着：控制器报得出旁路，叠层那一层才让得开', () async {
    // 旁路屏蔽的是增强图轨。烘焙档自然被挡住，而叠层是 Flutter 侧的一层 ——
    // 不读这一维，用户按下对比原图看到的是「原图 + 中文」。
    await seedReady();
    await TranslatedPageDisplayMode.save(TranslatedPageDisplayChoice.overlay);
    final base = '${root.path}/overlay_bypass.png';
    await File(base).writeAsBytes(page, flush: true);
    final c = TranslatedPageController(
      builder: _OverlayBuilder(needsBase: false, basePath: base),
    );
    expect(
      c.bypassesOriginalPreview,
      isFalse,
      reason: '还没挂呈现器就说「旁路开着」，是拿未知当证据',
    );

    final presenter = _FakePresenter(confirmed: true, bypassed: true);
    await c.toggle(source: _FakeSource(page), presenter: presenter, index: 6);
    expect(
      c.bypassesOriginalPreview,
      isTrue,
      reason: '这一维要如实转达呈现器那句「我在跑原图对比」',
    );
  });
}
