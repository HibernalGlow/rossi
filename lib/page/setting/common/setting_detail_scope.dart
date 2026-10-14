import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:zephyr/icons/icons.dart';

/// 页内二级分组（或关键设置块）的元数据描述：
/// 既供侧栏可折叠子树展示与搜索直达匹配，也供页内 Scroll Spy 与吸顶目录胶囊同步。
class SettingSectionSpec {
  const SettingSectionSpec({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.keywords = const <String>[],
    this.icon,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<String> keywords;
  final Glyph? icon;

  bool matchesQuery(String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    final q = normalizedQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (title.toLowerCase().contains(q)) return true;
    if (subtitle.toLowerCase().contains(q)) return true;
    for (final keyword in keywords) {
      if (keyword.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  /// 返回命中的首个具体设置项关键词（若查询直接命中标题则返回 null，供搜索结果副标题提示）。
  String? matchedKeyword(String normalizedQuery) {
    final q = normalizedQuery.trim().toLowerCase();
    if (q.isEmpty) return null;
    if (title.toLowerCase().contains(q)) return null;
    for (final keyword in keywords) {
      if (keyword.toLowerCase().contains(q)) return keyword;
    }
    if (subtitle.toLowerCase().contains(q)) return subtitle;
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingSectionSpec &&
          other.id == id &&
          other.title == title &&
          other.subtitle == subtitle &&
          listEquals(other.keywords, keywords) &&
          other.icon == icon;

  @override
  int get hashCode =>
      Object.hash(id, title, subtitle, Object.hashAll(keywords), icon);
}

/// 跨双栏/单栏的页内分组同步桥：
/// 右侧详情页（[SettingPageShell]）通过它把 `scroll_spy` 算出的当前主分组与
/// 页内已挂载分组列表回写给左侧可折叠侧栏树。
class SettingDetailBridge {
  SettingDetailBridge();

  /// 每个页面（`pageId`）当前由 `scroll_spy` 选出的主分组 ID。
  final Map<String, ValueNotifier<String?>> _activeSectionByPage = {};

  /// 每个页面（`pageId`）当前已挂载的二级分组列表。
  final Map<String, ValueNotifier<List<SettingSectionSpec>>> _sectionsByPage =
      {};

  ValueNotifier<String?> activeSectionNotifier(String pageId) =>
      _activeSectionByPage.putIfAbsent(
        pageId,
        () => ValueNotifier<String?>(null),
      );

  ValueNotifier<List<SettingSectionSpec>> sectionsNotifier(String pageId) =>
      _sectionsByPage.putIfAbsent(
        pageId,
        () => ValueNotifier<List<SettingSectionSpec>>(const []),
      );

  void updateActiveSection(String pageId, String? sectionId) {
    final notifier = activeSectionNotifier(pageId);
    if (notifier.value != sectionId) {
      notifier.value = sectionId;
    }
  }

  void updateSections(String pageId, List<SettingSectionSpec> sections) {
    final notifier = sectionsNotifier(pageId);
    if (!listEquals(notifier.value, sections)) {
      notifier.value = List<SettingSectionSpec>.unmodifiable(sections);
    }
  }

  void dispose() {
    for (final notifier in _activeSectionByPage.values) {
      notifier.dispose();
    }
    for (final notifier in _sectionsByPage.values) {
      notifier.dispose();
    }
    _activeSectionByPage.clear();
    _sectionsByPage.clear();
  }
}

/// 仅改变当前分类页的外壳；设置状态与下一级路由仍复用原页面。
///
/// 在桌面/平板双栏模式下额外携带 [pageId]、预设 [declaredSections] 与 [bridge]，
/// 使页内 `scroll_spy` 能将当前阅读分组实时同步回左侧可折叠子树。
class SettingDetailScope extends InheritedWidget {
  const SettingDetailScope({
    super.key,
    required super.child,
    this.pageId,
    this.declaredSections = const <SettingSectionSpec>[],
    this.bridge,
  });

  final String? pageId;
  final List<SettingSectionSpec> declaredSections;
  final SettingDetailBridge? bridge;

  static bool isEmbedded(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingDetailScope>() != null;

  static SettingDetailScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingDetailScope>();

  @override
  bool updateShouldNotify(SettingDetailScope oldWidget) =>
      oldWidget.pageId != pageId ||
      !listEquals(oldWidget.declaredSections, declaredSections) ||
      oldWidget.bridge != bridge;
}
