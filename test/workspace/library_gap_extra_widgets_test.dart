import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_extra_widgets.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_widgets.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

/// 6 款追加组件的 id / 下限尺寸（与需求规格一一对应，顺序即优先级）。
const List<({String id, double minWidth, double minHeight})> _expected = [
  (id: 'gap_completion', minWidth: 104, minHeight: 70),
  (id: 'gap_heatmap', minWidth: 132, minHeight: 86),
  (id: 'gap_weekday', minWidth: 116, minHeight: 74),
  (id: 'gap_span', minWidth: 112, minHeight: 66),
  (id: 'gap_unread', minWidth: 100, minHeight: 66),
  (id: 'gap_milestone', minWidth: 104, minHeight: 62),
];

/// 一条带齐时间、进度、标签、页数与体积的条目。
///
/// 时间全部相对于 [base]（默认「现在」）构造，测试不依赖具体日期文案。
LibraryEntry _entry(int index, {DateTime? base}) {
  final anchor = base ?? DateTime.now();
  final progress = switch (index % 5) {
    0 => 1.0,
    1 => 0.6,
    2 => 0.3,
    3 => null,
    _ => 0.0,
  };
  return LibraryEntry(
    key: 'e$index',
    title: '[社团$index] 作品标题 $index',
    subtitle: '本地 · P.${index + 3}',
    tags: ['#Pixiv', if (index.isEven) '#Cosplay'],
    timestamp: anchor.subtract(Duration(days: index * 5)),
    progress: progress,
    reading: index % 5 == 1,
    section: index.isEven ? '本地' : '插件',
    itemCount: 12 + index,
    byteSize: 1024 * 1024 * (index + 1),
  );
}

List<LibraryEntry> _sampleEntries() => [for (var i = 0; i < 12; i++) _entry(i)];

LibraryEntry _timed(int index, {double? progress = .5, bool? reading}) =>
    LibraryEntry(
      key: 't$index',
      title: 'T$index',
      timestamp: DateTime(2024, 1, 1).add(Duration(days: index)),
      progress: progress,
      reading: reading,
    );

LibraryGapSample _sample(List<LibraryEntry> entries, Size size) =>
    LibraryGapSample(
      entries: entries,
      slot: LibraryGapSlot(
        row: 0,
        tile: 0,
        columnStart: 0,
        span: 1,
        width: size.width,
        height: size.height,
      ),
      seed: 17,
    );

bool _accepts(
  LibraryGapWidgetSpec spec,
  List<LibraryEntry> entries, {
  Size size = const Size(180, 112),
}) => spec.accepts!(_sample(entries, size));

Future<void> _pumpSpec(
  WidgetTester tester,
  LibraryGapWidgetSpec spec,
  LibraryGapSample sample,
  Size size, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4E6A8F)),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Builder(builder: (context) => spec.builder(context, sample)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    tester.takeException(),
    isNull,
    reason: '${spec.id} @ ${size.width}x${size.height} scale $textScale',
  );
}

