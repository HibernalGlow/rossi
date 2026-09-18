import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/image_surface.dart';
import 'package:zephyr/reader/page_source.dart';

/// 一个不碰磁盘、不碰 FFI 的来源，用来把显示节点的**确定性行为**钉住。
///
/// 真机那条路（`integration_test/gpu_present_probe_test.dart`）验的是"链路通不通"，
/// 需要引擎、需要样本、跑一次要几分钟。而节点自己有一批与引擎无关的行为 ——
/// 未就绪时落兜底、翻页要重新取、失败文案怎么给、越界下标怎么办 ——
/// 那些用不着引擎，用这个假来源就能每次都验一遍。
class _FakeSource implements PageSource {
  _FakeSource({
    this.pageCount = 3,
    this.failure,
  });

  /// 假来源也必须有个路径：`rasterTargetFor` 给出的页标识里带着它，
  /// 而控制器就是靠它判断"native 侧打开的是不是同一份"。
  @override
  final String path = r'C:\fake\book.cbz';

  @override
  final int pageCount;

  /// 每次 `load` 的入参，按调用顺序记下来 —— 断言"请求了哪一页、按多宽解"。
  final List<({int index, int? targetWidth})> loads =
      <({int index, int? targetWidth})>[];

  /// 非空则每次 `load` 都返回它。
  final PageLoadFailureKind? failure;

  int closeCalls = 0;

  @override
  List<PageRef> get pages => <PageRef>[
        for (int i = 0; i < pageCount; i++)
          PageRef(index: i, name: 'page-$i.jpg', size: BigInt.from(1024)),
      ];

  @override
  RasterTargetRef? rasterTargetFor(int index) => (index < 0 || index >= pageCount)
      ? null
      : RasterTargetRef(path: path, index: index);

  @override
  Future<PageLoadOutcome> load(
    int index, {
    int? targetWidth,
    PageLoadIntent intent = PageLoadIntent.interactive,
  }) async {
    loads.add((index: index, targetWidth: targetWidth));
    final PageLoadFailureKind? failure = this.failure;
    if (failure != null) {
      return PageLoadFailed(kind: failure, message: '假失败：第 ${index + 1} 页');
    }
    // 2×2 的四色块，够 `RawImage` 画出来。
    return PageLoaded(
      RasterPageContent(
        width: 2,
        height: 2,
        sourceWidth: 2,
        sourceHeight: 2,
        rgba: Uint8List.fromList(<int>[
          255, 0, 0, 255, //
          0, 255, 0, 255, //
          0, 0, 255, 255, //
          255, 255, 255, 255, //
        ]),
      ),
    );
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }

  // 超分流水线要靠这两个取"原始一页"（散图给路径、归档给字节）。
  // 假来源没有磁盘上的页，如实回 null —— **不要**为了让它看起来能跑超分而造假数据：
  // 这条路径的测试点在真实夹具上。
  //
  // 这两个成员是 `PageSource` 后来加的（带默认实现）。`implements` 不继承默认实现，
  // 所以每加一个成员，所有假来源都得跟着补 —— 编译期就会报出来，这是故意留着的摩擦。
  @override
  Future<String?> getPageFilePath(int index) => Future.value(null);

  @override
  Future<Uint8List?> getPageBytes(int index) => Future.value(null);
}

/// 兜底路要过 `ui.decodeImageFromPixels`，它的完成回调走**真实**事件循环，
/// 而 `testWidgets` 默认跑在假时钟里 —— 不显式放它跑，就永远等不到位图。
Future<void> _flushDecode(
  WidgetTester tester, {
  required bool untilRawImage,
  ui.Image? previousImage,
}) async {
  for (int i = 0; i < 20; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    if (untilRawImage && find.byType(RawImage).evaluate().isNotEmpty) {
      final image = tester.widget<RawImage>(find.byType(RawImage)).image;
      if (image != null && !identical(image, previousImage)) return;
    }
  }
}

Widget _host(PageSource source, int index, GpuPresentController presenter, List<ImageSurfacePath> paths) {
  return MaterialApp(
    home: Scaffold(
      body: ImageSurface(
        source: source,
        index: index,
        presenter: presenter,
        onPathChanged: paths.add,
      ),
    ),
  );
}

