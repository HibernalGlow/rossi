import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/model/library_presentation_preferences.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_shape.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_widgets.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/icons/icons.dart';

Widget _stub(BuildContext context, LibraryGapSample sample) =>
    const SizedBox.shrink();

LibraryGapWidgetSpec _spec(
  String id, {
  double minWidth = 80,
  double minHeight = 50,
  bool Function(LibraryGapSample)? accepts,
}) => LibraryGapWidgetSpec(
  id: id,
  label: id,
  glyph: AppGlyphs.star,
  minWidth: minWidth,
  minHeight: minHeight,
  accepts: accepts,
  builder: _stub,
);

LibraryGapSlot _slot(String id, double width, double height) => LibraryGapSlot(
  row: id.hashCode.abs() % 97,
  tile: null,
  columnStart: 0,
  span: 1,
  width: width,
  height: height,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('空隙槽位', () {
    test('矮卡下方与行尾各算一块，尺寸按 unit/gap 复算', () {
      final slots = libraryGapSlots(
        rows: const [
          LibraryCanvasRow([0, 1], [1, 1], null),
        ],
        heights: const [
          [240, 120],
        ],
        unit: 100,
        gap: 10,
        columns: 4,
      );
      expect(slots.map((s) => s.id), ['r0t1', 'r0x']);
      final under = slots.first;
      // 竖向余量再让出一条 gap，填充物不贴着上面的卡片。
      expect(under.width, 100);
      expect(under.height, 110);
      final trailing = slots.last;
      expect(trailing.width, 210);
      expect(trailing.height, 240);
    });

    test('余量小于阈值就不填：碎成一条缝的空隙不值得放东西', () {
      final slots = libraryGapSlots(
        rows: const [
          LibraryCanvasRow([0, 1], [1, 1], null),
        ],
        heights: const [
          [240, 190],
        ],
        unit: 100,
        gap: 10,
        columns: 4,
      );
      expect(slots.map((s) => s.id), ['r0x']);
    });

    test('行排满时没有行尾槽位', () {
      final slots = libraryGapSlots(
        rows: const [
          LibraryCanvasRow([0, 1], [2, 2], null),
        ],
        heights: const [
          [300, 150],
        ],
        unit: 100,
        gap: 10,
        columns: 4,
      );
      expect(slots.map((s) => s.id), ['r0t1']);
    });
  });

  group('填充口径', () {
    const entries = [
      LibraryEntry(key: 'a', title: 'A'),
      LibraryEntry(key: 'b', title: 'B'),
    ];
    final slots = [
      _slot('wide', 220, 150),
      _slot('narrow', 100, 60),
      _slot('another', 240, 240),
    ];
    final kit = [_spec('big', minWidth: 150, minHeight: 100), _spec('small')];

    Map<String, LibraryGapChoice> plan(LibraryGapFill mode) =>
        libraryGapChoices(
          slots: slots,
          mode: mode,
          widgets: kit,
          entries: entries,
          scope: 'test',
        );

    test('不填充：一块都不派', () {
      expect(plan(LibraryGapFill.off), isEmpty);
    });

    test('随机图形：每个槽位都是图形，且同槽位种子稳定', () {
      final first = plan(LibraryGapFill.shapes);
      expect(first.length, 3);
      expect(first.values.every((c) => c.isShape), isTrue);
      // 位置决定种子：切回来不跳形，换位置就换形状。
      expect(first[slots[0].id]!.seed, isNot(first[slots[1].id]!.seed));
    });

    test('只选小组件：装不下的槽位留空，同一款可以重复', () {
      final chosen = plan(LibraryGapFill.widgets);
      expect(chosen[slots[0].id]!.widgetId, 'big');
      expect(chosen[slots[1].id]!.widgetId, 'small');
      // 第三个槽位只有 big 装得下，这一档允许重复，于是还是 big。
      expect(chosen[slots[2].id]!.widgetId, 'big');
    });

    test('并存：组件每面墙各一次，重复的位置改用图形', () {
      final chosen = plan(LibraryGapFill.both);
      expect(chosen[slots[0].id]!.widgetId, 'big');
      expect(chosen[slots[1].id]!.widgetId, 'small');
      // big 已经用过 → 这块改画随机图形。
      expect(chosen[slots[2].id]!.isShape, isTrue);
    });

    test('accepts 判不过的组件不会被选中', () {
      final gated = libraryGapChoices(
        slots: [slots.first],
        mode: LibraryGapFill.widgets,
        widgets: [_spec('needsProgress', accepts: (s) => false)],
        entries: entries,
        scope: 'test',
      );
      expect(gated, isEmpty);
    });

    test('默认套件的优先阶梯：数据越具体越先占位，最后才退到条目数', () {
      final now = DateTime.now();
      final rich = [
        for (var i = 0; i < 4; i++)
          LibraryEntry(
            key: 'h$i',
            title: 'H$i',
            tags: const ['#Pixiv'],
            timestamp: now.subtract(Duration(days: i)),
            reading: i == 0,
            progress: .4,
            section: i.isEven ? '本地' : '插件',
            media:
                (
                  context, {
                  required width,
                  required height,
                  required radius,
                  required fit,
                }) => Container(color: const Color(0xFF001122)),
          ),
      ];
      final big = _slot('big', 260, 200);
      String? pick({List<String> off = const []}) => libraryGapChoices(
        slots: [big],
        mode: LibraryGapFill.widgets,
        widgets: libraryGapKit(defaultLibraryGapWidgets(), {
          for (final id in off) id: false,
        }),
        entries: rich,
        scope: 'test',
      )[big.id]?.widgetId;

      // 阶梯按「这块空隙还能说出多少 specifics」排：封面 > 接着看 > 连续天数 >
      // 近 7 日 > 时段 > 随机漫游 > …；关掉前面的，后面的逐级顶上来。
      expect(pick(), 'gap_cover_collage');
      expect(pick(off: ['gap_cover_collage']), 'gap_continue');
      expect(
        pick(off: ['gap_cover_collage', 'gap_continue']),
        'gap_streak_days',
      );
      expect(
        pick(off: ['gap_cover_collage', 'gap_continue', 'gap_streak_days']),
        'gap_week_bars',
      );
      expect(
        pick(
          off: const [
            'gap_cover_collage',
            'gap_continue',
            'gap_streak_days',
            'gap_week_bars',
          ],
        ),
        'gap_day_parts',
      );
      expect(
        pick(
          off: const [
            'gap_cover_collage',
            'gap_continue',
            'gap_streak_days',
            'gap_week_bars',
            'gap_day_parts',
          ],
        ),
        'gap_random_pick',
      );
      // 只有裸条目时，能说的只有「这一墙有几条」。
      expect(
        libraryGapChoices(
          slots: [big],
          mode: LibraryGapFill.widgets,
          widgets: defaultLibraryGapWidgets(),
          entries: const [LibraryEntry(key: 'x', title: 'X')],
          scope: 'test',
        )[big.id]!.widgetId,
        'gap_count',
      );
    });
  });

  group('偏好持久化', () {
    test('gapFill 往返与未知值回退', () {
      expect(
        const LibraryPresentation().toJson()['gapFill'],
        LibraryGapFill.both.name,
      );
      expect(
        LibraryPresentation.fromJson(const {'gapFill': 'widgets'}).gapFill,
        LibraryGapFill.widgets,
      );
      expect(
        LibraryPresentation.fromJson(const {'gapFill': 'nope'}).gapFill,
        LibraryGapFill.both,
      );
      expect(
        const LibraryPresentation(
          gapFill: LibraryGapFill.shapes,
        ).copyWith(cardWidth: 200).gapFill,
        LibraryGapFill.shapes,
      );
    });

    test('只带 gapFill 的记录算「可用」，坏值不算', () {
      expect(
        LibraryPresentationPreferences.parsePresentation(const {
          'gapFill': 'shapes',
        })!.gapFill,
        LibraryGapFill.shapes,
      );
      expect(
        LibraryPresentationPreferences.parsePresentation(const {
          'gapFill': 'shapes',
        }),
        isNotNull,
      );
      expect(
        LibraryPresentationPreferences.parsePresentation(const {
          'gapFill': 'nonsense',
        }),
        isNull,
      );
    });
  });

  group('渲染', () {
    testWidgets('图形在小槽位里也不越界', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 40,
                height: 26,
                child: LibraryGapShape(seed: 12345),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LibraryGapShape), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('套件里每款组件在自己的下限尺寸里不溢出（含 2 倍字号）', (tester) async {
      final now = DateTime.now();
      final entries = [
        for (var i = 0; i < 6; i++)
          LibraryEntry(
            key: 'e$i',
            title: '[社团$i] 作品标题 E$i ${i.isEven ? ".mp4" : ".cbz"}',
            subtitle: '本地 · P.${(i + 1) * 3}',
            tags: ['#Pixiv', if (i.isEven) '#Cosplay' else '#原画'],
            timestamp: now.subtract(Duration(days: i)),
            progress: .2 * i,
            reading: i <= 2,
            section: i.isEven ? '本地' : '插件',
            byteSize: 1024 * 1024 * (i + 1),
            itemCount: 12 + i * 4,
            mediaAspectRatio: i % 3 == 0 ? 0.72 : (i % 3 == 1 ? 1.0 : 1.6),
            media:
                (
                  context, {
                  required width,
                  required height,
                  required radius,
                  required fit,
                }) => Container(color: const Color(0xFF123456)),
          ),
      ];
      for (final scale in [1.0, 2.0]) {
        for (final spec in defaultLibraryGapWidgets()) {
          // 下限就是 fits() 放行的最小空隙：比它小根本不会被选中，
          // 所以这里测的是这套件真正可能遇到的最紧的一种排布。
          final slot = LibraryGapSlot(
            row: 0,
            tile: 0,
            columnStart: 0,
            span: 1,
            width: spec.minWidth,
            height: spec.minHeight,
          );
          final sample = LibraryGapSample(
            entries: entries,
            slot: slot,
            seed: 7,
          );
          expect(spec.fits(sample), isTrue, reason: '${spec.id} should fit');
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: spec.minWidth,
                    height: spec.minHeight,
                    child: Builder(
                      builder: (context) => spec.builder(context, sample),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason:
                '${spec.id} @ ${spec.minWidth}x${spec.minHeight} scale $scale',
          );
        }
      }
    });

    testWidgets('大尺寸竖向与横向槽位下 MD3 Expressive 小组件正常展开不溢出', (tester) async {
      final now = DateTime.now();
      final entries = [
        for (var i = 0; i < 6; i++)
          LibraryEntry(
            key: 'e$i',
            title: '[清水由乃] NO.02$i 玉藻前 [DL版]',
            subtitle: '本地 · 57.mp4 · P.${i + 2}',
            tags: const ['#Pixiv', '#Cosplay', '#汉化'],
            timestamp: now.subtract(Duration(days: i)),
            reading: i < 3,
            section: i.isEven ? '本地' : '插件',
            byteSize: 1024 * 1024 * (i + 10),
            itemCount: 18,
            mediaAspectRatio: i.isEven ? 0.68 : 1.78,
            media:
                (
                  context, {
                  required width,
                  required height,
                  required radius,
                  required fit,
                }) => Container(color: const Color(0xFF334455)),
          ),
      ];
      for (final size in const [Size(360, 128), Size(188, 280)]) {
        for (final spec in defaultLibraryGapWidgets()) {
          final slot = LibraryGapSlot(
            row: 0,
            tile: 0,
            columnStart: 0,
            span: 2,
            width: size.width,
            height: size.height,
          );
          final sample = LibraryGapSample(
            entries: entries,
            slot: slot,
            seed: 42,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(useMaterial3: true),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: Builder(
                      builder: (context) => spec.builder(context, sample),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${spec.id} @ ${size.width}x${size.height}',
          );
        }
      }
    });
  });

  group('槽位不变量', () {
    test('随机行配置 500 轮：槽位互不重叠、不越列、不吃掉卡片自己的高度', () {
      final rng = math.Random(20261014);
      for (var trial = 0; trial < 500; trial++) {
        final columns = 1 + rng.nextInt(6);
        final gap = (4 + rng.nextInt(28)).toDouble();
        final unit = (60 + rng.nextInt(300)).toDouble();
        final rows = <LibraryCanvasRow>[];
        final heights = <List<double>>[];
        var index = 0;
        for (var r = 0; r < 1 + rng.nextInt(5); r++) {
          final spans = <int>[];
          final indices = <int>[];
          var used = 0;
          while (used < columns) {
            final span = used + 2 <= columns && rng.nextBool() ? 2 : 1;
            indices.add(index++);
            spans.add(span);
            used += span;
          }
          rows.add(LibraryCanvasRow(indices, spans, null));
          heights.add([
            for (var j = 0; j < spans.length; j++)
              (60 + rng.nextInt(540)).toDouble(),
          ]);
        }
        final slots = libraryGapSlots(
          rows: rows,
          heights: heights,
          unit: unit,
          gap: gap,
          columns: columns,
        );
        final reason = 'trial $trial columns=$columns';
        expect(
          slots.map((s) => s.id).toSet().length,
          slots.length,
          reason: '$reason 槽位 id 撞了',
        );
        for (var r = 0; r < rows.length; r++) {
          final rowSlots = slots.where((s) => s.row == r).toList();
          final rowHeight = heights[r].fold(0.0, math.max);
          final claimed = <int>{};
          for (final slot in rowSlots) {
            expect(
              slot.columnStart + slot.span <= columns,
              isTrue,
              reason: '$reason 第 $r 行越出 $columns 列',
            );
            for (
              var c = slot.columnStart;
              c < slot.columnStart + slot.span;
              c++
            ) {
              expect(
                claimed.contains(c),
                isFalse,
                reason: '$reason 第 $r 行第 $c 列被两块填充认领',
              );
              claimed.add(c);
            }
            final tile = slot.tile;
            if (tile != null) {
              expect(
                slot.height + heights[r][tile] <= rowHeight,
                isTrue,
                reason: '$reason 第 $r 行第 $tile 块会撑破行框',
              );
            }
            expect(slot.height, greaterThanOrEqualTo(kLibraryGapMinFill));
            expect(slot.width, greaterThanOrEqualTo(kLibraryGapMinFill));
          }
        }
      }
    });

    test('同一份输入重算两次结果一致（滚动与重建不闪形）', () {
      final slots = libraryGapSlots(
        rows: const [
          LibraryCanvasRow([0, 1], [1, 2], null),
        ],
        heights: const [
          [300, 150],
        ],
        unit: 120,
        gap: 10,
        columns: 3,
      );
      final now = DateTime.now();
      final entries = [
        for (var i = 0; i < 5; i++)
          LibraryEntry(
            key: 'k$i',
            title: 'T$i',
            timestamp: now.subtract(Duration(days: i)),
            section: i.isEven ? '本地' : '插件',
          ),
      ];
      Map<String, LibraryGapChoice> run() => libraryGapChoices(
        slots: slots,
        mode: LibraryGapFill.both,
        widgets: defaultLibraryGapWidgets(),
        entries: entries,
        scope: 'stable',
      );

      final first = run();
      final second = run();
      expect(first, isNotEmpty);
      expect(second.keys.toList()..sort(), first.keys.toList()..sort());
      for (final id in first.keys) {
        expect(second[id]!.widgetId, first[id]!.widgetId, reason: id);
        expect(second[id]!.isShape, first[id]!.isShape, reason: id);
        expect(second[id]!.seed, first[id]!.seed, reason: id);
      }
    });
  });

  group('单项开关', () {
    test('总口径 × 图形开关 → 生效口径（八种组合全列）', () {
      for (final fill in LibraryGapFill.values) {
        for (final shapes in [true, false]) {
          final mode = libraryGapMode(fill: fill, shapes: shapes);
          if (fill == LibraryGapFill.off) expect(mode, LibraryGapFill.off);
          if (fill == LibraryGapFill.shapes) {
            expect(mode, shapes ? LibraryGapFill.shapes : LibraryGapFill.off);
          }
          if (fill == LibraryGapFill.widgets) {
            // 这一档本来就不画图形，开关不该改变它。
            expect(mode, LibraryGapFill.widgets);
          }
          if (fill == LibraryGapFill.both) {
            expect(mode, shapes ? LibraryGapFill.both : LibraryGapFill.widgets);
          }
        }
      }
    });

    test('关掉某一款组件后由下一款认领；全关等于这一档什么都不派', () {
      final kit = defaultLibraryGapWidgets();
      final slot = _slot('big', 260, 200);
      final now = DateTime.now();
      final entries = [
        for (var i = 0; i < 4; i++)
          LibraryEntry(
            key: 'e$i',
            title: 'T$i',
            tags: const ['#Pixiv'],
            timestamp: now.subtract(Duration(days: i)),
          ),
      ];
      String? pick(Map<String, bool> toggles) => libraryGapChoices(
        slots: [slot],
        mode: LibraryGapFill.widgets,
        widgets: libraryGapKit(kit, toggles),
        entries: entries,
        scope: 's',
      )[slot.id]?.widgetId;

      final first = pick(const {});
      expect(first, isNotNull);
      expect(pick({first!: false}), isNot(first));
      // 缺键 = 开：新组件不需要迁移就能出现。
      expect(libraryGapKit(kit, const {}), hasLength(kit.length));
      expect(
        pick({for (final spec in kit) spec.id: false}),
        isNull,
        reason: '全部关掉之后不该还剩任何组件',
      );
    });

    test('gapShapes 与 gapWidgets 往返、脏值丢弃、插入顺序不影响合并', () {
      const value = LibraryPresentation(
        gapShapes: false,
        gapWidgets: {'gap_count': false, 'gap_streak_days': true},
      );
      final back = LibraryPresentation.fromJson(
        Map<String, dynamic>.from(value.toJson()),
      );
      expect(back.gapShapes, isFalse);
      expect(back.gapWidgets, value.gapWidgets);
      expect(LibraryPresentation.fromJson(const {}).gapShapes, isTrue);
      expect(
        LibraryPresentation.fromJson(const {
          'gapWidgets': {'gap_count': '不是布尔'},
        }).gapWidgets,
        isEmpty,
      );
      final a = LibraryPresentationPreferences.presentationJson(
        const LibraryPresentation(gapWidgets: {'x': false, 'y': true}),
      );
      final b = LibraryPresentationPreferences.presentationJson(
        const LibraryPresentation(gapWidgets: {'y': true, 'x': false}),
      );
      expect(jsonEncode(a), jsonEncode(b));
    });
  });
}
