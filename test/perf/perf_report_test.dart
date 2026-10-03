/// 归因层的算术验证：自耗时、占比、过桥差值、以及每条结论的触发条件。
///
/// 这里必须同时有**阳性对照**（违规输入一定要红）和**阴性对照**（干净输入不许报瓶颈），
/// 否则阈值规则会退化成「永远有一堆结论」，读的人就学不会信它。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/perf/perf.dart';

PerfBucket bucket(String label, int totalUs, {int? bytes, int times = 1}) {
  final b = PerfBucket(label);
  final each = totalUs ~/ times;
  for (var i = 0; i < times; i++) {
    b.add(i == times - 1 ? totalUs - each * (times - 1) : each, byteCount: bytes ?? 0);
  }
  return b;
}

RustPerfRow rustRow(
  String label, {
  required int totalUs,
  int count = 1,
  int bytes = 0,
}) {
  return RustPerfRow(
    label: label,
    count: count,
    totalUs: totalUs,
    avgUs: count == 0 ? 0 : totalUs ~/ count,
    maxUs: totalUs,
    minUs: totalUs,
    bytes: bytes,
  );
}

PerfRow? rowOf(PerfReport r, String label, PerfSide side) {
  final rows = side == PerfSide.dart ? r.dartRows : r.rustRows;
  for (final e in rows) {
    if (e.label == label) return e;
  }
  return null;
}

