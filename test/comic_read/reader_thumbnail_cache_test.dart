import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/bottom_thumbnail_strip.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/service/reader/reader_thumbnail_service.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

class _Source implements PageSource {
  @override
  String get path => '/shared/book.cbz';
  @override
  List<PageRef> get pages => [
    PageRef(index: 0, name: 'page.png', size: BigInt.one),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements RustLibApi {
  final requests = <Completer<Uint8List?>>[];
  final started = StreamController<void>.broadcast(sync: true);
  @override
  Future<Uint8List?> crateApiLocalThumbnailGetLocalThumbnail({
    required String cacheDir,
    required String bookPath,
    required String entryName,
    required int pageIndex,
    int? maxLongSide,
  }) {
    expect(bookPath, '/shared/book.cbz');
    expect(entryName, 'page.png');
    expect(pageIndex, 0);
    final request = Completer<Uint8List?>();
    requests.add(request);
    started.add(null);
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final service = ReaderThumbnailService.instance;
  final source = _Source();
  late Directory root;
  late _Api api;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('rossi-thumbnail-cache-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    await service.getCatalogCacheDir();
  });
  setUp(() {
    service.clear();
    api = _Api();
    RustLib.initMock(api: api);
  });
  tearDown(() async {
    RustLib.dispose();
    // ignore: invalid_use_of_internal_member
    RustLib.instance.resetState();
    await api.started.close();
  });
  tearDownAll(() async {
    service.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  test('胶卷与页列表同时加载同页只生成一次，并共享同一份字节', () async {
    final started = api.started.stream.first;
    final strip = service.getLocalThumbnailBytes(source: source, index: 0);
    final panel = service.getLocalThumbnailBytes(source: source, index: 0);
    await started;
    expect(api.requests, hasLength(1));
    final bytes = Uint8List.fromList([1, 2, 3]);
    api.requests.single.complete(bytes);
    final loaded = await Future.wait([strip, panel]);
    expect(identical(loaded[0], loaded[1]), isTrue);
    expect(
      identical(
        await service.getLocalThumbnailBytes(source: source, index: 0),
        bytes,
      ),
      isTrue,
    );
    expect(api.requests, hasLength(1));
  });

  test('失败后释放在途请求，下次打开可以重试', () async {
    var started = api.started.stream.first;
    final failed = service.getLocalThumbnailBytes(source: source, index: 0);
    await started;
    api.requests.single.completeError(StateError('decode failed'));
    expect(await failed, isNull);
    started = api.started.stream.first;
    final retry = service.getLocalThumbnailBytes(source: source, index: 0);
    await started;
    expect(api.requests, hasLength(2));
    api.requests.last.complete(Uint8List.fromList([1]));
    expect(await retry, isNotNull);
  });

  testWidgets('两个入口共享解码键，切换比例不再生成或解码图片', (tester) async {
    final bytes = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 120, 60),
        ui.Paint()..color = const ui.Color(0xff336699),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(120, 60);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return data!.buffer.asUint8List();
    }))!;
    var original = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return BottomThumbnailStrip(
                        totalPages: 1,
                        currentSlot: 0,
                        comicId: 'comic',
                        from: 'local',
                        localSource: source,
                        onSelectPage: (_) {},
                        originalAspectRatio: original,
                      );
                    },
                  ),
                  ReaderThumbnailWidget(
                    index: 0,
                    comicId: 'comic',
                    from: 'local',
                    localSource: source,
                    width: 80,
                    height: 80,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(api.requests, hasLength(1));
    api.requests.single.complete(bytes);
    await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    final providers = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .toList();
    await tester.runAsync(() async {
      final stream = providers.first.resolve(ImageConfiguration.empty);
      final loaded = Completer<void>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          info.dispose();
          stream.removeListener(listener);
          loaded.complete();
        },
        onError: (Object error, StackTrace? stack) {
          stream.removeListener(listener);
          loaded.completeError(error, stack);
        },
      );
      stream.addListener(listener);
      await loaded.future;
    });
    await tester.pumpAndSettle();
    expect(providers, hasLength(2));
    expect(providers[0], providers[1]);
    update(() => original = true);
    await tester.pumpAndSettle();
    expect(api.requests, hasLength(1));
    final currentProviders = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .toList();
    expect(currentProviders, providers);
    final tile = find.byKey(const ValueKey('reader-thumbnail-tile-0'));
    expect(
      tester.getSize(tile).width,
      closeTo(tester.getSize(tile).height * 2, .01),
    );
    expect(tester.takeException(), isNull);
  });

  test('不同分辨率保留独立的缓存与请求键', () async {
    final started = api.started.stream.take(2).toList();
    final normal = service.getLocalThumbnailBytes(source: source, index: 0);
    final small = service.getLocalThumbnailBytes(
      source: source,
      index: 0,
      maxLongSide: 160,
    );
    await started;
    expect(api.requests, hasLength(2));
    api.requests[0].complete(Uint8List.fromList([1]));
    api.requests[1].complete(Uint8List.fromList([2]));
    final loaded = await Future.wait([normal, small]);
    expect(identical(loaded[0], loaded[1]), isFalse);
  });
}
