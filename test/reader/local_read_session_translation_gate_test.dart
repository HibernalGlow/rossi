/// `LocalReadSession` 那两个入口与「在飞的成品页构建」之间的关系。
///
/// ADR-0018 Consequences 要求退出阅读 / 切章时取消在途推理。落地是两行装配
/// （`setSource` 与 `dispose` 各调一次 `TranslatedPageController.reset()`），
/// 而验收清单里我当时明写了「那一行装配没有单测，只能真机判」。这条文件就是来还这笔的：
/// 两行装配里有一条很阴的错法 —— 新页的 `State.dispose` 晚于新页的 `setSource` 时，
/// 无条件 reset 会把**新书**刚建好的状态与在飞构建一起清掉。
/// `dispose(expectedPath:)` 那道路径闸防的就是它，所以闸本身必须有测试。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/reader/translated_page_controller.dart';
import 'package:zephyr/service/ocr/ocr_models.dart';
import 'package:zephyr/service/ocr/translated_page_builder.dart';
import 'package:zephyr/src/rust/api/ocr.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');
const _pageW = 400, _pageH = 300;
final _box = const ui.Rect.fromLTWH(40, 30, 140, 90);

class _Source implements PageSource {
  _Source(this.path, this.bytes);

  @override
  final String path;
  final Uint8List bytes;
  Completer<void>? gate;

  @override
  List<PageRef> get pages => const [];
  @override
  int get pageCount => 1;
  @override
  RasterTargetRef? rasterTargetFor(int index) => null;
  @override
  Future<PageLoadOutcome> load(
    int index, {
    int? targetWidth,
    PageLoadIntent intent = PageLoadIntent.interactive,
  }) => throw UnimplementedError();

  @override
  Future<String?> getPageFilePath(int index) async => null;

  @override
  Future<Uint8List?> getPageBytes(int index) async {
    await gate?.future;
    return bytes;
  }

  @override
  Future<void> close() async {}
}

class _Presenter implements TranslatedPagePresenter {
  final Map<int, String> owned = <int, String>{};
  final List<String> injected = <String>[];

  @override
  Map<int, String> get translationOwnedPages => owned;
  @override
  Future<bool> setEnhancedImage(int index, String imagePath) async {
    injected.add(imagePath);
    return true;
  }

  @override
  Future<bool> reshowAfterInjection(int index) async => true;
  @override
  Future<bool?> presenterUsesEnhanced(int index) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Uint8List page;
  late TranslatedPageController previous;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rossi_read_session_gate_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => root.path);
    SharedPreferences.setMockInitialValues({});
    page = await _whitePng();
    // 权重齐 + 端点配好：控制器才允许进入 building，否则测的是前置检查不是闸。
    _fakeWeights(Directory('${root.path}/files/manga_ocr'));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ocr_base_url', 'http://127.0.0.1:11434/v1');
    await prefs.setString('ocr_model', 'qwen2.5:14b');
    previous = TranslatedPageController.useForTest(_gatedController(page));
  });

  tearDown(() async {
    TranslatedPageController.instance.reset();
    TranslatedPageController.instance = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await root.delete(recursive: true);
  });

  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('等不到控制器进入生成中');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('退出的是**别的**书：不许把当前这本的在飞构建一起清掉', () async {
    final controller = TranslatedPageController.instance;
    final source = _Source('/gate/current.cbz', page)
      ..gate = Completer<void>(); // 卡在取原图：构建必须还在飞
    LocalReadSession.instance.setSource(source);
    final presenter = _Presenter();
    final running = controller.toggle(
      source: source,
      presenter: presenter,
      index: 0,
    );
    await until(() => controller.phase == TranslatedPagePhase.building);

    // comicId 与当前来源路径不同 —— 那是上一页/上一本的 State.dispose 在收尾。
    await LocalReadSession.instance.dispose(
      expectedPath: '/gate/some_other.cbz',
    );

    expect(
      controller.phase,
      TranslatedPagePhase.building,
      reason: '闸没生效时这里会变成 off：旧页的 dispose 把新页刚起的构建清了',
    );
    source.gate!.complete();
    expect(await running, isTrue, reason: '没过期，构建该照常走完并注入');
    expect(presenter.injected, hasLength(1));
    expect(presenter.translationOwnedPages, contains(0));
  });

  test('退出的是**当前这本**：在飞构建必须认过期，且不留下归属', () async {
    final controller = TranslatedPageController.instance;
    final source = _Source('/gate/current.cbz', page)..gate = Completer<void>();
    LocalReadSession.instance.setSource(source);
    final presenter = _Presenter();
    final running = controller.toggle(
      source: source,
      presenter: presenter,
      index: 0,
    );
    await until(() => controller.phase == TranslatedPagePhase.building);

    await LocalReadSession.instance.dispose(expectedPath: '/gate/current.cbz');

    expect(controller.phase, TranslatedPagePhase.off);
    source.gate!.complete();
    expect(await running, isFalse);
    expect(presenter.injected, isEmpty, reason: '书都退出了，成品页没有归宿');
    expect(presenter.translationOwnedPages, isEmpty);
  });
}

/// 一台**只把分析/翻译当假件**的控制器，装进单例后才能被 `LocalReadSession` 的装配碰到。
TranslatedPageController _gatedController(Uint8List page) =>
    TranslatedPageController(
      builder: TranslatedPageBuilder(
        analyze: (imagePath, erasedPath, ep) async {
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

Future<Uint8List> _whitePng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, _pageW.toDouble(), _pageH.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(_pageW, _pageH);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

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