void main() {
  group('自耗时按前缀相减', () {
    test('父行只减去直接子行', () {
      final report = PerfReport.build(
        dartBuckets: {
          'a': bucket('a', 1000),
          'a.b': bucket('a.b', 600),
          'a.c': bucket('a.c', 200),
        },
        rustRows: const [],
      );
      expect(rowOf(report, 'a', PerfSide.dart)!.selfUs, 200);
      expect(rowOf(report, 'a.b', PerfSide.dart)!.selfUs, 600);
    });

    test('孙层不被减两次', () {
      final report = PerfReport.build(
        dartBuckets: {
          'a': bucket('a', 1000),
          'a.b': bucket('a.b', 600),
          'a.b.c': bucket('a.b.c', 400),
        },
        rustRows: const [],
      );
      expect(rowOf(report, 'a', PerfSide.dart)!.selfUs, 400,
          reason: 'a 的直接子只有 a.b，孙 a.b.c 由 a.b 自己去减');
      expect(rowOf(report, 'a.b', PerfSide.dart)!.selfUs, 200);
      expect(rowOf(report, 'a.b.c', PerfSide.dart)!.selfUs, 400);
    });

    test('子累计超过父时标为埋点矛盾，不夹成 0', () {
      final report = PerfReport.build(
        dartBuckets: {
          'x': bucket('x', 100),
          'x.y': bucket('x.y', 900),
        },
        rustRows: const [],
      );
      final x = rowOf(report, 'x', PerfSide.dart)!;
      expect(x.negativeSelf, isTrue);
      expect(x.selfUs, -800, reason: '负值要原样露出来，夹成 0 就把 bug 藏进合理外观里');
      expect(
        report.findings().any((f) => f.title.contains('埋点自相矛盾')),
        isTrue,
      );
    });

    test('占比分母是自耗时之和，父行不重复计入', () {
      final report = PerfReport.build(
        dartBuckets: {
          'a': bucket('a', 1000),
          'a.b': bucket('a.b', 1000),
        },
        rustRows: const [],
      );
      // 自耗时：a=0，a.b=1000 → 分母 1000。
      expect(rowOf(report, 'a.b', PerfSide.dart)!.shareOfTotal, closeTo(1.0, 1e-9));
      expect(rowOf(report, 'a', PerfSide.dart)!.shareOfTotal, closeTo(0.0, 1e-9));
    });
  });

  group('过桥差值', () {
    test('同名标签两边都有才产生，且等于 Dart 墙钟减 Rust 计算', () {
      final report = PerfReport.build(
        dartBuckets: {'frb.page': bucket('frb.page', 1000)},
        rustRows: [rustRow('frb.page', totalUs: 300)],
      );
      expect(rowOf(report, 'frb.page', PerfSide.dart)!.bridgeUs, 700);
      expect(rowOf(report, 'frb.page', PerfSide.rust)!.bridgeUs, isNull,
          reason: '同一个差值只报一次，不两侧各报一遍');
    });

    test('对面没有同名标签时不凭空造差值', () {
      final report = PerfReport.build(
        dartBuckets: {'only.dart': bucket('only.dart', 500)},
        rustRows: const [],
      );
      expect(rowOf(report, 'only.dart', PerfSide.dart)!.bridgeUs, isNull);
    });

    test('差值低于三成不报「过桥比计算贵」', () {
      final report = PerfReport.build(
        dartBuckets: {'frb.page': bucket('frb.page', 1000)},
        rustRows: [rustRow('frb.page', totalUs: 800)],
      );
      expect(
        report.findings().any((f) => f.title.contains('过桥成本高于计算本身')),
        isFalse,
        reason: '桥占 20%，此时瓶颈确实在 Rust 计算里，不该喊过桥',
      );
    });

    test('差值过半必须报（阳性对照）', () {
      final report = PerfReport.build(
        dartBuckets: {'frb.page': bucket('frb.page', 1000)},
        rustRows: [rustRow('frb.page', totalUs: 200, bytes: 0)],
      );
      expect(
        report.findings().any((f) => f.title.contains('过桥成本高于计算本身')),
        isTrue,
      );
    });
  });

  group('帧判据', () {
    FrameInput frames({
      int period = 16_667,
      int janky = 0,
      int severe = 0,
      int buildLimited = 0,
      int rasterLimited = 0,
      int stalls = 0,
      int maxGapUs = 0,
      int count = 300,
    }) {
      return FrameInput(
        frames: count,
        jankyFrames: janky,
        severeFrames: severe,
        buildLimitedJank: buildLimited,
        rasterLimitedJank: rasterLimited,
        stallFrames: stalls,
        maxGapUs: maxGapUs,
        maxBuildUs: 0,
        maxRasterUs: 0,
        refreshPeriodUs: period,
      );
    }

    PerfReport withFrames(FrameInput? f) => PerfReport.build(
          dartBuckets: const {},
          rustRows: const [],
          frames: f,
        );

    test('raster 占多数时结论指向光栅线程', () {
      final report = withFrames(frames(
        janky: 40,
        buildLimited: 5,
        rasterLimited: 35,
      ));
      final f = report.findings().firstWhere((e) => e.title.contains('掉帧卡在'));
      expect(f.title, contains('光栅'));
    });

    test('build 占多数时结论指向 UI 线程', () {
      final report = withFrames(frames(
        janky: 40,
        buildLimited: 35,
        rasterLimited: 5,
      ));
      final f = report.findings().firstWhere((e) => e.title.contains('掉帧卡在'));
      expect(f.title, contains('UI 线程'));
    });

    test('停帧与慢帧分开报', () {
      final report = withFrames(frames(stalls: 3, maxGapUs: 400_000));
      expect(
        report.findings().any((f) => f.title.contains('没出帧')),
        isTrue,
      );
    });

    test('推不出刷新周期时明说判定被跳过，不许显示成不掉帧', () {
      // 传 null 而不是 0：monitor 只会给出夹在 4–40ms 的中位数或 null，
      // 造一个 0 出来等于给不可能发生的输入做校验。
      final report = PerfReport.build(
        dartBuckets: const {},
        rustRows: const [],
        frames: FrameInput(
          frames: 300,
          jankyFrames: 0,
          severeFrames: 0,
          buildLimitedJank: 0,
          rasterLimitedJank: 0,
          stallFrames: 0,
          maxGapUs: 20_000,
          maxBuildUs: 0,
          maxRasterUs: 0,
        ),
      );
      expect(
        report.findings().any((f) => f.title.contains('掉帧判定被跳过')),
        isTrue,
      );
      expect(
        report.findings().any((f) => f.title.contains('掉帧卡在')),
        isFalse,
      );
    });

    test('样本太少时完全不参与帧结论', () {
      final report = withFrames(frames(count: 10, janky: 9));
      expect(report.findings().where((f) => f.title.contains('帧')), isEmpty);
    });
  });

  group('阈值规则', () {
    test('单次均耗过 50ms 要报，与累计占比无关', () {
      final report = PerfReport.build(
        dartBuckets: {
          'a.lot': bucket('a.lot', 9_000_000, times: 900), // 单次 10ms，累计巨大
          'jump.seek': bucket('jump.seek', 200_000, times: 2), // 单次 100ms，累计小
        },
        rustRows: const [],
      );
      final f = report.findings().where((e) => e.title.contains('单次响应慢'));
      expect(f.map((e) => e.title), contains(contains('jump.seek')));
    });

    test('占比过两成要进第一梯队', () {
      final report = PerfReport.build(
        dartBuckets: {
          'dominant': bucket('dominant', 8_000_000),
          'minor': bucket('minor', 100_000),
        },
        rustRows: const [],
      );
      // 只看「第一梯队」这一条规则：minor 的 100ms 均耗会被另一条
      // 「单次响应慢」合法命中，混在一起断言就测不到占比规则本身。
      final tier = report.findings()
          .where((f) => f.title.contains('自耗时第一梯队'))
          .map((f) => f.title)
          .toList();
      expect(tier, contains(contains('dominant')));
      expect(tier, isNot(contains(contains('minor'))));
    });

    test('干净输入不报瓶颈（阴性对照）', () {
      // 刻意摊平：6 条各占 1/6 自耗时（16.7%），没有一条过 20% 阈值；
      // 单次均耗 1ms，离 50ms 的交互阈值很远。
      // 上一版这里写的是「a 占 60%」，那本身就是个真瓶颈，当不了阴性对照。
      final report = PerfReport.build(
        dartBuckets: {
          for (var i = 0; i < 6; i++)
            'flat.$i': bucket('flat.$i', 100_000, times: 100),
        },
        rustRows: const [],
        frames: FrameInput(
          frames: 500,
          jankyFrames: 0,
          severeFrames: 0,
          buildLimitedJank: 0,
          rasterLimitedJank: 0,
          stallFrames: 0,
          maxGapUs: 20_000,
          maxBuildUs: 3_000,
          maxRasterUs: 4_000,
          refreshPeriodUs: 16_667,
        ),
      );
      final f = report.findings();
      expect(f, hasLength(1), reason: '只该剩那一条「不显著」的说明');
      expect(f.single.title, contains('没有可报告的瓶颈'));
      expect(f.single.severity, PerfSeverity.note);
    });
  });

  group('排名', () {
    test('allRows 按自耗时降序，父行不压过子行', () {
      final report = PerfReport.build(
        dartBuckets: {
          'a': bucket('a', 1000),
          'a.b': bucket('a.b', 900),
        },
        rustRows: const [],
      );
      expect(report.allRows.first.label, 'a.b');
    });

    test('字节数只在记了的行显示', () {
      final report = PerfReport.build(
        dartBuckets: {
          'with.bytes': bucket('with.bytes', 1000, bytes: 5 * 1024 * 1024),
          'no.bytes': bucket('no.bytes', 1000),
        },
        rustRows: const [],
      );
      expect(rowOf(report, 'with.bytes', PerfSide.dart)!.bytesText, contains('MB'));
      expect(rowOf(report, 'no.bytes', PerfSide.dart)!.bytesText, '—');
    });
  });
}
