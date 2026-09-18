/// 面板 / 卡片的**布局记账** —— 与 neoview 的 `panelLayout` / `cardLayout` 同构。
///
/// 本文件是**纯 Dart**（不 import Flutter / dart:ui），于是可以用
/// `dart run test/workspace/board_layout_check.dart` 直接跑断言 ——
/// 本机 `flutter test` 起不来（flutter_tester 的 WebSocket 握手失败），
/// 凡是能从 widget 里抽出来的判据都抽到这里来验。
///
/// 三种 id 的关系：
/// - **泳道**（lane）：横向条带上的一条，`left` / `reader` / `right`；
/// - **面板**（panel）：泳道内部的一个功能位，由**图标轨**切换；
/// - **卡片**（card）：面板内部的一块内容，成员关系在泳道与四边栏之间**共享**。
library;

/// 面板依附的泳道侧。
///
/// 目前只有左右两条面板泳道；`reader` 泳道不承载面板（它就是阅读器）。
enum WorkspacePanelSide {
  left,
  right;

  /// 对应的泳道 id（`LaneId.left` / `LaneId.right`）。
  String get laneId => name;

  static WorkspacePanelSide? tryParse(String value) {
    for (final side in WorkspacePanelSide.values) {
      if (side.name == value) return side;
    }
    return null;
  }
}

/// 单个面板的布局覆盖项（未记录的项回落到面板定义里的默认值）。
class PanelLayout {
  final bool visible;
  final int order;
  final WorkspacePanelSide side;

  const PanelLayout({
    required this.visible,
    required this.order,
    required this.side,
  });

