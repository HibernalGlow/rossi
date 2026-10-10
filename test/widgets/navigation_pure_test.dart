import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/widgets/navigation/navigation_entries.dart';
import 'package:zephyr/widgets/navigation/navigation_layout.dart';

/// 导航栏「走哪一支」与「两段各摆哪几条」的判据。
///
/// 这一层全是纯函数（不挂 app、不碰 ObjectBox、不碰 i18n 词条），所以能秒级
/// 跑完 —— 而这几条边界（阈值的开闭区间、越界阈值、主区被删到只剩一条页面、
/// 关掉旧版页面后残留的旧页、动作与页面混排、底部快捷区的「没设置过」与
/// 「全隐藏」分不分得开）恰恰是起整个 app 点不出来的。
///
/// 组件本体（侧栏 / Dock / 弹窗）的渲染不在这里：那部分要真帧，见
/// `test/widgets/navigation_shell_test.dart`。
void main() {
  const sidebar = NavigationLayout.sidebar;
  const mobile = NavigationLayout.mobile;

  NavigationLayout resolve({
    bool sidebarCapable = true,
    double width = 1200,
    bool autoSwitchOnNarrow = true,
    double narrowWidth = kDefaultNarrowNavigationWidth,
  }) => resolveNavigationLayout(
    sidebarCapable: sidebarCapable,
    width: width,
    autoSwitchOnNarrow: autoSwitchOnNarrow,
    narrowWidth: narrowWidth,
  );

  group('resolveNavigationLayout —— 平台能力先于宽度', () {
    test('手机（不适合侧栏）不读宽度：横屏再宽也不长出侧栏', () {
      expect(
        resolve(sidebarCapable: false, width: 4000),
        mobile,
        reason: '4 千像素宽的手机横屏也仍然是移动端布局',
      );
      expect(
        resolve(sidebarCapable: false, width: 4000, autoSwitchOnNarrow: false),
        mobile,
      );
    });

    test('够格走侧栏但关掉自动切：窗口再窄也留在侧栏', () {
      expect(
        resolve(width: 400, autoSwitchOnNarrow: false),
        sidebar,
        reason: '开关关着时「窄」不参与判定',
      );
    });

    test('自动切打开：窄于阈值才切', () {
      expect(resolve(width: 1200, narrowWidth: 600), sidebar);
      expect(resolve(width: 600, narrowWidth: 600), sidebar, reason: '是「小于」不是「小于等于」');
      expect(resolve(width: 599, narrowWidth: 600), mobile);
    });
  });

  group('窄屏阈值', () {
    test('越界一律夹取到可调范围', () {
      expect(clampNarrowNavigationWidth(10), kMinNarrowNavigationWidth);
      expect(
        clampNarrowNavigationWidth(kMaxNarrowNavigationWidth + 1),
        kMaxNarrowNavigationWidth,
      );
      expect(clampNarrowNavigationWidth(800), 800);
    });

    test('夹取在判定里生效，而不是判定之后才知道越界', () {
      // 存了个 5（老版本 / 云端同步来的）：夹到 320 之后，300 宽的窗口是窄屏。
      expect(resolve(width: 300, narrowWidth: 5), mobile);
      // 存了个超大值：夹到 1600 之后，1200 宽的窗口也是窄屏。
      expect(resolve(width: 1200, narrowWidth: 99999), mobile);
    });
  });

  group('条目身份', () {
    test('页面与动作分得开，且每一条都有唯一的持久化名字', () {
      expect(NavigationEntryId.bookshelf.isPage, isTrue);
      expect(NavigationEntryId.oldRank.isPage, isTrue);
      expect(NavigationEntryId.workspace.isAction, isTrue);
      expect(NavigationEntryId.search.isAction, isTrue);
      // 「自定义导航」以前是侧栏底部写死的按钮，现在是一条普通动作 ——
      // 用户提的正是「它也该能隐藏 / 换位置」。
      expect(NavigationEntryId.customizeNavigation.isAction, isTrue);
      // 持久化契约：`name` 是存进设置与云同步载荷里的那一份，重名 = 老用户的
      // 选择会解析到另一条上。
      final names = [for (final id in NavigationEntryId.values) id.name];
      expect(names.toSet().length, names.length);
    });

    test('动作那几个不是视图：build() 给出空盒子', () {
      for (final id in NavigationEntryId.values) {
        if (!id.isAction) continue;
        expect(id.build(), isA<SizedBox>(), reason: '${id.name} 不该是一页');
      }
    });

    test('旧版页面那两条仍然只属于旧版那一套', () {
      expect(NavigationEntryId.oldHome.legacyOnly, isTrue);
      expect(NavigationEntryId.oldRank.legacyOnly, isTrue);
      expect(NavigationEntryId.workspace.legacyOnly, isFalse);
    });
  });

  group('主区清单', () {
    final allowed = availableNavigationEntries(false);
    final allowedWithLegacy = availableNavigationEntries(true);
    final fallback = defaultNavigationEntries(false);

    test('出厂口径：主区三条页面；可选全集 = 三条页面 + 五个动作', () {
      expect(fallback, [
        NavigationEntryId.bookshelf,
        NavigationEntryId.discover,
        NavigationEntryId.more,
      ]);
      // 全集是**枚举顺序**（= 「待添加」列表的顺序），不是出厂清单的顺序：
      // 出厂清单把旧首页 / 旧排行摆在前头，而待添加列表先给新版三页再给动作。
      expect(allowed, [
        NavigationEntryId.bookshelf,
        NavigationEntryId.discover,
        NavigationEntryId.more,
        NavigationEntryId.workspace,
        NavigationEntryId.openLocalComic,
        NavigationEntryId.gpuPresent,
        NavigationEntryId.search,
        NavigationEntryId.customizeNavigation,
      ]);
      expect(allowedWithLegacy, [
        NavigationEntryId.bookshelf,
        NavigationEntryId.discover,
        NavigationEntryId.more,
        NavigationEntryId.oldHome,
        NavigationEntryId.oldRank,
        NavigationEntryId.workspace,
        NavigationEntryId.openLocalComic,
        NavigationEntryId.gpuPresent,
        NavigationEntryId.search,
        NavigationEntryId.customizeNavigation,
      ]);
      expect(defaultNavigationEntries(true), [
        NavigationEntryId.oldHome,
        NavigationEntryId.oldRank,
        ...fallback,
      ]);
      // 动作默认**不进主区**：开箱观感与改造前一致，动作留在底部快捷区。
      expect(fallback.where((id) => id.isAction), isEmpty);
    });

    test('认不出的 id 与重复项都丢掉', () {
      expect(
        resolveNavigationEntryIds(
          stored: ['bookshelf', 'nope', 'bookshelf', 'discover'],
          allowed: allowed,
          fallback: fallback,
        ),
        [NavigationEntryId.bookshelf, NavigationEntryId.discover],
      );
    });

    test('关掉旧版页面之后，清单里残留的旧页不再占位', () {
      expect(
        resolveNavigationEntryIds(
          stored: ['oldHome', 'bookshelf', 'oldRank'],
          allowed: allowed,
          fallback: fallback,
        ),
        [NavigationEntryId.bookshelf],
        reason: 'allowed 之外的一律丢掉，否则关掉开关后旧页还在侧栏上',
      );
    });

    test('一条不剩就退回出厂清单（空清单不是「用户想清空」）', () {
      expect(
        resolveNavigationEntryIds(
          stored: const [],
          allowed: allowed,
          fallback: fallback,
        ),
        fallback,
      );
      expect(
        resolveNavigationEntryIds(
          stored: const ['nope'],
          allowed: allowed,
          fallback: fallback,
        ),
        fallback,
      );
    });

    test('主区里一条页面都不剩也退回出厂清单（全动作等于没有导航）', () {
      expect(
        resolveNavigationEntryIds(
          stored: const ['workspace', 'search'],
          allowed: allowed,
          fallback: fallback,
        ),
        fallback,
        reason: '动作点了不换页 —— 一屏动作就没有「当前视图」可指了',
      );
      // 阳性对照：**有**页面时动作照常留着（含它在清单里的位置）。
      expect(
        resolveNavigationEntryIds(
          stored: const ['workspace', 'bookshelf', 'search'],
          allowed: allowed,
          fallback: fallback,
        ),
        [
          NavigationEntryId.workspace,
          NavigationEntryId.bookshelf,
          NavigationEntryId.search,
        ],
      );
    });

    test('存进去的形状就是 id 字符串（持久化契约）', () {
      expect(encodeNavigationEntryIds([NavigationEntryId.more]), ['more']);
      expect(
        encodeNavigationEntryIds([NavigationEntryId.customizeNavigation]),
        ['customizeNavigation'],
      );
      expect(
        decodeNavigationEntryIds(
          encodeNavigationEntryIds(allowedWithLegacy),
          allowed: allowedWithLegacy,
          fallback: fallback,
        ),
        allowedWithLegacy,
      );
    });

    test('下限是两条**页面**：删到下限返回 null（调用方据此禁用按钮）', () {
      // 三条删一条：可以。
      expect(
        toggleNavigationEntry([
          NavigationEntryId.bookshelf,
          NavigationEntryId.discover,
          NavigationEntryId.more,
        ], NavigationEntryId.more),
        [NavigationEntryId.bookshelf, NavigationEntryId.discover],
      );
      // 两条页面再删：拒绝（旧版手机底栏 `PersistentTabView` 只渲染页面、
      // 且断言 2..6 条，所以下限按页面数算而不是条目数）。
      expect(
        toggleNavigationEntry(
          [NavigationEntryId.bookshelf, NavigationEntryId.discover],
          NavigationEntryId.discover,
        ),
        isNull,
      );
      // **动作不算进下限**：两条页面 + 一个动作，动作能删，页面不能。
      final twoPagesPlusAction = [
        NavigationEntryId.bookshelf,
        NavigationEntryId.discover,
        NavigationEntryId.workspace,
      ];
      expect(
        toggleNavigationEntry(twoPagesPlusAction, NavigationEntryId.workspace),
        [NavigationEntryId.bookshelf, NavigationEntryId.discover],
      );
      expect(
        toggleNavigationEntry(twoPagesPlusAction, NavigationEntryId.bookshelf),
        isNull,
        reason: '删完只剩一条页面，旧版底栏那支会断言失败',
      );
      // 不在清单里就是添加，不受下限影响。
      expect(
        toggleNavigationEntry([
          NavigationEntryId.bookshelf,
        ], NavigationEntryId.discover),
        [NavigationEntryId.bookshelf, NavigationEntryId.discover],
      );
    });

    test('不在清单里的条目不谈删', () {
      const list = [NavigationEntryId.bookshelf, NavigationEntryId.discover];
      expect(canRemoveNavigationEntry(list, NavigationEntryId.more), isFalse);
      expect(toggleNavigationEntry(list, NavigationEntryId.more), [
        NavigationEntryId.bookshelf,
        NavigationEntryId.discover,
        NavigationEntryId.more,
      ]);
    });

    test('排序按「先摘后插」，越界一律当没动', () {
      final list = [
        NavigationEntryId.bookshelf,
        NavigationEntryId.discover,
        NavigationEntryId.more,
      ];
      expect(
        reorderNavigationEntry(list, 0, 2),
        [
          NavigationEntryId.discover,
          NavigationEntryId.more,
          NavigationEntryId.bookshelf,
        ],
      );
      // 越界的 newIndex 夹到末尾（拖到列表下方空白处不该丢条目）
      expect(reorderNavigationEntry(list, 0, 99).last, NavigationEntryId.bookshelf);
      // 越界的 oldIndex 当没动
      expect(reorderNavigationEntry(list, 9, 0), list);
      expect(reorderNavigationEntry(list, 1, 1), list);
    });
  });

  group('底部快捷区清单', () {
    final allowed = availableNavigationEntries(false);
    final fallback = defaultNavigationActions(allowed);

    test('出厂：与改造前侧栏底部那块逐条一致，只多一条「自定义导航」', () {
      expect(fallback, [
        NavigationEntryId.openLocalComic,
        NavigationEntryId.gpuPresent,
        NavigationEntryId.search,
        NavigationEntryId.customizeNavigation,
      ]);
      expect(fallback.every((id) => id.isAction), isTrue);
      // 出厂清单只取这台设备可选的。
      expect(
        defaultNavigationActions(const [NavigationEntryId.search]),
        [NavigationEntryId.search],
        reason: 'allowed 之外的（这里是旧版页面与其余动作）不该混进来',
      );
    });

    test('`null` = 没设置过（用出厂）；`[]` = 用户全隐藏了（真的是空的）', () {
      expect(
        resolveNavigationActionIds(
          stored: null,
          allowed: allowed,
          fallback: fallback,
        ),
        fallback,
      );
      expect(
        resolveNavigationActionIds(
          stored: const [],
          allowed: allowed,
          fallback: fallback,
        ),
        isEmpty,
        reason: '这两件事分不开的话，用户永远关不掉底部那一块',
      );
      expect(
        resolveNavigationActionIds(
          stored: null,
          allowed: allowed,
          fallback: const [],
        ),
        isEmpty,
      );
    });

    test('只收动作：页面 / 认不出的 / 重复的混进来都丢掉', () {
      expect(
        resolveNavigationActionIds(
          stored: const ['search', 'bookshelf', 'nope', 'search'],
          allowed: allowed,
          fallback: fallback,
        ),
        [NavigationEntryId.search],
        reason: '底部那一段只放动作 —— 页面的位置在主区',
      );
      expect(
        resolveNavigationActionIds(
          stored: const ['oldHome', 'gpuPresent'],
          allowed: allowed,
          fallback: fallback,
        ),
        [NavigationEntryId.gpuPresent],
        reason: '旧版页面本来就不是动作',
      );
    });

    test('增删没有下限：全隐藏是合法的', () {
      expect(
        toggleNavigationAction(fallback, NavigationEntryId.search),
        [
          NavigationEntryId.openLocalComic,
          NavigationEntryId.gpuPresent,
          NavigationEntryId.customizeNavigation,
        ],
      );
      var list = fallback;
      for (final id in fallback) {
        list = toggleNavigationAction(list, id);
      }
      expect(list, isEmpty, reason: '动作全删光没事 —— 那时底部整块不出现');
      expect(
        toggleNavigationAction(const [], NavigationEntryId.workspace),
        [NavigationEntryId.workspace],
      );
    });

    test('编码往返：存的就是 id 字符串', () {
      expect(
        encodeNavigationEntryIds(fallback),
        ['openLocalComic', 'gpuPresent', 'search', 'customizeNavigation'],
      );
    });
  });
}
