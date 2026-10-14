/// 「设置搜索 → 精准定位」管道的第一个落点：这一页的每一行都得有可定位的 id。
///
/// # 为什么这条要跑在真页面上
/// 机制层的尺（`test/setting/setting_entry_list_test.dart`）只能证明
/// 「给了 id 就能定位」，它证明不了这一页**有没有漏登记某一行**。
/// 漏一行的话，将来搜索点进去只会停在上一条，而页面看起来完全正常。
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_entry.dart';
import 'package:zephyr/page/setting/common/setting_entry_list.dart';
import 'package:zephyr/page/setting/global/app_behavior_setting_page.dart';
import 'package:zephyr/workspace/model/workspace_startup.dart';

/// 页面上声明过的全部 id（含被平台条件挡掉的那几条）。
const _declaredIds = <String>[
  'behavior.splashPage',
  'behavior.workspaceSleepCoveredUi',
  'behavior.skipUpdateCheck',
  'behavior.desktopCloseBehavior',
  'behavior.androidKeepAlive',
  'behavior.backPressExit',
  'behavior.appLock',
  'behavior.oldPageRollback',
  'behavior.cloudFavoritePreferred',
  'behavior.autoFollowOnCollect',
  'behavior.autoFavoriteOnDownload',
  'behavior.writeDownloadMetadataFile',
  'behavior.leftHandMode',
  'behavior.clickCoverToStartReading',
  'behavior.searchHistoryGroupBySource',
  'behavior.comicInfoInlineReadButton',
  'behavior.comicInfoRailLiquidGlass',
];

/// 只有这一页会因平台条件缺席的行。桌面测试机上 16 条里少这两条，
/// 不是漏登记 —— 所以期望值要按同样的条件筛一遍。
const _androidOnlyIds = <String>[
  'behavior.androidKeepAlive',
  'behavior.backPressExit',
];

/// 未登记 id 的行，只允许是这两种装饰行：章节标题、尾部留白。
/// 别的类型冒出来就是有人新加了一行没给 id。
List<Widget> _unregisteredRows(List<Widget> children) {
  return [
    for (final child in children)
      if (child.key is! SettingEntryKey &&
          child.runtimeType != Padding &&
          child.runtimeType != SizedBox)
        child,
  ];
}

List<Widget> _childrenOfPage(WidgetTester tester) {
  // 行现在装在分组卡里：卡是 SettingEntryList 的一个下标，不是「一行」。
  // 数的必须是拆开后的行，否则漏登记的行会藏在卡里数不到。
  return flattenSettingEntries(
    tester.widget<SettingEntryList>(find.byType(SettingEntryList)).children,
  );
}

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(
    BlocProvider(
      create: (_) => GlobalSettingCubit(),
      child: MaterialApp(home: const AppBehaviorSettingPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => settingFocusRequest.value = null);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('这一页没有未登记的设置行', (tester) async {
    await _pumpPage(tester);

    final children = _childrenOfPage(tester);
    expect(
      _unregisteredRows(children),
      isEmpty,
      reason: '这几行没包 settingEntry(...)，将来搜索点到它们只会停在上一条',
    );

    final ids = settingEntryIds(children);
    final workspaceAvailable = workspaceAvailableOnDevice(
      tester.element(find.byType(SettingEntryList)),
    );
    final expected = _declaredIds
        .where(
          (id) =>
              (Platform.isAndroid || !_androidOnlyIds.contains(id)) &&
              (workspaceAvailable || id != 'behavior.workspaceSleepCoveredUi'),
        )
        .toList();
    expect(ids, expected, reason: '登记的 id 应与这一页真正渲染出来的行一一对应');
    expect(ids.toSet().length, ids.length, reason: 'id 撞了的话定位只会跳到先出现的那一行');
  });

  test('阳性对照：漏包一行的列表会被上面那条抓到', () {
    final children = <Widget>[
      settingEntry('behavior.a', const Text('A')),
      SwitchListTile(
        value: false,
        onChanged: (_) {},
        title: const Text('忘了给 id 的新行'),
      ),
    ];
    expect(_unregisteredRows(children), hasLength(1));
  });

  testWidgets('按 id 请求：目标行真的换到屏幕上', (tester) async {
    await _pumpPage(tester);
    // 挑一条**每个平台都在**、又排在靠后的行：`behavior.*` 里最后一条非桌面专属的。
    // 用「树上最后一条」当目标的话，期望文案就得跟着平台变，测起来反而像在赌平台。
    const targetId = 'behavior.searchHistoryGroupBySource';
    final targetKey = find.byKey(const SettingEntryKey(targetId));
    final viewport = tester.getRect(find.byType(ListView));

    // 先证「它在视口外」。行的现在装在一张分组卡里，而一张卡只是一个列表下标，
    // 卡里的行会跟着卡一起被建出来 —— 所以这里只能用几何（在视口下方），
    // 不能再用「树上找不到」当对照，那样量的已经不是「画面上有没有」。
    expect(tester.getRect(targetKey).top, greaterThanOrEqualTo(viewport.bottom));

    settingFocusRequest.value = targetId;
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(targetKey, findsOneWidget);
    expect(
      find.text(t.settings.searchHistoryGroupBySource),
      findsOneWidget,
      reason: '画面上得真换了，不是只动了个值',
    );
    expect(tester.getRect(targetKey).overlaps(viewport), isTrue);
    expect(settingFocusRequest.value, isNull);
  });

  testWidgets('不认识的 id 不认领、也不动', (tester) async {
    await _pumpPage(tester);
    final splashRow = find.byKey(const SettingEntryKey('behavior.splashPage'));
    final targetRow = find.byKey(
      const SettingEntryKey('behavior.searchHistoryGroupBySource'),
    );
    final before = tester.getRect(splashRow);
    final targetBefore = tester.getRect(targetRow);

    settingFocusRequest.value = 'behavior.definitelyNotARow';
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(
      settingFocusRequest.value,
      'behavior.definitelyNotARow',
      reason: '别人的请求要留着',
    );
    expect(tester.getRect(splashRow), before);
    expect(
      tester.getRect(targetRow),
      targetBefore,
      reason: '别人的 id 不该把本页滚走',
    );
  });
}