void main() {
  group('清单', () {
    test('6 款、顺序与下限尺寸符合规格，id 唯一且 label/glyph 齐备', () {
      final kit = extraLibraryGapWidgets();
      expect(kit, hasLength(_expected.length));
      expect(kit.map((s) => s.id).toList(), [
        for (final item in _expected) item.id,
      ]);
      expect(kit.map((s) => s.id).toSet(), hasLength(kit.length));
      for (final item in _expected) {
        final spec = kit.firstWhere((s) => s.id == item.id);
        expect(spec.label, isNotEmpty, reason: item.id);
        expect(spec.glyph, isNotNull, reason: item.id);
        expect(spec.minWidth, item.minWidth, reason: item.id);
        expect(spec.minHeight, item.minHeight, reason: item.id);
        expect(spec.accepts, isNotNull, reason: item.id);
        expect(spec.minWidth, greaterThanOrEqualTo(96), reason: item.id);
        expect(spec.minHeight, greaterThanOrEqualTo(56), reason: item.id);
      }
    });

    test('清单不可变：调用方改不动内置顺序', () {
      final kit = extraLibraryGapWidgets();
      expect(() => kit.add(kit.first), throwsUnsupportedError);
    });
  });

  group('接受条件', () {
    final kit = extraLibraryGapWidgets();
    LibraryGapWidgetSpec spec(String id) => kit.firstWhere((s) => s.id == id);

    test('空墙：6 款全部不接受', () {
      for (final item in kit) {
        expect(_accepts(item, const []), isFalse, reason: item.id);
      }
    });

    test('没有时间戳：热力 / 星期 / 跨度三款拒绝，进度类照常', () {
      final entries = [
        for (var i = 0; i < 6; i++)
          LibraryEntry(key: 'n$i', title: 'N$i', progress: .4),
      ];
      expect(_accepts(spec('gap_heatmap'), entries), isFalse);
      expect(_accepts(spec('gap_weekday'), entries), isFalse);
      expect(_accepts(spec('gap_span'), entries), isFalse);
      expect(_accepts(spec('gap_completion'), entries), isTrue);
      expect(_accepts(spec('gap_unread'), entries), isFalse);
      expect(_accepts(spec('gap_milestone'), entries), isTrue);
    });

    test('时间戳数量边界：热力 / 星期要 5 条，跨度要 2 条', () {
      expect(_accepts(spec('gap_span'), [_timed(0)]), isFalse);
      expect(_accepts(spec('gap_span'), [_timed(0), _timed(1)]), isTrue);
      expect(
        _accepts(spec('gap_heatmap'), [for (var i = 0; i < 4; i++) _timed(i)]),
        isFalse,
      );
      final five = [for (var i = 0; i < 5; i++) _timed(i)];
      expect(_accepts(spec('gap_heatmap'), five), isTrue);
      expect(_accepts(spec('gap_weekday'), five), isTrue);
      // 无时间戳的条目不算进 5 条，但仍是「条目数」。
      final mix = [...five, const LibraryEntry(key: 'x', title: 'X')];
      expect(_accepts(spec('gap_heatmap'), mix), isTrue);
    });

    test('全部没有进度：收官进度拒绝、待读存量接受', () {
      final entries = [
        for (var i = 0; i < 6; i++)
          LibraryEntry(
            key: 'u$i',
            title: 'U$i',
            timestamp: _timed(i).timestamp,
          ),
      ];
      expect(_accepts(spec('gap_completion'), entries), isFalse);
      expect(_accepts(spec('gap_unread'), entries), isTrue);
    });

    test('全部读完：收官进度接受、待读存量拒绝', () {
      final entries = [
        for (var i = 0; i < 6; i++)
          LibraryEntry(
            key: 'f$i',
            title: 'F$i',
            progress: 1,
            timestamp: _timed(i).timestamp,
          ),
      ];
      expect(_accepts(spec('gap_completion'), entries), isTrue);
      expect(_accepts(spec('gap_unread'), entries), isFalse);
    });

    test('里程碑要 5 条，且与时间戳无关', () {
      expect(
        _accepts(spec('gap_milestone'), [
          for (var i = 0; i < 4; i++) _timed(i),
        ]),
        isFalse,
      );
      expect(
        _accepts(spec('gap_milestone'), [
          for (var i = 0; i < 5; i++) _timed(i),
        ]),
        isTrue,
      );
      final untimed = [
        for (var i = 0; i < 5; i++) LibraryEntry(key: 'z$i', title: 'Z$i'),
      ];
      expect(_accepts(spec('gap_milestone'), untimed), isTrue);
    });
  });

  group('helper 边界', () {
    test('收官三档：读完 / 在读 / 未读不重不漏', () {
      final entries = [
        LibraryEntry(key: 'a', title: 'A', progress: 1),
        LibraryEntry(key: 'b', title: 'B', progress: .4, reading: true),
        LibraryEntry(key: 'c', title: 'C', progress: .4),
        LibraryEntry(key: 'd', title: 'D'),
        LibraryEntry(key: 'e', title: 'E', progress: 0, reading: true),
        LibraryEntry(key: 'f', title: 'F', progress: 1, reading: true),
      ];
      final tiers = gapCompletionTiers(entries);
      expect(tiers.finished, 2);
      expect(tiers.reading, 2);
      expect(tiers.unread, 2);
      expect(tiers.finished + tiers.reading + tiers.unread, entries.length);
      expect(gapCompletionTiers(const []), (
        finished: 0,
        reading: 0,
        unread: 0,
      ));
    });

    test('热力桶：56 格、最后一格是今天、窗口外的旧记录不计', () {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final counts = gapHeatDayCounts([
        LibraryEntry(key: 'a', title: 'A', timestamp: startOfToday),
        LibraryEntry(key: 'b', title: 'B', timestamp: startOfToday),
        LibraryEntry(
          key: 'old',
          title: 'OLD',
          timestamp: now.subtract(const Duration(days: 90)),
        ),
      ]);
      expect(counts, hasLength(56));
      expect(counts.last, 2);
      expect(counts.fold<int>(0, (a, b) => a + b), 2);
      expect(gapHeatDayCounts(const []), List.filled(56, 0));
      expect(gapHeatDayCounts(const [], weeks: 4), hasLength(28));
    });

    test('星期桶：2024-03-04 / 03-11 落在周一，03-10 落在周日', () {
      // 固定日期，不依赖「现在」。
      final counts = gapWeekdayCounts([
        LibraryEntry(key: 'm1', title: 'M1', timestamp: DateTime(2024, 3, 4)),
        LibraryEntry(key: 'm2', title: 'M2', timestamp: DateTime(2024, 3, 11)),
        LibraryEntry(key: 's', title: 'S', timestamp: DateTime(2024, 3, 10)),
      ]);
      expect(counts, hasLength(7));
      expect(counts[0], 2);
      expect(counts[6], 1);
      expect(counts.fold<int>(0, (a, b) => a + b), 3);
      expect(gapWeekdayCounts(const []), List.filled(7, 0));
    });

    test('跨度：少于两个时间点没有跨度，其余按最新与最早差天数', () {
      expect(gapSpanWindow(const []), isNull);
      expect(gapSpanWindow([LibraryEntry(key: 'a', title: 'A')]), isNull);
      expect(
        gapSpanWindow([
          LibraryEntry(key: 'a', title: 'A', timestamp: DateTime(2024, 3, 1)),
          LibraryEntry(key: 'b', title: 'B'),
        ]),
        isNull,
        reason: '只有一个带时间的条目，没有跨度',
      );
      final span = gapSpanWindow([
        LibraryEntry(key: 'a', title: 'A', timestamp: DateTime(2024, 3, 20)),
        LibraryEntry(key: 'b', title: 'B', timestamp: DateTime(2024, 1, 1)),
        LibraryEntry(key: 'c', title: 'C', timestamp: DateTime(2024, 2, 10)),
      ]);
      expect(span, isNotNull);
      expect(span!.days, 79);
      expect(span.earliest, DateTime(2024, 1, 1));
    });

    test('待读存量：进度为 null 或 <= 0 才算「还没开始」', () {
      final entries = [
        LibraryEntry(key: 'a', title: 'A'),
        LibraryEntry(key: 'b', title: 'B', progress: 0),
        LibraryEntry(key: 'c', title: 'C', progress: .1),
        LibraryEntry(key: 'd', title: 'D', progress: 1),
      ];
      expect(gapUnreadCount(entries), 2);
      expect(gapUnreadCount(const []), 0);
    });

    test('里程碑：严格大于当前数量的下一个整十 / 整百', () {
      expect(nextGapMilestone(0), 10);
      expect(nextGapMilestone(5), 10);
      expect(nextGapMilestone(9), 10);
      expect(nextGapMilestone(10), 20);
      expect(nextGapMilestone(52), 60);
      expect(nextGapMilestone(99), 100);
      expect(nextGapMilestone(100), 200);
      expect(nextGapMilestone(150), 200);
      expect(nextGapMilestone(1000), 1100);
      expect(nextGapMilestone(-3), 10);
    });
  });

  group('渲染', () {
    testWidgets('每款在 180x112 与 96x56 槽位都不溢出', (tester) async {
      final entries = _sampleEntries();
      for (final size in const [Size(180, 112), Size(96, 56)]) {
        final sample = _sample(entries, size);
        for (final spec in extraLibraryGapWidgets()) {
          await _pumpSpec(tester, spec, sample, size);
          expect(
            find.byType(GapExpressiveShell),
            findsOneWidget,
            reason: '${spec.id} @ ${size.width}x${size.height}',
          );
        }
      }
    });

    testWidgets('每款在自己的下限尺寸里也不溢出（含 2 倍字号）', (tester) async {
      final entries = _sampleEntries();
      for (final spec in extraLibraryGapWidgets()) {
        final size = Size(spec.minWidth, spec.minHeight);
        final sample = _sample(entries, size);
        for (final scale in const [1.0, 2.0]) {
          await _pumpSpec(tester, spec, sample, size, textScale: scale);
        }
      }
    });

    testWidgets('大槽位展开：跨度走大数字指标、热力画网格、星期画 7 根柱', (tester) async {
      final entries = _sampleEntries();
      const size = Size(180, 112);
      final sample = _sample(entries, size);
      final kit = extraLibraryGapWidgets();

      await _pumpSpec(
        tester,
        kit.firstWhere((s) => s.id == 'gap_span'),
        sample,
        size,
      );
      expect(find.byType(GapExpressiveMetricBody), findsOneWidget);

      await _pumpSpec(
        tester,
        kit.firstWhere((s) => s.id == 'gap_heatmap'),
        sample,
        size,
      );
      expect(find.byType(CustomPaint), findsWidgets);

      await _pumpSpec(
        tester,
        kit.firstWhere((s) => s.id == 'gap_weekday'),
        sample,
        size,
      );
      expect(find.byType(FractionallySizedBox), findsNWidgets(7));
    });
  });
}
