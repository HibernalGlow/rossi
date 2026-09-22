import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/neighbor_page_prefetch.dart';
import 'package:zephyr/reader/page_source.dart';

/// 一个只够编译的假来源。
///
/// 本组判据验的是**预取调度**（发不发、发几次、按什么尺寸发、失败后还发不发），
/// 全程不碰解码路。所以除了 `pageCount` / `path`（控制器要靠它们做越界与
/// 「native 侧打开的是不是这一份」的判断）以外的成员一律抛：
/// 真被调到就说明有人把这条判据写歪了 —— 那比"悄悄用了假数据"好得多。
class _FakeSource implements PageSource {
  @override
  final String path = r'C:\fake\book.cbz';

  @override
  final int pageCount = 3;

  Never _notForThisProbe() => throw UnimplementedError(
    '本组判据只验预取调度；解码路请用 image_surface_page_turn_test.dart 那一组',
  );

  @override
  List<PageRef> get pages => _notForThisProbe();

  @override
  RasterTargetRef? rasterTargetFor(int index) => _notForThisProbe();

  @override
  Future<PageLoadOutcome> load(
    int index, {
    int? targetWidth,
    PageLoadIntent intent = PageLoadIntent.interactive,
  }) => _notForThisProbe();

  @override
  Future<void> close() async {}

  @override
  Future<String?> getPageFilePath(int index) => _notForThisProbe();

  @override
  Future<Uint8List?> getPageBytes(int index) => _notForThisProbe();
}

/// 只实现「邻页预取」这一个动作的呈现器。
///
/// `prepareNeighbor` 的**返回值就是**这条机制的全部对外契约：接受（true）或
/// 落空（false）。所以这里把它做成可配置的，并把每次调用的入参记下来。
class _FakePresenter extends GpuPresentController {
  /// 每次 `prepareNeighbor` 的入参，按调用顺序记下来。
  final List<({int index, int width, int height})> prepares =
      <({int index, int width, int height})>[];

  /// 下一次 `prepareNeighbor` 回什么。
  bool accepted = true;

  /// 模拟「当前页正在上屏」。
  ///
  /// 这是**唯一**该被避开的争用：macOS 上 `show` / `prepare` / `open` 共用一条
  /// 串行队列（`GpuPresentBridgeMac` 的 `workerQueue`），一次 `prepare` 会实实在在地
  /// 排在当前页 `show` 前面。注意别把它错写成"还没有完成帧"——
  /// `present()` 一开头就把完成帧清成 null，那个信号在每次翻页后都会为真。
  bool busy = false;

  @override
  bool get isPresenting => busy;

  @override
  Future<bool> prepareNeighbor({
    required PageSource source,
    required int index,
    required Size physicalSize,
  }) async {
    prepares.add((
      index: index,
      width: physicalSize.width.round(),
      height: physicalSize.height.round(),
    ));
    return accepted;
  }
}

Widget _host(PageSource source, int index, GpuPresentController presenter) =>
    MaterialApp(
      home: Scaffold(
        body: NeighborPagePrefetch(
          source: source,
          index: index,
          presenter: presenter,
        ),
      ),
    );

void main() {
  testWidgets('按控件的**物理**尺寸请求预取，且同一目标只发一次', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final source = _FakeSource();
    final presenter = _FakePresenter();
    addTearDown(presenter.dispose);

    await tester.pumpWidget(_host(source, 1, presenter));
    await tester.pump();
    await tester.pump();

    // 逻辑尺寸是 400×300。给逻辑尺寸的话，预渲染帧与 `show` 的物理目标会差
    // 整整一倍 —— 而命中的容差只有 ±3 px，于是"预取了"却永远 miss。
    expect(presenter.prepares, hasLength(1));
    expect(presenter.prepares.single.index, 1);
    expect(presenter.prepares.single.width, 800);
    expect(presenter.prepares.single.height, 600);

    // 这个节点每次布局都会被回调一次；不去重就是每帧一次跨语言往返。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(presenter.prepares, hasLength(1), reason: '同一个目标被重复请求了');
  });

  testWidgets('一次落空会重试，间隔要短于连翻的间隔（不是"发过就算了"）', (tester) async {
    final source = _FakeSource();
    final presenter = _FakePresenter();
    addTearDown(presenter.dispose);
    // 「呈现器还没 open 过 / 还在后台建」都会让第一次尝试落空，而那两件事
    // 都是**暂时**的。从前这里一次落空就永久放弃，等于把这个机制整个废掉。
    presenter.accepted = false;

    await tester.pumpWidget(_host(source, 1, presenter));
    await tester.pump();
    await tester.pump();
    expect(presenter.prepares, hasLength(1));

    await tester.pump(const Duration(milliseconds: 100));
    expect(presenter.prepares, hasLength(2), reason: '一次落空就放弃 = 预取只体现在日志里');

    // 间隔若是 250 ms 级，重试点会整段落在"用户已经翻走"之后 —— 而连翻时每页只停
    // 两三百毫秒、一次 `prepare` 本身就要 200–300 ms，于是永远追不上。
    // 这里钉住"紧跟着就来第二次"，而不是一个固定的长间隔。
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      presenter.prepares,
      hasLength(3),
      reason: '重试得比连翻的间隔更密，否则每一页都追不上',
    );

    // 30 次重试 × 100 ms = 3 s，与 Rust 侧预取 backstop 同一个量级。
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      presenter.prepares,
      hasLength(31),
      reason: '首次 + 上限 30 次重试；再多就是死循环了',
    );

    // 停手之后不能留下还活着的定时器（否则 widget 都拆了它还会再发一次）。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('当前页正在上屏时不插队，上屏结束后同一轮重试接上', (tester) async {
    final source = _FakeSource();
    final presenter = _FakePresenter()..busy = true;
    addTearDown(presenter.dispose);

    await tester.pumpWidget(_host(source, 1, presenter));
    await tester.pump();
    await tester.pump();

    // macOS 上 `prepare` 与当前页的 `show` 共用一条串行队列，插进去就是把翻页
    // 整整推迟一个全尺寸解码的时间。所以上屏期间一次都不发。
    expect(presenter.prepares, isEmpty, reason: '画面还在上屏就去插队，翻页会更慢');

    presenter.busy = false;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(presenter.prepares, hasLength(1), reason: '上屏结束后，同一轮重试要接上');
  });

  testWidgets('预取被接受后就不再重试', (tester) async {
    final source = _FakeSource();
    final presenter = _FakePresenter();
    addTearDown(presenter.dispose);
    presenter.accepted = true;

    await tester.pumpWidget(_host(source, 1, presenter));
    await tester.pump();
    await tester.pump();
    expect(presenter.prepares, hasLength(1));

    await tester.pump(const Duration(seconds: 5));
    expect(presenter.prepares, hasLength(1), reason: '已经备好了还反复发，就是白烧 CPU');
  });

  testWidgets('换页后按新的一页重新发', (tester) async {
    final source = _FakeSource();
    final presenter = _FakePresenter();
    addTearDown(presenter.dispose);

    await tester.pumpWidget(_host(source, 1, presenter));
    await tester.pump();
    await tester.pump();
    expect(presenter.prepares.map((p) => p.index), <int>[1]);

    // 翻页之后这个 slot 的邻页身份换了，去重键必须跟着换。
    await tester.pumpWidget(_host(source, 2, presenter));
    await tester.pump();
    await tester.pump();
    expect(presenter.prepares.map((p) => p.index), <int>[1, 2]);
  });
}
