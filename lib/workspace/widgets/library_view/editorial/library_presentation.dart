import 'dart:math' as math;

import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/i18n/strings.g.dart';

enum LibraryWeight {
  signals,
  order,
  count,
  bytes,
  recent,
  progress,
  imageShape,
  balanced;

  const LibraryWeight();

  String get label => switch (this) {
    LibraryWeight.signals => t.workspace.favouriteTags,
    LibraryWeight.order => t.workspace.followSort,
    LibraryWeight.count => t.workspace.contentCount,
    LibraryWeight.bytes => t.workspace.occupiedSize,
    LibraryWeight.recent => t.workspace.recentlyUsed,
    LibraryWeight.progress => t.workspace.readingStatus,
    LibraryWeight.imageShape => t.workspace.originalRatio,
    LibraryWeight.balanced => t.workspace.weightBalanced,
  };
}

enum LibraryCoverTapAction {
  expandDetails,
  openDetails;

  const LibraryCoverTapAction();

  String get label => switch (this) {
    LibraryCoverTapAction.expandDetails => t.workspace.expandDetailsBelow,
    LibraryCoverTapAction.openDetails => t.workspace.openDetailsPage,
  };
}

/// 不规则轮廓之间的空隙填什么。
///
/// 展墙的行高取同行最高那块卡，于是矮卡下方会留出一块竖向余量；一行没排满时
/// 行尾还会留横向余量。[widgets] 与 [shapes] 各选一种，[both] 让两者并存 ——
/// 此时**每款小组件一面墙最多出现一次**，重复的位置改用随机图形。
enum LibraryGapFill {
  off,
  shapes,
  widgets,
  both;

  const LibraryGapFill();

  String get label => switch (this) {
    LibraryGapFill.off => t.workspace.noFill,
    LibraryGapFill.shapes => t.workspace.randomShapes,
    LibraryGapFill.widgets => t.workspace.miniWidgets,
    LibraryGapFill.both => t.workspace.widgetsPlusShapes,
  };
}

/// 信号定义由宿主提供；通用展墙不认识漫画标签或业务种类。
class LibraryWeightSignal {
  const LibraryWeightSignal(this.id, this.label, this.defaultWeight);
  final String id;
  final String label;
  final double defaultWeight;
}

/// 展示偏好独立于核心视图枚举：不会把原有六档视图或目录排序写坏。
class LibraryPresentation {
  const LibraryPresentation({
    this.editorial = true,
    this.hero = true,
    this.sections = false,
    this.asymmetric = true,
    this.weight = LibraryWeight.balanced,
    this.emphasis = .65,
    this.recursiveStats = false,
    this.cardWidth = 140,
    this.cardHeight = 270,
    this.gap = 10,
    this.imageScale = 1,
    this.gapFill = LibraryGapFill.both,
    this.gapShapes = true,
    this.gapShapeStyles = const {},
    this.gapWidgets = const {},
    this.signalWeights = const {},
    this.coverTapAction,
  });

  final bool editorial;
  final bool hero;
  final bool sections;
  final bool asymmetric;
  final LibraryWeight weight;
  final double emphasis;
  final bool recursiveStats;
  final double cardWidth, cardHeight, gap, imageScale;

  /// 空隙填充口径；默认「组件 + 图形」，装不下组件的位置由图形补。
  final LibraryGapFill gapFill;

  /// 随机图形单独开关：关掉之后 shapes 档等于不填，both 档只剩小组件
  /// （装不下的位置留空）。与 [gapFill] 是「总口径 / 单项开关」的关系。
  final bool gapShapes;

  /// 每一款随机图形样式的单独开关；缺键 = 开（新样式默认可见，不必迁移）。
  /// 键是 `LibraryGapShapeStyle.name`，全部关掉时退回有机团那一款。
  final Map<String, bool> gapShapeStyles;

  /// 每一款空隙小组件的单独开关；缺键 = 开（新组件默认可见，不必迁移）。
  final Map<String, bool> gapWidgets;
  final Map<String, double> signalWeights;

  /// 旧设置未指定时沿用宿主默认：发现打开页签，书签与历史原位展开。
  final LibraryCoverTapAction? coverTapAction;

  bool expandsOnCoverTap({required bool defaultValue}) => coverTapAction == null
      ? defaultValue
      : coverTapAction == LibraryCoverTapAction.expandDetails;