  PanelLayout copyWith({
    bool? visible,
    int? order,
    WorkspacePanelSide? side,
  }) {
    return PanelLayout(
      visible: visible ?? this.visible,
      order: order ?? this.order,
      side: side ?? this.side,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PanelLayout &&
      other.visible == visible &&
      other.order == order &&
      other.side == side;

  @override
  int get hashCode => Object.hash(visible, order, side);

  @override
  String toString() => 'PanelLayout(visible: $visible, order: $order, side: ${side.name})';
}

/// 单张卡片的布局覆盖项。
///
/// [panelId] 决定这张卡**住在哪个面板**里 —— 拖动卡片换面板改的就是它，
/// 卡片成员关系（泳道 / 四边栏共用）也由它表达。
class CardLayout {
  final String panelId;
  final bool visible;
  final int order;
  final bool expanded;

  const CardLayout({
    required this.panelId,
    required this.visible,
    required this.order,
    this.expanded = true,
  });

  CardLayout copyWith({
    String? panelId,
    bool? visible,
    int? order,
    bool? expanded,
  }) {
    return CardLayout(
      panelId: panelId ?? this.panelId,
      visible: visible ?? this.visible,
      order: order ?? this.order,
      expanded: expanded ?? this.expanded,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CardLayout &&
      other.panelId == panelId &&
      other.visible == visible &&
      other.order == order &&
      other.expanded == expanded;

  @override
  int get hashCode => Object.hash(panelId, visible, order, expanded);

  @override
  String toString() =>
      'CardLayout(panelId: $panelId, visible: $visible, order: $order, expanded: $expanded)';
}

/// 面板 + 卡片布局的**完整记账**。
///
/// 只存**被改动过**的项；没记录的项由注册表用定义里的默认值填。
/// 于是「加一个新面板 / 新卡片」不需要迁移已存的布局，也不会被旧记录挡住。
class WorkspaceBoardLayout {
  final Map<String, PanelLayout> panels;
  final Map<String, CardLayout> cards;

  const WorkspaceBoardLayout({
    this.panels = const <String, PanelLayout>{},
    this.cards = const <String, CardLayout>{},
  });

  PanelLayout? panelLayout(String panelId) => panels[panelId];

  CardLayout? cardLayout(String cardId) => cards[cardId];

  bool get isEmpty => panels.isEmpty && cards.isEmpty;

  WorkspaceBoardLayout withPanel(String panelId, PanelLayout layout) {
    final updated = Map<String, PanelLayout>.from(panels);
    updated[panelId] = layout;
    return WorkspaceBoardLayout(panels: updated, cards: cards);
  }

  WorkspaceBoardLayout withCard(String cardId, CardLayout layout) {
    final updated = Map<String, CardLayout>.from(cards);
    updated[cardId] = layout;
    return WorkspaceBoardLayout(panels: panels, cards: updated);
  }

  WorkspaceBoardLayout withoutPanel(String panelId) {
    if (!panels.containsKey(panelId)) return this;
    final updated = Map<String, PanelLayout>.from(panels)..remove(panelId);
    return WorkspaceBoardLayout(panels: updated, cards: cards);
  }

  // ── 面板 ────────────────────────────────────────────────────────────────

  /// 把 [panelId] 放到 [side] 侧的 [siblingIds] 里的 [insertIndex] 位，
  /// 并把该侧所有面板按新顺序**重新编号**。
  ///
  /// [siblingIds] 是**目标侧除了它以外**的其它面板（按当前显示顺序）。
  /// 拖动重排与「拖到另一条泳道」都走这一个口子：前者是同一侧换下标，
  /// 后者只是 [side] 变了 —— 两种手势的记账完全一样，不必写两遍。
  WorkspaceBoardLayout placePanel({
    required String panelId,
    required WorkspacePanelSide side,
    required List<String> siblingIds,
    required int insertIndex,
  }) {
    final ordered = List<String>.from(siblingIds);
    final index = insertIndex.clamp(0, ordered.length);
    ordered.insert(index, panelId);

    final updated = Map<String, PanelLayout>.from(panels);
    for (var i = 0; i < ordered.length; i++) {
      final id = ordered[i];
      final current = updated[id];
      updated[id] = current == null
          ? PanelLayout(visible: true, order: i, side: side)
          : current.copyWith(order: i, side: side, visible: true);
    }
    return WorkspaceBoardLayout(panels: updated, cards: cards);
  }

  /// 显示 / 隐藏一个面板。
  WorkspaceBoardLayout setPanelVisible({
    required String panelId,
    required WorkspacePanelSide side,
    required int order,
    required bool visible,
  }) {
    return withPanel(
      panelId,
      (panels[panelId] ??
              PanelLayout(visible: visible, order: order, side: side))
          .copyWith(visible: visible, side: side, order: order),
    );
  }

  // ── 卡片 ────────────────────────────────────────────────────────────────

  /// 在**同一面板内**把 [cardId] 上移（-1）或下移（+1）一格。
  ///
  /// [orderedCardIds] 是该面板当前显示的卡片 id 顺序。
  /// 到头了就返回 `null` —— 调用方据此把「上移 / 下移」按钮置灰，
  /// 而不是把一个什么都没做的状态推出去。
  WorkspaceBoardLayout? moveCard(
    String cardId,
    int direction,
    List<String> orderedCardIds,
  ) {
    final currentIndex = orderedCardIds.indexOf(cardId);
    if (currentIndex < 0) return null;
    final destinationIndex = currentIndex + direction;
    if (destinationIndex < 0 || destinationIndex >= orderedCardIds.length) {
      return null;
    }

    final next = List<String>.from(orderedCardIds);
    final moved = next[currentIndex];
    next[currentIndex] = next[destinationIndex];
    next[destinationIndex] = moved;

    final updated = Map<String, CardLayout>.from(cards);
    for (var i = 0; i < next.length; i++) {
      final id = next[i];
      final existing = updated[id];
      final fallback = _defaultCardLayoutFor(cardId);
      updated[id] = (existing ?? fallback).copyWith(order: i);
    }
    return WorkspaceBoardLayout(panels: panels, cards: updated);
  }

  /// 把一张卡**搬到另一个面板**（或同一面板的指定下标）。
  ///
  /// [siblingCardIds] 是目标面板里**除它以外**的卡片（按当前显示顺序）。
  /// [fallbackFor] 给出「这张卡还没有布局记录时该用什么」——
  /// 调用方（注册表）知道每张卡的默认面板与默认顺序，本文件不该猜。
  WorkspaceBoardLayout placeCard({
    required String cardId,
    required String panelId,
    required List<String> siblingCardIds,
    required int insertIndex,
    required CardLayout Function(String cardId) fallbackFor,
  }) {
    final ordered = List<String>.from(siblingCardIds);
    final index = insertIndex.clamp(0, ordered.length);
    ordered.insert(index, cardId);

    final updated = Map<String, CardLayout>.from(cards);
    for (var i = 0; i < ordered.length; i++) {
      final id = ordered[i];
      final existing = updated[id] ?? fallbackFor(id);
      updated[id] = existing.copyWith(order: i, panelId: panelId, visible: true);
    }
    return WorkspaceBoardLayout(panels: panels, cards: updated);
  }

  /// 显示 / 隐藏一张卡。
  WorkspaceBoardLayout setCardVisible({
    required String cardId,
    required String panelId,
    required int order,
    required bool visible,
  }) {
    return withCard(
      cardId,
      (cards[cardId] ??
              CardLayout(panelId: panelId, visible: visible, order: order))
          .copyWith(visible: visible, panelId: panelId, order: order),
    );
  }

  /// 折叠 / 展开一张卡。
  WorkspaceBoardLayout setCardExpanded({
    required String cardId,
    required String panelId,
    required int order,
    required bool expanded,
  }) {
    return withCard(
      cardId,
      (cards[cardId] ??
              CardLayout(panelId: panelId, visible: true, order: order))
          .copyWith(expanded: expanded),
    );
  }

  /// 只用于「这张卡第一次被拖动、布局里还没有它的记录」时的兜底值。
  /// 真正的默认值来自卡片注册表；这里只需要一个不会崩的占位。
  static CardLayout _defaultCardLayoutFor(String cardId) {
    return const CardLayout(panelId: '', visible: true, order: 0);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'panels': <String, Object?>{
      for (final entry in panels.entries)
        entry.key: <String, Object?>{
          'visible': entry.value.visible,
          'order': entry.value.order,
          'side': entry.value.side.name,
        },
    },
    'cards': <String, Object?>{
      for (final entry in cards.entries)
        entry.key: <String, Object?>{
          'panelId': entry.value.panelId,
          'visible': entry.value.visible,
          'order': entry.value.order,
          'expanded': entry.value.expanded,
        },
    },
  };

  /// 从 JSON 还原**只存改动过项**的记账。
  ///
  /// 非法项**整条丢掉**而不是补默认值：这套记账的语义是「空账 = 全用注册表里的
  /// 默认值」，所以丢掉一条非法项恰好就是「这一项回到默认」，而补一条假的记录
  /// 反而会把某个面板钉在一个不属于它的位置上。
  factory WorkspaceBoardLayout.fromJson(Map<String, Object?> json) {
    final panels = <String, PanelLayout>{};
    final rawPanels = json['panels'];
    if (rawPanels is Map) {
      for (final entry in rawPanels.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! Map) continue;
        final visible = value['visible'];
        final order = value['order'];
        final side = WorkspacePanelSide.tryParse('${value['side']}');
        if (visible is! bool || order is! int || side == null) continue;
        panels[key] = PanelLayout(visible: visible, order: order, side: side);
      }
    }

    final cards = <String, CardLayout>{};
    final rawCards = json['cards'];
    if (rawCards is Map) {
      for (final entry in rawCards.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! Map) continue;
        final panelId = value['panelId'];
        final visible = value['visible'];
        final order = value['order'];
        final expanded = value['expanded'];
        if (panelId is! String || visible is! bool || order is! int) continue;
        cards[key] = CardLayout(
          panelId: panelId,
          visible: visible,
          order: order,
          expanded: expanded is bool ? expanded : true,
        );
      }
    }

    // 面板 id / 卡片 id 是否还在注册表里由**调用方**决定：本文件是纯记账，
    // 不该认识注册表（否则「加一个新面板」会牵动这里的解析）。
    return WorkspaceBoardLayout(panels: panels, cards: cards);
  }

  @override
  String toString() =>
      'WorkspaceBoardLayout(panels: $panels, cards: $cards)';
}

/// 按 [orderOf] 给 id 排序；[orderOf] 相同则按 id 字典序 ——
/// **顺序必须是全序**，否则同一份配置在不同构建里会排出不同的轨，
/// 图标的相对位置就会莫名其妙地漂。
List<String> sortByOrder(Iterable<String> ids, int Function(String id) orderOf) {
  final list = List<String>.from(ids);
  list.sort((a, b) {
    final byOrder = orderOf(a).compareTo(orderOf(b));
    return byOrder != 0 ? byOrder : a.compareTo(b);
  });
  return list;
}
