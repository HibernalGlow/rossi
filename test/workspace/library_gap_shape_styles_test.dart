import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/model/library_presentation_preferences.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_shape.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('随机图形样式', () {
    test('单项开关缺键 = 开；全关掉时保留有机团，不会把空隙填成空白', () {
      expect(
        libraryGapShapeStylesFromToggles(const {}),
        kLibraryGapShapeStyles,
      );
      final onlyWave = libraryGapShapeStylesFromToggles({
        for (final style in LibraryGapShapeStyle.values)
          style.name: style == LibraryGapShapeStyle.wave,
      });
      expect(onlyWave, [LibraryGapShapeStyle.wave]);
      expect(
        libraryGapShapeStylesFromToggles({
          for (final style in LibraryGapShapeStyle.values) style.name: false,
        }),
        [LibraryGapShapeStyle.blob],
      );
    });

    test('种子挑样式是确定的：同一块空隙重排不跳形', () {
      final enabled = [
        LibraryGapShapeStyle.burst,
        LibraryGapShapeStyle.gem,
        LibraryGapShapeStyle.wave,
      ];
      for (var seed = 0; seed < 20; seed++) {
        final first = libraryGapShapeStyleFor(seed, enabled);
        expect(libraryGapShapeStyleFor(seed, enabled), first);
        expect(enabled, contains(first));
      }
    });

    test('每款样式都有非空名字', () {
      for (final style in kLibraryGapShapeStyles) {
        expect(style.label.trim(), isNotEmpty);
      }
    });
  });

  group('样式进入槽位决策', () {
    LibraryGapSlot slot(int i) => LibraryGapSlot(
      row: i,
      tile: null,
      columnStart: 0,
      span: 1,
      width: 160,
      height: 120,
    );

    test('shapes 档用启用中的样式；同输入两次结果一致', () {
      final slots = [slot(0), slot(1), slot(2)];
      final shapes = [LibraryGapShapeStyle.ring, LibraryGapShapeStyle.arch];
      final first = libraryGapChoices(
        slots: slots,
        mode: LibraryGapFill.shapes,
        widgets: const [],
        entries: const <LibraryEntry>[],
        scope: 'seed-test',
        shapes: shapes,
      );
      final second = libraryGapChoices(
        slots: slots,
        mode: LibraryGapFill.shapes,
        widgets: const [],
        entries: const <LibraryEntry>[],
        scope: 'seed-test',
        shapes: shapes,
      );
      for (final entry in first.entries) {
        expect(entry.value.isShape, isTrue);
        expect(shapes, contains(entry.value.shapeStyle));
        expect(second[entry.key]!.shapeStyle, entry.value.shapeStyle);
        expect(second[entry.key]!.seed, entry.value.seed);
      }
    });

    test('both 档里组件用完后的退位也带样式', () {
      final choices = libraryGapChoices(
        slots: [slot(0), slot(1)],
        mode: LibraryGapFill.both,
        widgets: const [],
        entries: const <LibraryEntry>[],
        scope: 'seed-fallback',
        shapes: const [LibraryGapShapeStyle.gem],
      );
      expect(choices.values.every((c) => c.isShape), isTrue);
      expect(choices.values.map((c) => c.shapeStyle).toSet(), {
        LibraryGapShapeStyle.gem,
      });
    });
  });

  group('偏好持久化', () {
    test('gapShapeStyles 往返；插入顺序不影响合并内容', () {
      const value = LibraryPresentation(
        gapShapeStyles: {'wave': false, 'arch': true},
      );
      final restored = LibraryPresentation.fromJson(
        jsonDecode(jsonEncode(value.toJson())) as Map<String, dynamic>,
      );
      expect(restored.gapShapeStyles, {'wave': false, 'arch': true});

      // 内容串按 id 排序：同步合并只看得懂「值」，看不懂插入顺序。
      const reordered = LibraryPresentation(
        gapShapeStyles: {'arch': true, 'wave': false},
      );
      expect(
        LibraryPresentationPreferences.content(value),
        LibraryPresentationPreferences.content(reordered),
      );
    });

    test('脏值被丢弃，缺键不覆盖默认', () {
      final restored = LibraryPresentation.fromJson({
        'gapShapeStyles': {'wave': false, 'arch': 'yes', 3: true},
      });
      expect(restored.gapShapeStyles, {'wave': false});
    });
  });

  group('渲染', () {
    for (final style in LibraryGapShapeStyle.values) {
      testWidgets('${style.name} 在小槽位与大槽位都不越界（含 2 倍字号）', (tester) async {
        for (final size in const [Size(96, 56), Size(200, 140)]) {
          for (final scale in const [1.0, 2.0]) {
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
                      width: size.width,
                      height: size.height,
                      child: LibraryGapShape(seed: 7, style: style),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${style.name} @ $size scale $scale',
            );
          }
        }
      });
    }
  });
}