  LibraryPresentation copyWith({
    bool? editorial,
    bool? hero,
    bool? sections,
    bool? asymmetric,
    LibraryWeight? weight,
    double? emphasis,
    bool? recursiveStats,
    double? cardWidth,
    double? cardHeight,
    double? gap,
    double? imageScale,
    LibraryGapFill? gapFill,
    bool? gapShapes,
    Map<String, bool>? gapShapeStyles,
    Map<String, bool>? gapWidgets,
    Map<String, double>? signalWeights,
    LibraryCoverTapAction? coverTapAction,
  }) => LibraryPresentation(
    editorial: editorial ?? this.editorial,
    hero: hero ?? this.hero,
    sections: sections ?? this.sections,
    asymmetric: asymmetric ?? this.asymmetric,
    weight: weight ?? this.weight,
    emphasis: emphasis ?? this.emphasis,
    recursiveStats: recursiveStats ?? this.recursiveStats,
    cardWidth: cardWidth ?? this.cardWidth,
    cardHeight: cardHeight ?? this.cardHeight,
    gap: gap ?? this.gap,
    imageScale: imageScale ?? this.imageScale,
    gapFill: gapFill ?? this.gapFill,
    gapShapes: gapShapes ?? this.gapShapes,
    gapShapeStyles: gapShapeStyles ?? this.gapShapeStyles,
    gapWidgets: gapWidgets ?? this.gapWidgets,
    signalWeights: signalWeights ?? this.signalWeights,
    coverTapAction: coverTapAction ?? this.coverTapAction,
  );

  Map<String, Object> toJson() => {
    'editorial': editorial,
    'hero': hero,
    'sections': sections,
    'asymmetric': asymmetric,
    'weight': weight.name,
    'emphasis': emphasis,
    'recursiveStats': recursiveStats,
    'cardWidth': cardWidth,
    'cardHeight': cardHeight,
    'gap': gap,
    'imageScale': imageScale,
    'gapFill': gapFill.name,
    'gapShapes': gapShapes,
    'gapShapeStyles': gapShapeStyles,
    'gapWidgets': gapWidgets,
    'signalWeights': signalWeights,
    if (coverTapAction != null) 'coverTapAction': coverTapAction!.name,
  };

