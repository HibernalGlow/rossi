/// 归因层：把 Dart 账本、Rust 账本、帧统计合成一张「时间掉在哪」的排名表。
///
/// 这一层刻意**不 import FRB 生成物** —— Rust 侧数据以 [RustPerfRow] 这种中立形状注入，
/// 由调用方（调试页）负责适配。好处有两个：归因逻辑能脱离 App 单测，
/// 以及 FRB 重新生成时不会连带编译失败。
///
/// 三个核心推导：
///
/// 1. **自耗时**：标签用 `.` 分段表达父子，父行减去**直接**子行的累计即得自耗时。
///    只减直接子层，否则孙层会被减两次。
/// 2. **过桥成本**：Dart 与 Rust 上的**同名标签**相减。Dart 是墙钟（含 isolate 排队、
///    FRB 序列化、大块内存拷贝），Rust 是自线程内的计算时长，差值就是跨语言那一程。
/// 3. **严重度**：一组阈值规则，每条都必须带着「触发它的那个实测数字」出报告。
///    没有数字的结论不写。
library;

import 'package:zephyr/perf/perf_ledger.dart';

/// 注入用的 Rust 侧行。字段与 `crate::perf::PerfEntry` 一一对应。
class RustPerfRow {
  const RustPerfRow({
    required this.label,
    required this.count,
    required this.totalUs,
    required this.avgUs,
    required this.maxUs,
    required this.minUs,
    required this.bytes,
  });

  final String label;
  final int count;
  final int totalUs;
  final int avgUs;
  final int maxUs;
  final int minUs;
  final int bytes;
}

enum PerfSide { dart, rust }

/// 排名表里的一行。`totalUs` 是**含子调用**的累计，`selfUs` 是扣掉直接子调用后的净耗时。
class PerfRow {
  PerfRow({
    required this.label,
    required this.side,
    required this.count,
    required this.totalUs,
    required this.avgUs,
    required this.maxUs,
    required this.minUs,
    required this.bytes,
    required this.selfUs,
    required this.shareOfTotal,
    this.bridgeUs,
    this.negativeSelf = false,
  });

  final String label;
  final PerfSide side;
  final int count;
  final int totalUs;
  final int avgUs;
  final int maxUs;
  final int minUs;
  final int bytes;
  final int selfUs;

  /// 占本侧全部自耗时的比例。父行不再重复计入，所以各行的分母一致、可以直接相加。
  final double shareOfTotal;

  /// 仅当同名标签在 Dart 与 Rust 两边都存在时非空：Dart 墙钟减 Rust 计算。
  final int? bridgeUs;

  /// 自耗时算出负数说明埋点写错了（父子标签重叠、或同名标签在两侧语义不同）。
  /// 如实标出来，不夹成 0 —— 夹成 0 会把 bug 藏成一个看起来合理的表。
  final bool negativeSelf;

  bool get isHot => shareOfTotal >= 0.15;

  /// 人类可读的字节数。0 显示「—」而不是「0 B」，因为多数标签根本不记字节。
  String get bytesText => bytes == 0 ? '—' : _humanBytes(bytes);

  String get periodText => count == 0 ? '—' : '${(totalUs / count / 1000).toStringAsFixed(2)} ms';
}

/// 一条归因结论。必须带证据数字，[detail] 里不含「可能」「大概」这类无测量的措辞。
class PerfFinding {
  const PerfFinding({
    required this.title,
    required this.detail,
    required this.severity,
  });

  final String title;
  final String detail;
  final PerfSeverity severity;
}

enum PerfSeverity { critical, warning, note }

/// 帧统计的注入形状（同样为了不与 monitor 的引擎依赖绑死，方便单测）。
class FrameInput {
  const FrameInput({
    required this.frames,
    required this.jankyFrames,
    required this.severeFrames,
    required this.buildLimitedJank,
    required this.rasterLimitedJank,
    required this.stallFrames,
    required this.maxGapUs,
    required this.maxBuildUs,
    required this.maxRasterUs,
    this.refreshPeriodUs,
  });

  final int frames;
  final int jankyFrames;
  final int severeFrames;
  final int buildLimitedJank;
  final int rasterLimitedJank;
  final int stallFrames;
  final int maxGapUs;
  final int maxBuildUs;
  final int maxRasterUs;
  final int? refreshPeriodUs;
}

class PerfReport {
  PerfReport({
    required this.dartRows,
    required this.rustRows,
    required this.frames,
  });

  final List<PerfRow> dartRows;
  final List<PerfRow> rustRows;
  final FrameInput? frames;

  List<PerfRow> get allRows => [...dartRows, ...rustRows]
    ..sort((a, b) => b.selfUs.compareTo(a.selfUs));

