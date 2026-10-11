import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_bar.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';

SpringLensPainter _lens(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<SpringLensPainter>()
    .single;

class _PaintProbe extends SingleChildRenderObjectWidget {
  const _PaintProbe({required this.onPaint, required super.child});
  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) => _ProbeBox(onPaint);

  @override
  void updateRenderObject(BuildContext context, _ProbeBox renderObject) {
    renderObject.onPaint = onPaint;
  }
}

class _ProbeBox extends RenderProxyBox {
  _ProbeBox(this.onPaint);
  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}

void main() {
  for (final destination in [1, 3]) {
    for (final tint in [null, Colors.white]) {
      testWidgets('1→${destination + 1}，染色=$tint：动画不重画正文和远处页签', (tester) async {
        var selected = 0;
        var bodyBuilds = 0;
        var bodyPaints = 0;
        final tabPaints = List.filled(8, 0);
        final tabBuilds = List.filled(8, 0);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => Column(
                  children: [
                    SpringLensBar(
                      tabs: [
                        for (var i = 0; i < 8; i++)
                          SpringLensTab(
                            child: Builder(
                              builder: (context) {
                                tabBuilds[i]++;
                                return _PaintProbe(
                                  onPaint: () => tabPaints[i]++,
                                  child: SizedBox(
                                    height: 40,
                                    child: Center(child: Text('panel $i')),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                      tabSizes: List.filled(8, 80),
                      selectedIndex: selected,
                      tintColor: tint,
                      onSelected: (value) => setState(() => selected = value),
                    ),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          bodyBuilds++;
                          return _PaintProbe(
                            onPaint: () => bodyPaints++,
                            child: const ColoredBox(color: Colors.grey),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Positive control: these probes actually paint before counting frames.
        expect(bodyPaints, greaterThan(0));
        expect(tabPaints.every((count) => count > 0), isTrue);
        await tester.tap(find.text('panel $destination'));
        await tester.pump();
        final painter = _lens(tester);
        final initialPosition = painter.position;
        final initialBodyPaints = bodyPaints;
        final initialBodyBuilds = bodyBuilds;
        final farPaints = tabPaints.last;
        final builds = List.of(tabBuilds);
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(identical(_lens(tester), painter), isTrue);
        }
        expect(painter.position, greaterThan(initialPosition));
        expect(tabBuilds, builds);
        expect(bodyBuilds, initialBodyBuilds);
        expect(bodyPaints, initialBodyPaints);
        expect(tabPaints.last, farPaints);
        if (tint != null) {
          expect(tabPaints[destination], greaterThan(1));
        }
        await tester.pumpAndSettle();
        expect(painter.position, closeTo(destination, .001));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('透镜跨格移动时图标的局部染色仍按真实轮廓绘制', (tester) async {
    final boundaryKey = GlobalKey();
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: StatefulBuilder(
                builder: (context, setState) => SpringLensBar(
                  tabSizes: const [60, 60, 60, 60],
                  selectedIndex: selected,
                  onSelected: (value) => setState(() => selected = value),
                  lensColor: Colors.black,
                  lensCorner: 12,
                  tintColor: Colors.green,
                  tabs: [
                    for (var i = 0; i < 4; i++)
                      SpringLensTab(
                        child: SizedBox(
                          height: 40,
                          child: Center(
                            child: SizedBox(
                              key: ValueKey('glyph-$i'),
                              width: 20,
                              height: 20,
                              child: const ColoredBox(color: Colors.red),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<List<int>> pixels() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final positions = [
        for (var i = 0; i < 4; i++)
          tester.getCenter(find.byKey(ValueKey('glyph-$i'))) -
              tester.getTopLeft(find.byKey(boundaryKey)),
      ];
      return tester
          .runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final colors = [
              for (final position in positions)
                Color.fromARGB(
                  bytes.getUint8(
                    (position.dy.floor() * image.width + position.dx.floor()) *
                            4 +
                        3,
                  ),
                  bytes.getUint8(
                    (position.dy.floor() * image.width + position.dx.floor()) *
                        4,
                  ),
                  bytes.getUint8(
                    (position.dy.floor() * image.width + position.dx.floor()) *
                            4 +
                        1,
                  ),
                  bytes.getUint8(
                    (position.dy.floor() * image.width + position.dx.floor()) *
                            4 +
                        2,
                  ),
                ).toARGB32(),
            ];
            image.dispose();
            return colors;
          })
          .then((value) => value!);
    }

    expect(await pixels(), [
      Colors.green.toARGB32(),
      Colors.red.toARGB32(),
      Colors.red.toARGB32(),
      Colors.red.toARGB32(),
    ]);
    await tester.tap(find.byKey(const ValueKey('glyph-3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final position = _lens(tester).position;
    expect(position, greaterThan(0));
    expect(position, lessThan(3));
    final painter = _lens(tester);
    final lensPaint = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .firstWhere((widget) => identical(widget.painter, painter));
    final rect = lensRect(
      slots: painter.slots.resolvedTo(
        tester.getSize(find.byWidget(lensPaint)),
      )!,
      position: painter.position,
      velocity: painter.velocity,
      lift: painter.lift,
    );
    // The centers lie on the shape's cross-axis midline, away from corner AA.
    final expected = [
      for (var i = 0; i < 4; i++)
        (rect.contains(Offset(30 + i * 60, 20)) ? Colors.green : Colors.red)
            .toARGB32(),
    ];
    expect(await pixels(), expected);
    await tester.pumpAndSettle();
    expect(await pixels(), [
      Colors.red.toARGB32(),
      Colors.red.toARGB32(),
      Colors.red.toARGB32(),
      Colors.green.toARGB32(),
    ]);
    expect(tester.takeException(), isNull);
  });
}
