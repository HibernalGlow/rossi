import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zephyr/reader/animated_local_page.dart';
import 'package:zephyr/reader/page_source.dart';

/// `AnimatedLocalPage` 的换路条件。
///
/// 夹具是**一张真 PNG 挂在 `.gif` 名下**：引擎按魔数认格式，所以「动图那条路解得开」
/// 不需要仓库里有 GIF 样本；而 `.gif` 这个后缀就足以让判定走动图档
/// （`animatedByExtensionName` 只看后缀）。反过来同一张 PNG 挂在 `.jpg` 名下时，
/// 名字与容器都不像动图 → 必须一路留在 `child` 上。
void main() {
  late Directory temp;
  late Uint8List pngBytes;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('rossi-animated-page-');
    final canvas = img.Image(width: 3, height: 2);
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 3; x++) {
        canvas.setPixel(x, y, img.ColorRgba8(10, 20, 30, 255));
      }
    }
    pngBytes = Uint8List.fromList(img.encodePng(canvas));
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  /// 图片解码走的是真异步（编解码器回调不是微任务），fake-async 的 `pumpAndSettle`
  /// 等不到它 —— 必须在 `runAsync` 里泵。
  Future<void> pump(
    WidgetTester tester,
    PageSource source, {
    ValueChanged<Size>? onIntrinsicSize,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: AnimatedLocalPage(
                source: source,
                index: 0,
                onIntrinsicSize: onIntrinsicSize,
                child: const Placeholder(key: Key('static-route')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      // `pumpAndSettle` 只在「还有帧要画」时泵，不会等真时间过去；解码回来的回调
      // 需要真实的事件循环轮次，所以这里显式让出真时间再泵。
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
  }

  testWidgets('动图档换成 Image，并把画布尺寸报出去', (tester) async {
    Size? intrinsic;
    await pump(
      tester,
      _FakeSource(name: 'motion.gif', bytes: pngBytes),
      onIntrinsicSize: (size) => intrinsic = size,
    );

    expect(find.byKey(const Key('static-route')), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(intrinsic, const Size(3, 2));
  });

  testWidgets('后缀与容器都不像动图时，一路留在 child 上', (tester) async {
    await pump(tester, _FakeSource(name: 'page01.jpg', bytes: pngBytes));
    expect(find.byKey(const Key('static-route')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('有直接路径的动图用文件路径，不整条过桥', (tester) async {
    final file = File('${temp.path}/motion.gif')..writeAsBytesSync(pngBytes);
    final source = _FakeSource(name: 'motion.gif', bytes: pngBytes)
      ..filePath = file.path;
    await pump(tester, source);
    expect(find.byType(Image), findsOneWidget);
    expect(source.bytesReads, 0, reason: '散图不该整条字节过桥');
  });

  testWidgets('归档内的动图才取整条字节', (tester) async {
    final source = _FakeSource(name: 'motion.gif', bytes: pngBytes);
    await pump(tester, source);
    expect(find.byType(Image), findsOneWidget);
    expect(source.bytesReads, greaterThan(0));
  });

  testWidgets('字节取不到时不崩，交回 child', (tester) async {
    await pump(tester, _FakeSource(name: 'motion.gif', bytes: null));
    expect(find.byKey(const Key('static-route')), findsOneWidget);
  });

  testWidgets('页码越界时不做判定，交给 child 报越界', (tester) async {
    await pump(
      tester,
      _FakeSource(name: 'motion.gif', bytes: pngBytes, pageCount: 0),
    );
    expect(find.byKey(const Key('static-route')), findsOneWidget);
  });
}

class _FakeSource implements PageSource {
  _FakeSource({required String name, required this.bytes, int pageCount = 1})
    : pages = <PageRef>[
        for (var i = 0; i < pageCount; i++)
          PageRef(index: i, name: name, size: BigInt.from(1)),
      ];

  final Uint8List? bytes;
  @override
  List<PageRef> pages;
  String? filePath;
  int bytesReads = 0;

  @override
  String get path => '/fake/path.cbz';

  @override
  int get pageCount => pages.length;

  @override
  RasterTargetRef? rasterTargetFor(int index) => null;

  @override
  Future<PageLoadOutcome> load(
    int index, {
    int? targetWidth,
    PageLoadIntent intent = PageLoadIntent.interactive,
  }) async =>
      const PageLoadFailed(kind: PageLoadFailureKind.decodeFailed, message: '');

  @override
  Future<void> close() async {}

  @override
  Future<String?> getPageFilePath(int index) async => filePath;

  @override
  Future<Uint8List?> getPageBytes(int index) async {
    bytesReads++;
    return bytes;
  }
}
