// 自绘图标（glyph）体系的出口。
//
// 来源：FlClash（https://github.com/chen08209/FlClash），GPL-3.0；
// 许可口径见 `docs/adr/0021-flclash-navigation-port-and-gpl-relicense.md`。
// 上游同名的 `icons.dart` 多导出一个 `caption_icon.dart`，那份是阅读器里的
// 字幕图标，本次没有搬，所以这里也不导出它。

export 'animated_glyph.dart';
// 本仓新增：`AnimatedGlyph` 的带 size/color 透传版（见文件头注释）。
export 'animated_glyph_icon.dart';
export 'app_glyphs.dart';
export 'glyph.dart';
export 'glyph_icon.dart';
export 'glyph_painter.dart';
