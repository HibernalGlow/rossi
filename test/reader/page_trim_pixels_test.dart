import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/reader/page_trim_transform.dart';

class _MarginPage extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      const Rect.fromLTWH(50, 0, 80, 200),
      Paint()..color = Colors.black,
    );
    canvas.drawRect(
      const Rect.fromLTWH(130, 0, 20, 200),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_MarginPage oldDelegate) => false;
}

void main() {
  testWidgets(
    'height-constrained crop removes the actual white pixels without a new image',
    (tester) async {
      final boundaryKey = GlobalKey();
      Widget host(Rect? crop) => MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: ColoredBox(
              color: const Color(0xffff0000),
              child: PageTrimTransform(
                boxSize: const Size(200, 200),
                imageSize: const Size(100, 200),
                contentRect: crop,
                child: CustomPaint(
                  size: const Size(200, 200),
                  painter: _MarginPage(),
                ),
              ),
            ),
          ),
        ),
      );
      Future<List<int>> pixelAt(int x, int y) async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final pixel = bytes.buffer.asUint8List().sublist(
          (y * image.width + x) * 4,
          (y * image.width + x) * 4 + 4,
        );
        image.dispose();
        return pixel;
      }

      await tester.pumpWidget(host(null));
      await tester.pump();
      expect(await tester.runAsync(() => pixelAt(145, 100)), [
        255,
        255,
        255,
        255,
      ]);
      await tester.pumpWidget(host(const Rect.fromLTRB(0, 0, .8, 1)));
      await tester.pump();
      // The discarded right margin is background; the remaining content is centered.
      expect(await tester.runAsync(() => pixelAt(145, 100)), [255, 0, 0, 255]);
      expect(await tester.runAsync(() => pixelAt(135, 100)), [0, 0, 0, 255]);
      await tester.pumpWidget(host(null));
      await tester.pump();
      expect(await tester.runAsync(() => pixelAt(145, 100)), [
        255,
        255,
        255,
        255,
      ]);
    },
  );
}
