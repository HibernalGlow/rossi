import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/image_surface.dart';
import 'package:zephyr/reader/page_source.dart';

/// 呈现器的替身。
///
/// `present` 一调就成功（除非被 `busy` 挡住），并把「纹理里现在是哪一页」
/// 如实记在 [frame] 里 —— 这正是 `_buildContent` 唯一相信的那个事实。
class _FakePresenter extends GpuPresentController {
  GpuPresentedFrame? frame;
  final List<int> presents = <int>[];
  int count = 0;
  bool busy = false;
  bool canPresentNow = true;

  @override
  GpuPresentedFrame? get presentedFrame => frame;

  @override
  bool get isPresenting => busy;

  @override
  int get presentCount => count;

  @override
  bool get canPresent => canPresentNow;

  @override
  int get textureId => 1;

  @override
  Future<bool> present({
    required PageSource source,
    required int index,
    required Size physicalSize,
  }) async {
    if (frame?.matches(source, index, physicalSize) == true) return true;
    presents.add(index);
    frame = GpuPresentedFrame(
      source: source,
      index: index,
      physicalSize: physicalSize,
      textureId: textureId,
    );
    count++;
    return true;
  }

  /// 模拟「另一页上屏了」：纹理里换成了别人的画面。
  void textureNowHolds(PageSource source, GpuPresentedFrame next) {
    frame = next;
    count++;
    notifyListeners();
  }
}

/// 不碰磁盘、不碰 FFI 的来源。解出来的位图是 2×2 四色块，`RawImage` 画得出来。
class _FakeSource implements PageSource {
  @override
  final String path = r'C:\fake\book.cbz';

  @override
  final int pageCount = 3;

  /// 每次 `load` 的入参，按调用顺序记下来 —— 断言"请求了哪一页、按多宽解、什么许可"。
  final List<({int index, int? targetWidth, PageLoadIntent intent})> loads =
      <({int index, int? targetWidth, PageLoadIntent intent})>[];

  /// 前 N 次 `load` 回「没轮到就作废了」。
  ///
  /// 这是**真实会发生**的一类结果（请求还在队列里就被更新的跳页请求取代），
  /// 而它**不是这一页的属性** —— 拿它当"这一页解不了"，下次翻到这里就是一片空白，
  /// 而且再也回不来。
  int cancelFirstLoads = 0;

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
    loads.add((index: index, targetWidth: targetWidth, intent: intent));
    if (cancelFirstLoads > 0) {
      cancelFirstLoads--;
      return const PageLoadFailed(
        kind: PageLoadFailureKind.cancelled,
        message: '这一页的加载已经过期',
      );
    }
    return PageLoaded(
      RasterPageContent(
        width: 2,
        height: 2,
        sourceWidth: 200,
        sourceHeight: 200,
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
  Future<void> close() async {}

  @override
  Future<String?> getPageFilePath(int index) => Future.value(null);

  @override
  Future<Uint8List?> getPageBytes(int index) => Future.value(null);
}

/// 兜底路要过 `ui.decodeImageFromPixels`，它的完成回调走**真实**事件循环，
/// 而 `testWidgets` 默认跑在假时钟里 —— 不显式放它跑，就永远等不到位图。
///
/// [untilRawImage] 为真时等到"出现一张与 [previousImage] 不同的 `RawImage`"；
/// 为假时只是把真实事件循环推够时间（用于"纹理在画、位图在后台备着"那种状态）。
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
      final ui.Image? image = tester
          .widget<RawImage>(find.byType(RawImage))
          .image;
      if (image != null && !identical(image, previousImage)) return;
    }
  }
}

Widget _host(
  PageSource source,
  int index,
  GpuPresentController presenter, {
  bool drivesPresentation = true,
  bool holdOwnBitmap = false,
  double bitmapWidthScale = 1.0,
  List<ImageSurfacePath>? paths,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ImageSurface(
        source: source,
        index: index,
        presenter: presenter,
        drivesPresentation: drivesPresentation,
        holdOwnBitmap: holdOwnBitmap,
        bitmapWidthScale: bitmapWidthScale,
        onPathChanged: paths?.add,
      ),
    ),
  );
}