  factory PerfReport.build({
    required Map<String, PerfBucket> dartBuckets,
    required List<RustPerfRow> rustRows,
    FrameInput? frames,
  }) {
    return PerfReport(
      dartRows: _rankSide(
        {
          for (final b in dartBuckets.values)
            b.label: (
              count: b.count,
              totalUs: b.totalUs,
              avgUs: b.avgUs,
              maxUs: b.maxUs,
              minUs: b.minUsOrZero,
              bytes: b.bytes,
            ),
        },
        PerfSide.dart,
        counterpartTotals: _totalsOf(rustRows),
      ),
      rustRows: _rankSide(
        {
          for (final r in rustRows)
            r.label: (
              count: r.count,
              totalUs: r.totalUs,
              avgUs: r.avgUs,
              maxUs: r.maxUs,
              minUs: r.minUs,
              bytes: r.bytes,
            ),
        },
        PerfSide.rust,
        counterpartTotals: {
          for (final b in dartBuckets.values) b.label: b.totalUs,
        },
      ),
      frames: frames,
    );
  }

  /// 归因结论。顺序即严重度顺序，调试页直接照这个顺序渲染。
  List<PerfFinding> findings() {
    final out = <PerfFinding>[];

    for (final row in allRows.take(6)) {
      if (row.shareOfTotal < 0.2) continue;
      out.add(PerfFinding(
        title: '${row.side == PerfSide.rust ? 'Rust' : 'Dart'} 侧自耗时第一梯队：${row.label}',
        detail: '自耗时 ${_ms(row.selfUs)}，占本侧 ${(_sharePct(row.shareOfTotal))}%，'
            '共 ${row.count} 次、单次均 ${row.periodText}、最慢一次 ${_ms(row.maxUs)}。',
        severity: row.avgUs > 100_000
            ? PerfSeverity.critical
            : PerfSeverity.warning,
      ));
    }

    // 过桥：差值只在两边都有同名标签时才成立。
    final bridges = [
      ...dartRows,
      ...rustRows,
    ].where((r) => r.bridgeUs != null && r.bridgeUs! > 0).toList()
      ..sort((a, b) => b.bridgeUs!.compareTo(a.bridgeUs!));
    for (final row in bridges.take(3)) {
      final ratio = row.totalUs == 0 ? 0.0 : row.bridgeUs! / row.totalUs;
      if (ratio < 0.3) continue;
      out.add(PerfFinding(
        title: '过桥成本高于计算本身：${row.label}',
        detail: 'Dart 墙钟减 Rust 计算 = ${_ms(row.bridgeUs!)}，占该标签 ${_sharePct(ratio)}%。'
            '剩下那段才是真在算。${row.bytes == 0 ? '' : '同标签跨桥字节 ${row.bytesText}。'}',
        severity: PerfSeverity.critical,
      ));
    }

    // 单次就慢的调用 —— 比累计占比更能解释「点一下要等一下」。
    final slowOnce = [...dartRows, ...rustRows]
        .where((r) => r.count > 0)
        .toList()
      ..sort((a, b) => b.avgUs.compareTo(a.avgUs));
    for (final row in slowOnce.take(4)) {
      if (row.avgUs < 50_000) break;
      out.add(PerfFinding(
        title: '单次响应慢：${row.label}',
        detail: '平均 ${row.periodText}，最慢 ${_ms(row.maxUs)}，共 ${row.count} 次。'
            '累计占比只有 ${_sharePct(row.shareOfTotal)}%，所以它在总表里不显眼，'
            '但它落在交互路径上就是手感的延迟。',
        severity: PerfSeverity.critical,
      ));
    }

    final f = frames;
    if (f != null && f.frames > 30) {
      final period = f.refreshPeriodUs;
      if (period == null) {
        out.add(const PerfFinding(
          title: '刷新周期没推出来，掉帧判定被跳过',
          detail: '相邻帧间隔的中位数落在 4–40ms 之外，说明采样窗口里没有稳定画面节奏'
              '（多半是静止很久后的一次性出帧）。此时不判超标，别把空白当「不掉帧」。',
          severity: PerfSeverity.note,
        ));
      } else if (f.jankyFrames > 0) {
        final rasterWorst = f.rasterLimitedJank >= f.buildLimitedJank;
        out.add(PerfFinding(
          title: rasterWorst ? '掉帧卡在光栅线程' : '掉帧卡在 UI 线程',
          detail: '${f.frames} 帧里 ${f.jankyFrames} 帧超标（${_sharePct(f.jankyFrames / f.frames)}%），'
              '严重超标 ${f.severeFrames} 帧。按预算 ${(period / 1000).toStringAsFixed(1)} ms 算：'
              'build 受限 ${f.buildLimitedJank} 帧 / raster 受限 ${f.rasterLimitedJank} 帧。'
              '最慢 build ${_ms(f.maxBuildUs)}、最慢 raster ${_ms(f.maxRasterUs)}。',
          severity: f.jankyFrames / f.frames > 0.1 ? PerfSeverity.critical : PerfSeverity.warning,
        ));
      }
      if (f.stallFrames > 0) {
        out.add(PerfFinding(
          title: '有一段完全没出帧（不是慢帧，是停帧）',
          detail: '${f.stallFrames} 次的相邻帧间隔超过预算 4 倍，最长 ${_ms(f.maxGapUs)}。'
              '这类通常是主 isolate 被一件同步的事占住 —— 去账本里找单次均耗时最高那条同步标签。',
          severity: PerfSeverity.critical,
        ));
      }
    }

    for (final row in allRows) {
      if (!row.negativeSelf) continue;
      out.add(PerfFinding(
        title: '埋点自相矛盾：${row.label}',
        detail: '自耗时算出负值（${_ms(row.selfUs)}），即直接子标签的累计超过了父标签。'
            '要么父子命名重叠，要么同名标签在两侧的语义不一样。这一行的排名不可信。',
        severity: PerfSeverity.note,
      ));
    }

    if (out.isEmpty) {
      out.add(PerfFinding(
        title: '没有可报告的瓶颈',
        detail: 'Dart ${dartRows.length} 条 / Rust ${rustRows.length} 条标签，'
            '没有任何一条自耗时占比过 20%、单次均耗过 50ms、或超预算 4 倍的停帧。'
            '这不代表没开销，代表当前采样窗口内它不显著 —— 去操作一轮再刷新。',
        severity: PerfSeverity.note,
      ));
    }
    return out;
  }