void main() {
  testWidgets('未就绪时走 CPU 兜底，并按控件的**物理**宽度请求解码', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final _FakeSource source = _FakeSource();
    // 不 start() → 状态永远停在 loading，这正是"呈现器还没建好"那一档。
    final GpuPresentController presenter = GpuPresentController();
    addTearDown(presenter.dispose);
    final List<ImageSurfacePath> paths = <ImageSurfacePath>[];

    await tester.pumpWidget(_host(source, 0, presenter, paths));
    await _flushDecode(tester, untilRawImage: true);

    expect(paths, <ImageSurfacePath>[ImageSurfacePath.cpu]);
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.byType(Texture), findsNothing);

    // 物理 = 逻辑 × DPR = （800/2）× 2 = 800。给逻辑尺寸的话这里会是 400，
    // 而那在 2x 屏上就是一张被拉伸的模糊图。
    expect(source.loads, hasLength(1));
    expect(source.loads.single.index, 0);
    expect(source.loads.single.targetWidth, 800);
  });

  testWidgets('翻页会重新取页，并释放上一页的位图', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final _FakeSource source = _FakeSource();
    final GpuPresentController presenter = GpuPresentController();
    addTearDown(presenter.dispose);
    final List<ImageSurfacePath> paths = <ImageSurfacePath>[];

    await tester.pumpWidget(_host(source, 0, presenter, paths));
    await _flushDecode(tester, untilRawImage: true);

    final ui.Image firstPage =
        tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(firstPage.debugDisposed, isFalse);

    await tester.pumpWidget(_host(source, 1, presenter, paths));
    await _flushDecode(tester, untilRawImage: true, previousImage: firstPage);

    expect(source.loads.map((r) => r.index), <int>[0, 1]);
    // 单页位图可达 179 MB（44.8 MPix 那一档），翻页不释放等于连读几本就把内存吃光。
    // 这一帧可能还在用它，所以释放是延后一帧的 —— 再多推一帧等它落地。
    await tester.pump();
    expect(firstPage.debugDisposed, isTrue, reason: '翻页后上一页的位图没有被释放');

    final ui.Image secondPage =
        tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(secondPage.debugDisposed, isFalse);
  });

  testWidgets('解码失败时把 Rust 给的原因显示出来', (WidgetTester tester) async {
    final _FakeSource source = _FakeSource(failure: PageLoadFailureKind.decodeFailed);
    final GpuPresentController presenter = GpuPresentController();
    addTearDown(presenter.dispose);

    await tester.pumpWidget(_host(source, 0, presenter, <ImageSurfacePath>[]));
    await _flushDecode(tester, untilRawImage: false);

    expect(find.textContaining('假失败'), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets('cancelled 不当作错误显示（那一页完全可能解得出）', (WidgetTester tester) async {
    final _FakeSource source = _FakeSource(failure: PageLoadFailureKind.cancelled);
    final GpuPresentController presenter = GpuPresentController();
    addTearDown(presenter.dispose);

    await tester.pumpWidget(_host(source, 0, presenter, <ImageSurfacePath>[]));
    await _flushDecode(tester, untilRawImage: false);

    expect(find.textContaining('已经过期'), findsOneWidget);
    expect(
      find.textContaining('假失败'),
      findsNothing,
      reason: 'cancelled 被显示成了"解不了" —— 用户会据此以为这本打不开',
    );
  });

  testWidgets('越界下标不取页，并说明是页码问题', (WidgetTester tester) async {
    final _FakeSource source = _FakeSource(pageCount: 3);
    final GpuPresentController presenter = GpuPresentController();
    addTearDown(presenter.dispose);

    await tester.pumpWidget(_host(source, 7, presenter, <ImageSurfacePath>[]));
    await _flushDecode(tester, untilRawImage: false);

    // 越界请求换来的失败文案会指向"数据坏了"，把调用方的 bug 伪装成数据问题。
    expect(source.loads, isEmpty);
    expect(find.textContaining('页码越界'), findsOneWidget);
  });
}