GpuPresentedFrame _frame(PageSource source, int index) => GpuPresentedFrame(
  source: source,
  index: index,
  physicalSize: const Size(400, 600),
  textureId: 1,
);

/// 一页在滑出去的时候是**谁**在画它。
///
/// 共享纹理只有一张、且归当前页用，所以滑动过半时新页 `present` 那一刻，
/// 旧页手里的纹理里立刻就是别人的画面了。这一组判据钉的就是"那两半"。
void main() {
  testWidgets('邻页节点不碰共享纹理，只解自己那份位图，并按 prefetch 许可取页', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final source = _FakeSource();
    final presenter = _FakePresenter();
    addTearDown(presenter.dispose);
    // 故意让纹理里**恰好**是这一页：没有 `drivesPresentation` 这道闸，
    // 邻页节点会以为自己可以画它 —— 两个节点都推就是 Ping-Pong 拔河（红黄闪）。
    presenter.frame = _frame(source, 1);
    final paths = <ImageSurfacePath>[];

    await tester.pumpWidget(
      _host(
        source,
        1,
        presenter,
        drivesPresentation: false,
        bitmapWidthScale: kNeighborBitmapWidthScale,
        paths: paths,
      ),
    );
    await _flushDecode(tester, untilRawImage: true);

    expect(presenter.presents, isEmpty, reason: '邻页去推共享纹理 = 红黄闪');
    expect(find.byType(Texture), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
    expect(paths, <ImageSurfacePath>[ImageSurfacePath.cpu]);

    // 邻页只是提前把位图备好，**不能**挤掉用户在等的那一页：调度器给交互那一档
    // 留的许可比这里多。
    expect(source.loads.single.index, 1);
    expect(source.loads.single.intent, PageLoadIntent.prefetch);
    // 而且它按**缩小**的宽度解。这一份位图决定的是"翻页那一瞬有没有像素"：
    // 视口宽全解要 300–400 ms，比连翻的间隔还长 —— 赶不上就透出阅读底色。
    // 视口逻辑宽 200（物理 400）× 0.5 = 200。
    expect(
      source.loads.single.targetWidth,
      200,
      reason: '邻页按全宽解 ⇒ 翻页那一瞬还没解完 ⇒ 黑一下',
    );
  });

  testWidgets('要自己上屏的那一页在兜底时按 interactive 取页，不排在预取后面', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final source = _FakeSource();
    // 呈现器不可用 → 走兜底。兜底这一页就是**用户在等**的那一页。
    final presenter = _FakePresenter()..canPresentNow = false;
    addTearDown(presenter.dispose);

    await tester.pumpWidget(_host(source, 0, presenter));
    await _flushDecode(tester, untilRawImage: true);

    expect(presenter.presents, isEmpty);
    expect(source.loads.single.intent, PageLoadIntent.interactive);
  });

  testWidgets('「没轮到就作废」不会把这一页永久拉黑', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final source = _FakeSource()..cancelFirstLoads = 1;
    // 呈现器不可用 ⇒ 画面全靠这条兜底路，所以"还能不能再试"直接等于"这一页画不画得出来"。
    final presenter = _FakePresenter()..canPresentNow = false;
    addTearDown(presenter.dispose);

    // 第一次请求被更新的跳页请求取代了（`cancelled`）：这一页还没有像素。
    await tester.pumpWidget(_host(source, 0, presenter));
    await tester.pump();
    await tester.pump();
    expect(source.loads, isNotEmpty);
    expect(source.loads.first.index, 0);

    // 从前这里会把这一页记成"解不了"，于是**再也不发** —— 下次翻到它是一片空白，
    // 重开也一样。取消只是一次调度事件，不是这一页的属性。
    //
    // 而这类结果**不改任何状态**，所以不会自己再来一次 `build` —— 重试必须由节点
    // 自己安排（见 `_cancelRetry`）。所以这里推的是时间，不是只推一帧。
    await tester.pump(const Duration(milliseconds: 150));
    await _flushDecode(tester, untilRawImage: true);
    expect(source.loads.length, greaterThan(1), reason: '一次取消之后必须还会再试');
    expect(find.byType(RawImage), findsOneWidget, reason: '最终必须真的出图');
  });

  testWidgets('留位图时：上屏成功后仍在后台备一份，退场的那一瞬就有画面', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final source = _FakeSource();
    final presenter = _FakePresenter();
    addTearDown(presenter.dispose);

    await tester.pumpWidget(
      _host(source, 0, presenter, holdOwnBitmap: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Texture), findsOneWidget);
    // 上屏成功**不等于**位图白解了：它要在这一页退场时接上。
    await _flushDecode(tester, untilRawImage: false);
    expect(source.loads.map((r) => r.index), contains(0));

    // 翻页：这一页从"当前页"变成"正在滑出去的那一页"，与此同时纹理里
    // 已经换成了新页的画面。
    presenter.textureNowHolds(source, _frame(source, 1));
    await tester.pumpWidget(
      _host(source, 0, presenter, drivesPresentation: false, holdOwnBitmap: true),
    );
    await tester.pump();

    expect(find.byType(Texture), findsNothing, reason: '纹理里是别人的画面，照画就是页码与画面对不上');
    expect(
      find.byType(RawImage),
      findsOneWidget,
      reason: '退场那一半必须**立刻**有画面 —— 让用户等一次新解码等于没修',
    );
  });

  testWidgets('关掉留位图之后：同样的退场就没有画面（这就是那个开关买到的东西）', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final source = _FakeSource();
    final presenter = _FakePresenter();
    addTearDown(presenter.dispose);

    await tester.pumpWidget(
      _host(source, 0, presenter, holdOwnBitmap: false),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Texture), findsOneWidget);

    await _flushDecode(tester, untilRawImage: false);
    // 不上屏成功之后再去解一份位图 —— 每页少留一张视口宽度的位图。
    expect(source.loads, isEmpty, reason: '不走 CPU 路就不该有一次过桥解码');

    presenter.textureNowHolds(source, _frame(source, 1));
    await tester.pumpWidget(
      _host(
        source,
        0,
        presenter,
        drivesPresentation: false,
        holdOwnBitmap: false,
      ),
    );
    await tester.pump();

    // 不是 bug：关掉这个开关就是拿"退场那半秒的黑"换每页少一份位图的内存。
    expect(find.byType(Texture), findsNothing);
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets('纹理里不是这一页就绝不照画，哪怕这个节点仍是当前页', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final source = _FakeSource();
    final presenter = _FakePresenter();
    addTearDown(presenter.dispose);

    await tester.pumpWidget(
      _host(source, 0, presenter, holdOwnBitmap: true),
    );
    await tester.pumpAndSettle();
    await _flushDecode(tester, untilRawImage: false);
    expect(find.byType(Texture), findsOneWidget);

    // 另一个节点正在上屏（`isPresenting`），这期间纹理里已经是**别人的**一页。
    // 此时本节点仍是当前页、也不会被重新推一次 —— 于是"纹理恰好是本页"这个
    // 事实的判定完全落在 `GpuPresentedFrame.matches` 上。
    presenter.busy = true;
    presenter.textureNowHolds(source, _frame(source, 1));
    await tester.pump();

    expect(presenter.presents, <int>[0], reason: '本节点不该在这时候再推一次');
    expect(
      find.byType(Texture),
      findsNothing,
      reason: '把别人的帧画进这一格，就是"页码与画面对不上"',
    );
    expect(find.byType(RawImage), findsOneWidget, reason: '能画的只剩自己那份位图');
  });
}