  static Map<String, int> _totalsOf(List<RustPerfRow> rows) =>
      {for (final r in rows) r.label: r.totalUs};

  /// 把一侧的扁平累计算成带自耗时与占比的排名行。
  static List<PerfRow> _rankSide(
    Map<String, ({
      int count,
      int totalUs,
      int avgUs,
      int maxUs,
      int minUs,
      int bytes,
    })> flat,
    PerfSide side, {
    required Map<String, int> counterpartTotals,
  }) {
    final directChildren = _directChildrenOf(flat.keys);

    final selfOf = <String, int>{};
    final negative = <String, bool>{};
    for (final entry in flat.entries) {
      var self = entry.value.totalUs;
      for (final child in directChildren[entry.key] ?? const <String>[]) {
        self -= flat[child]!.totalUs;
      }
      selfOf[entry.key] = self;
      negative[entry.key] = self < 0;
    }

    // 分母用「全部自耗时之和」，且夹掉负值带来的误差：父行不重复计入，
    // 所以各行的占比可以相加，读者才不会被「每行都很大」骗到。
    final denom = selfOf.values.where((v) => v > 0).fold<int>(0, (a, b) => a + b);

    final rows = <PerfRow>[];
    for (final entry in flat.entries) {
      final label = entry.key;
      final v = entry.value;
      final counterpartTotal = counterpartTotals[label];
      rows.add(PerfRow(
        label: label,
        side: side,
        count: v.count,
        totalUs: v.totalUs,
        avgUs: v.avgUs,
        maxUs: v.maxUs,
        minUs: v.minUs,
        bytes: v.bytes,
        selfUs: selfOf[label]!,
        shareOfTotal: denom == 0 ? 0 : selfOf[label]! / denom,
        // 过桥差值只在 Dart 行上报一次（Dart 墙钟减 Rust 计算），且要求对面
        // 确有同名标签 —— 对面没有就不能凭空造一个差值。
        bridgeUs: side == PerfSide.dart && counterpartTotal != null
            ? v.totalUs - counterpartTotal
            : null,
        negativeSelf: negative[label]!,
      ));
    }
    rows.sort((a, b) => b.selfUs.compareTo(a.selfUs));
    return rows;
  }

  /// label -> 它的**直接**子标签列表（多一层且中间不含 `.`）。
  static Map<String, List<String>> _directChildrenOf(Iterable<String> labels) {
    final all = labels.toList();
    final map = <String, List<String>>{};
    for (final parent in all) {
      final prefix = '$parent.';
      for (final child in all) {
        if (child == parent || !child.startsWith(prefix)) continue;
        final rest = child.substring(prefix.length);
        if (rest.isEmpty || rest.contains('.')) continue;
        map.putIfAbsent(parent, () => []).add(child);
      }
    }
    return map;
  }
}

String _ms(int us) => '${(us / 1000).toStringAsFixed(1)} ms';
String _sharePct(double ratio) => (ratio * 100).toStringAsFixed(1);

String _humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  double v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i += 1;
  }
  return '${v.toStringAsFixed(1)} ${units[i]}';
}