  factory LibraryPresentation.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    double number(String key, double fallback, double min, double max) {
      final value = json[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    return LibraryPresentation(
      editorial: flag('editorial', true),
      hero: flag('hero', true),
      sections: flag('sections', false),
      asymmetric: flag('asymmetric', true),
      weight:
          LibraryWeight.values
              .where((w) => w.name == json['weight'])
              .firstOrNull ??
          LibraryWeight.balanced,
      emphasis: number('emphasis', .65, 0, 1),
      recursiveStats: flag('recursiveStats', false),
      cardWidth: number('cardWidth', 140, 80, 420),
      cardHeight: number('cardHeight', 270, 180, 600),
      gap: number('gap', 10, 4, 32),
      imageScale: number('imageScale', 1, .5, 1),
      gapFill:
          LibraryGapFill.values
              .where((mode) => mode.name == json['gapFill'])
              .firstOrNull ??
          LibraryGapFill.both,
      gapShapes: flag('gapShapes', true),
      gapShapeStyles: {
        if (json['gapShapeStyles'] is Map)
          for (final entry in (json['gapShapeStyles'] as Map).entries)
            if (entry.key is String && entry.value is bool)
              entry.key as String: entry.value as bool,
      },
      gapWidgets: {
        if (json['gapWidgets'] is Map)
          for (final entry in (json['gapWidgets'] as Map).entries)
            if (entry.key is String && entry.value is bool)
              entry.key as String: entry.value as bool,
      },
      coverTapAction: LibraryCoverTapAction.values
          .where((action) => action.name == json['coverTapAction'])
          .firstOrNull,
      signalWeights: {
        if (json['signalWeights'] is Map)
          for (final entry in (json['signalWeights'] as Map).entries)
            if (entry.key is String &&
                entry.value is num &&
                (entry.value as num).isFinite)
              entry.key as String: (entry.value as num).toDouble().clamp(0, 10),
      },
    );
  }
}

/// 面积强调有界；度量先取对数，避免一个巨型目录吞掉整面展墙。
List<double> libraryWeights(
  List<LibraryEntry> entries,
  LibraryWeight weight, {
  Map<String, double> signalWeights = const {},
}) {
  List<double> normalize(double Function(LibraryEntry) metric) {
    final values = entries
        .map((e) => math.log(1 + math.max(0, metric(e))))
        .toList();
    final max = values.fold(0.0, math.max);
    return max == 0
        ? List.filled(entries.length, 0)
        : values.map((v) => v / max).toList();
  }

  final counts = normalize((e) => (e.itemCount ?? 0).toDouble());
  final bytes = normalize((e) => e.byteSize ?? 0);
  final latest = entries.fold<int>(
    0,
    (t, e) => math.max(t, e.timestamp?.millisecondsSinceEpoch ?? 0),
  );
  double recency(LibraryEntry e) {
    final time = e.timestamp?.millisecondsSinceEpoch;
    if (time == null || latest == 0) return 0;
    return 1 /
        (1 +
            math.max(0, latest - time) /
                const Duration(days: 7).inMilliseconds);
  }

  final hasMetrics =
      counts.any((v) => v > 0) ||
      bytes.any((v) => v > 0) ||
      latest != 0 ||
      entries.any((e) => e.progress != null || e.reading == true);
  return List.generate(entries.length, (i) {
    final order = 1 / (1 + i / 3);
    final progress =
        (entries[i].progress ?? (entries[i].reading == true ? 1.0 : 0.0)).clamp(
          0.0,
          1.0,
        );
    return switch (weight) {
      LibraryWeight.signals => librarySignalScore(entries[i], signalWeights),
      LibraryWeight.order => order,
      LibraryWeight.count => counts[i],
      LibraryWeight.bytes => bytes[i],
      LibraryWeight.recent => recency(entries[i]),
      LibraryWeight.progress => progress,
      LibraryWeight.imageShape => entries[i].mediaAspectRatio ?? .72,
      LibraryWeight.balanced when !hasMetrics => order,
      LibraryWeight.balanced =>
        math.max(
              math.max(counts[i], bytes[i]) * .6,
              math.max(recency(entries[i]), progress) * .85,
            ) +
            order * .15,
    };
  });
}

/// 取最强匹配，低优先级标签叠加不会压过更高优先级。
double librarySignalScore(LibraryEntry entry, Map<String, double> weights) {
  final maximum = weights.values
      .where((v) => v.isFinite && v > 0)
      .fold(0.0, math.max);
  if (maximum == 0) return 0;
  return weights.entries.fold(0.0, (score, rule) {
    final match = entry.weightSignals[rule.key] ?? 0;
    if (!match.isFinite || !rule.value.isFinite) return score;
    return math.max(
      score,
      match.clamp(0.0, 1.0) * math.max(0, rule.value) / maximum,
    );
  });
}

/// 按面板实际宽度选列数；用户尺寸是目标，窄面板始终能容纳一列。
int libraryCanvasColumns(double width, LibraryPresentation presentation) =>
    ((width + presentation.gap) / (presentation.cardWidth + presentation.gap) +
            1e-9)
        .floor()
        .clamp(1, 24);

double libraryCardWidthForColumns(double width, int columns, double gap) =>
    (width - (columns - 1) * gap) / columns;

class LibraryCanvasRow {
  const LibraryCanvasRow(this.indices, this.spans, this.section);
  final List<int> indices;
  final List<int> spans;
  final String? section;
}

/// 顺序打包，不做 dense 回填；展开只在所属行下方占位，上方行位置不变。
List<LibraryCanvasRow> libraryCanvasRows({
  required List<LibraryEntry> entries,
  required int columns,
  required LibraryPresentation presentation,
  Map<String, double> aspectRatios = const {},
  String? Function(LibraryEntry entry)? sectionOf,
}) {
  final weights = libraryWeights(
    entries,
    presentation.weight,
    signalWeights: presentation.signalWeights,
  );
  // 控制大卡密度：即使一组权重接近，也给普通条目留出足够空间。
  final candidates = List.generate(entries.length, (i) => i)
    ..removeWhere((i) => weights[i] * presentation.emphasis < .42)
    ..sort((a, b) {
      final priority = weights[b].compareTo(weights[a]);
      return priority == 0 ? a.compareTo(b) : priority;
    });
  final large = candidates
      .take(math.max(1, (entries.length * .28).ceil()))
      .toSet();
  final rows = <LibraryCanvasRow>[];
  var indices = <int>[];
  var spans = <int>[];
  var used = 0;
  var emphasized = false;
  String? section;
  void flush() {
    if (indices.isEmpty) return;
    rows.add(LibraryCanvasRow(indices, spans, section));
    indices = [];
    spans = [];
    used = 0;
    emphasized = false;
  }

  for (var i = 0; i < entries.length; i++) {
    final nextSection = sectionOf != null
        ? sectionOf(entries[i])
        : (presentation.sections ? entries[i].section : null);
    if (nextSection != section) {
      flush();
      section = nextSection;
    }
    final span =
        presentation.asymmetric &&
            columns > 1 &&
            !emphasized &&
            (presentation.weight == LibraryWeight.imageShape
                ? (aspectRatios[entries[i].key] ??
                          entries[i].mediaAspectRatio ??
                          .72) >
                      1.15
                : large.contains(i))
        ? math.min(2, columns)
        : 1;
    if (used + span > columns) flush();
    indices.add(i);
    spans.add(span);
    used += span;
    if (span > 1) emphasized = true;
    if (used == columns) flush();
  }
  flush();
  return rows;
}
