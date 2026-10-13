import 'package:zephyr/icons/glyph.dart';

/// 阅读操作的补充符号，沿用全应用的描边和形状词汇。
abstract final class ReaderActionGlyphs {
  static const firstPage = Glyph([
    GlyphPolyline([GlyphVertex(5, 5), GlyphVertex(5, 19)]),
    GlyphPolyline([
      GlyphVertex(15, 6),
      GlyphVertex(9, 12),
      GlyphVertex(15, 18),
    ]),
  ]);
  static const lastPage = Glyph([
    GlyphPolyline([GlyphVertex(19, 5), GlyphVertex(19, 19)]),
    GlyphPolyline([GlyphVertex(9, 6), GlyphVertex(15, 12), GlyphVertex(9, 18)]),
  ]);
  static const zoomOut = Glyph([
    GlyphCircle(10.8, 10.8, 6.9),
    GlyphPolyline([GlyphVertex(15.9, 15.9), GlyphVertex(20.6, 20.6)]),
    GlyphPolyline([
      GlyphVertex(7.9, 10.8),
      GlyphVertex(13.7, 10.8),
    ], role: GlyphRole.detail),
  ]);
}
