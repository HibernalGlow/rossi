import 'dart:ui' show Color;

/// 阅读背景「自适应取色」的一份调色板。
///
/// 形状与 `rust/gpu_present/src/ambient.rs` 的 `AmbientPalette` **一一对应**：
/// 四条边各 [stops] 个色标，加一个代表色（四边色标的平均）。
///
/// # 为什么取色在 Rust 侧、这份模型只在 Dart 侧
///
/// 取色要的是**已经解出来的页面像素**，而那批像素只存在于呈现器里（GPU 上屏那条路
/// 的契约是"像素不过桥"）。参考实现 neoview 是在 Dart/JS 侧**又解了一遍图**再回读，
/// 而它自己后来把这条路关掉了，注释写着「competing with Reader rendering」。
/// 这里反过来：采样跟着解码走，过桥的只是这一小份颜色。
///
/// 这个类因此刻意做成**纯数据 + 纯函数**：解析、插值、压暗都不碰 Flutter widget，
/// 可以直接被单元测试驱动。
class ReaderAmbientPalette {
  const ReaderAmbientPalette({
    required this.average,
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  /// 代表色 = 四条边色标的平均。
  ///
  /// 刻意**不是**整页平均：背景要接的是页面的边沿色。拿整页平均，一张大面积白底
  /// 黑线的漫画页会得到一个灰底，反而与页面边沿对不上。口径与 neoview 的
  /// `edgeFrameToPresentation` 一致。
  final Color average;

  final List<Color> top;
  final List<Color> right;
  final List<Color> bottom;
  final List<Color> left;

  /// 每条边的色标数。与 Rust 侧 `ambient::STOPS` 同值。
  static const int stops = 6;

  /// 值相等语义：五个字段逐通道比较。
  ///
  /// [ReaderAmbientStore.publish] 的「同值不写」完全靠它 —— `ValueNotifier` 的
  /// setter 本身就按 `==` 判同值不通知。这里**必须**真的比较字段：
  /// 早期版本在 publish 里用 `toString()` 判同值，可 Dart 默认的
  /// `Object.toString()` 只返回 `Instance of '…'`、不含任何字段值，
  /// 两个不同的调色板比出来永远相等 —— 现象就是翻页后背景色永远冻在第一页。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReaderAmbientPalette &&
        other.average == average &&
        _listEquals(other.top, top) &&
        _listEquals(other.right, right) &&
        _listEquals(other.bottom, bottom) &&
        _listEquals(other.left, left);
  }

  @override
  int get hashCode => Object.hash(
        average,
        Object.hashAll(top),
        Object.hashAll(right),
        Object.hashAll(bottom),
        Object.hashAll(left),
      );

  static bool _listEquals(List<Color> a, List<Color> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  /// 一条边**没有内容**时的兜底色。
  static const Color emptyColor = Color(0xFF000000);

  /// 一份「四边色标全是同一个颜色」的调色板。
  ///
  /// 它存在的唯一理由是**让过渡有起点**：从固定底色切到自适应档位时，把底色本身
  /// 当成"四边色标都是它"的调色板，插值就统一成了一种情况 —— 不必为「从 null 淡入」
  /// 另写一条分支，也就不会出现两套插值规则互相打架。
  factory ReaderAmbientPalette.flat(Color color) {
    return ReaderAmbientPalette(
      average: color,
      top: List<Color>.filled(stops, color),
      right: List<Color>.filled(stops, color),
      bottom: List<Color>.filled(stops, color),
      left: List<Color>.filled(stops, color),
    );
  }

  /// 从呈现器探针里的 `ambient` 字段解析出一份调色板。
  ///
  /// # 形状不对就**整份丢掉**
  ///
  /// 不做部分兜底：半份调色板（比如只有代表色、四边是空的）会让背景出现
  /// 「某一条边是黑的」这种莫名其妙的效果，而整份丢掉只是退回静态底色 ——
  /// 后者是用户能理解的结果。判据见 `test/reader/ambient_palette_test.dart`。
  ///
  /// 传 `null`（Rust 侧报 `null`，表示这一页没采到）同样返回 `null`。
  static ReaderAmbientPalette? fromProbe(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Color? average = parseHexColor(raw['average']);
    final List<Color>? top = _parseStops(raw['top']);
    final List<Color>? right = _parseStops(raw['right']);
    final List<Color>? bottom = _parseStops(raw['bottom']);
    final List<Color>? left = _parseStops(raw['left']);
    if (average == null ||
        top == null ||
        right == null ||
        bottom == null ||
        left == null) {
      return null;
    }
    return ReaderAmbientPalette(
      average: average,
      top: top,
      right: right,
      bottom: bottom,
      left: left,
    );
  }

  /// 按 [t] 在 `this` 与 [other] 之间插值（`0` = 这一份，`1` = [other]）。
  ///
  /// 色标个数不一致时按**下标记**并夹紧：Rust 侧恒发 [stops] 个，不一致只可能是
  /// 两边的取样口径在升级的那一版对不上，那时宁可让渐变形状有点走样，
  /// 也不要在这里抛异常把阅读器带崩。
  ReaderAmbientPalette lerpTo(ReaderAmbientPalette other, double t) {
    if (t <= 0) {
      return this;
    }
    if (t >= 1) {
      return other;
    }
    return ReaderAmbientPalette(
      average: Color.lerp(average, other.average, t)!,
      top: _lerpStops(top, other.top, t),
      right: _lerpStops(right, other.right, t),
      bottom: _lerpStops(bottom, other.bottom, t),
      left: _lerpStops(left, other.left, t),
    );
  }

  /// 把整份调色板按 [dimPercent] 压暗。
  ///
  /// # 为什么必须压暗
  ///
  /// 颜色来自页面的**边沿**，而漫画页的边沿常常就是白纸。原封不动铺成背景，
  /// 白底漫画在暗环境里就是一块刺眼的光斑 —— 阅读器的背景相比内容永远该更暗一档。
  ///
  /// 参考实现做的是同一件事，而且压得比"暗一档"更狠：
  /// neoview 的 `ReaderBackgroundLayer.css` 是 `filter: blur(...) brightness(0.48)`
  /// （流光溢彩档 `0.48`、"自动匹配"档 `0.56`）。这里的默认值取在同一区间。
  ///
  /// `0` = 不压暗（用原色），`100` = 全黑。
  ReaderAmbientPalette dimmed(int dimPercent) {
    final double scale = 1 - (dimPercent.clamp(0, 100) / 100);
    if (scale >= 1) {
      return this;
    }
    return ReaderAmbientPalette(
      average: _scaleColor(average, scale),
      top: _scaleStops(top, scale),
      right: _scaleStops(right, scale),
      bottom: _scaleStops(bottom, scale),
      left: _scaleStops(left, scale),
    );
  }

  @override
  String toString() =>
      'ReaderAmbientPalette(average: $average, stops: ${top.length})';
}

/// 解析 `#rrggbb` / `#aarrggbb`。认不出返回 `null`（**不**退回黑色 ——
/// "认不出"与"就是黑"是两件事，前者要的是丢掉整份调色板）。
Color? parseHexColor(Object? raw) {
  if (raw is! String) {
    return null;
  }
  final String value = raw.startsWith('#') ? raw.substring(1) : raw;
  if (value.length != 6 && value.length != 8) {
    return null;
  }
  final int? parsed = int.tryParse(value, radix: 16);
  if (parsed == null) {
    return null;
  }
  if (value.length == 6) {
    return Color(0xFF000000 | parsed);
  }
  return Color(parsed);
}

List<Color>? _parseStops(Object? raw) {
  if (raw is! List) {
    return null;
  }
  final List<Color> colors = <Color>[];
  for (final Object? entry in raw) {
    final Color? color = parseHexColor(entry);
    if (color == null) {
      return null;
    }
    colors.add(color);
  }
  if (colors.isEmpty) {
    return null;
  }
  return colors;
}

List<Color> _lerpStops(List<Color> from, List<Color> to, double t) {
  final int count = from.length > to.length ? from.length : to.length;
  return <Color>[
    for (int index = 0; index < count; index++)
      Color.lerp(
        from[index < from.length ? index : from.length - 1],
        to[index < to.length ? index : to.length - 1],
        t,
      )!,
  ];
}

List<Color> _scaleStops(List<Color> colors, double scale) => <Color>[
  for (final Color color in colors) _scaleColor(color, scale),
];

/// 按 [scale] 缩放 RGB，alpha 保持不透明。
///
/// 用 `.r/.g/.b` 这套 0..1 的通道而不是 `red/green/blue`：后者在新版
/// Flutter 里已经标了废弃，而这一层的意图本来就是"按比例缩放"，
/// 0..1 的表达比 0..255 更贴近意图（也更少一处取整）。
Color _scaleColor(Color color, double scale) {
  return Color.from(
    alpha: 1,
    red: (color.r * scale).clamp(0, 1),
    green: (color.g * scale).clamp(0, 1),
    blue: (color.b * scale).clamp(0, 1),
  );
}
