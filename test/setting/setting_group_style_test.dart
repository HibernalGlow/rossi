/// 设置页的分组样式契约：迁到 M3E 分组的每一页，每一行都必须坐在分组表面里。
///
/// # 为什么这条要跑在真页面上
/// `SettingGroup` 自己的样子早就被别的页面证明过了，它证明不了某一页
/// **有没有把行塞进分组**。书架与同步原本是裸 `ListTile` + `Divider` 直接坐在
/// 页面底色（浅色主题下的纯白）上，和外观/提示/文件管理器/布局那几页的
/// 主题色分组表面（`surfaceContainerLow`）是两套样子。
///
/// # 加一页就往 `_migratedPages` 里加一条
/// 漏登记不会让这条变红，所以迁移进行中要靠 `script/check_setting_group_style.py`
/// 对着路由目的地清单查覆盖度；两边都过了才算这一页真的迁完。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/setting/bookshelf/bookshelf_setting_page.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/data_backup/data_backup_page.dart';
import 'package:zephyr/page/setting/global/app_behavior_setting_page.dart';
import 'package:zephyr/page/setting/cache/cache_setting_page.dart';
import 'package:zephyr/page/about/view/about_page.dart';
import 'package:zephyr/page/font_setting/view/font_setting_page.dart';
import 'package:zephyr/page/theme_color/view/theme_color_page.dart';
import 'package:zephyr/page/setting/global/content_network_setting_page.dart';
import 'package:zephyr/page/setting/global/eink_setting_page.dart';
import 'package:zephyr/page/setting/global/favorite_artist_setting_page.dart';
import 'package:zephyr/page/setting/global/favorite_tag_setting_page.dart';
import 'package:zephyr/page/setting/global/storage_setting_page.dart';
import 'package:zephyr/page/setting/global/notify_setting_page.dart';
import 'package:zephyr/page/setting/global/sync_setting_page.dart';
import 'package:zephyr/page/webdav_sync/view/webdav_sync_page.dart';

import '../test_helper.dart';

/// 已迁到分组样式的页面。`needsWebdavConfig` 的页面只有配好服务才会多出第二张卡。
///
/// 「缓存」那一页带一个算完才停的进度圈（缓存大小走 path_provider），测试里没有真
/// 目录，`pumpAndSettle` 会一直等到超时，所以它单独只泵固定几帧（见 `_pump`）。
///
/// # 这份表没覆盖到的两页
/// 「漫画翻译（OCR）」与「按键绑定」要过 Rust 桥（`RustLib.init`），测试里报
/// `Bad state: flutter_rust_bridge has not been initialized`；跑法是先
/// `./script/refresh_release_dylib.sh` 再把它们加回上面的表。在那之前这两页只有
/// `script/check_setting_group_style.py` 的文件级门禁（无 Divider / 有外壳 / 有分组）
/// 覆盖，「每一行都在卡内」这一条对它们是**未验**，不是已验。
const List<(String, Widget, {bool needsWebdavConfig})> _migratedPages = [
  ('同步', SyncSettingPage(), needsWebdavConfig: true),
  ('书架', BookshelfSettingPage(), needsWebdavConfig: false),
  ('数据备份', DataBackupPage(), needsWebdavConfig: false),
  ('应用行为', AppBehaviorSettingPage(), needsWebdavConfig: false),
  ('提示个性化', NotifySettingPage(), needsWebdavConfig: false),
  ('内容与网络', ContentNetworkSettingPage(), needsWebdavConfig: false),
  ('存储', StorageSettingPage(), needsWebdavConfig: false),
  ('喜欢画师管理', FavoriteArtistSettingPage(), needsWebdavConfig: false),
  ('收藏 tag 管理', FavoriteTagSettingPage(), needsWebdavConfig: false),
  ('墨水屏', EInkSettingPage(), needsWebdavConfig: false),
  ('缓存', CacheSettingPage(), needsWebdavConfig: false),
  ('字体设置', FontSettingPage(), needsWebdavConfig: false),
  ('主题色', ThemeColorPage(), needsWebdavConfig: false),
  ('关于应用', AboutPage(), needsWebdavConfig: false),
];

/// 落在分组之外的设置行数。
///
/// `SwitchListTile` 内部会 build 一颗 `ListTile`，全局数与分组内数都包含它，
/// 相减正好抵消，所以按类型各数一遍再取差集。
int _rowsOutsideGroup(WidgetTester tester) {
  var orphans = 0;
  for (final type in <Type>[ListTile, SwitchListTile]) {
    orphans +=
        tester.widgetList(find.byType(type)).length -
        tester
            .widgetList(
              find.descendant(
                of: find.byType(SettingGroup),
                matching: find.byType(type),
              ),
            )
            .length;
  }
  return orphans;
}

Future<void> _pump(
  WidgetTester tester,
  GlobalSettingCubit cubit,
  Widget page, {
  bool keepsSpinning = false,
}) async {
  await tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: MaterialApp(home: page),
    ),
  );
  if (keepsSpinning) {
    // 只泵两帧：树已经建出来了，结构断言用得上；等 settle 就是等一个不会来的回调。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return;
  }
  await tester.pumpAndSettle();
}

void main() {
  // 设置页的开关会经 `GlobalSettingCubit` 落库，没库就只能验到默认那半屏。
  setUpAll(TestObjectBoxHelper.setUpTestObjectBox);
  tearDownAll(TestObjectBoxHelper.tearDownTestObjectBox);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // cubit 的写库路径固定读 id=1 那行；测试库里没有就按 main 的做法种一行。
    if (objectbox.userSettingBox.get(1) == null) {
      objectbox.userSettingBox.put(UserSetting());
    }
  });

  for (final (name, page, needsWebdavConfig: needsWebdavConfig)
      in _migratedPages) {
    testWidgets('$name：每一行都在分组表面里，页面上没有 Divider', (tester) async {
      final cubit = GlobalSettingCubit();
      addTearDown(cubit.close);
      await _pump(tester, cubit, page, keepsSpinning: name == '缓存');

      expect(find.byType(SettingGroup), findsWidgets, reason: '$name 一张分组卡都没画');
      expect(find.byType(SettingPageShell), findsOneWidget);
      expect(_rowsOutsideGroup(tester), 0);
      expect(find.byType(Divider), findsNothing);

      if (needsWebdavConfig) {
        // 「已配置」要三样都齐（见 `WebDavSyncService.isConfigured`），
        // 只改服务类型的话这一屏仍然只画一张卡。
        cubit.updateSyncSetting(
          (current) => current.copyWith(
            syncServiceType: SyncServiceType.webdav,
            autoSync: true,
            webdavSetting: current.webdavSetting.copyWith(
              host: 'https://dav.example.com/breeze',
              username: 'tester',
              password: 'secret',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 这一页还在长（本地备份那块也搬进来了），所以数量只断言「至少两张卡」：
        // 这条要抓的是「有行落在分组之外」，不是这一屏此刻有几张卡。
        expect(find.byType(SettingGroup), findsAtLeastNWidgets(2));
        expect(_rowsOutsideGroup(tester), 0);
        expect(find.byType(Divider), findsNothing);
      }
    });
  }

  testWidgets('同步配置表单页也走外壳与分组，不再有裸 Scaffold', (tester) async {
    final cubit = GlobalSettingCubit();
    addTearDown(cubit.close);
    cubit.updateSyncSetting(
      (current) => current.copyWith(
        syncServiceType: SyncServiceType.webdav,
        webdavSetting: current.webdavSetting.copyWith(
          host: 'https://dav.example.com/breeze',
          username: 'tester',
          password: 'secret',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: WebDavSyncPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 表单坐在分组卡里（三个输入框都在同一张卡的分组表面之下）。
    expect(find.byType(SettingGroup), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SettingGroup),
        matching: find.byType(TextField),
      ),
      findsNWidgets(3),
    );
    expect(_rowsOutsideGroup(tester), 0);
    expect(find.byType(Divider), findsNothing);
    expect(find.byType(SettingPageShell), findsOneWidget);
  });

  testWidgets('阳性对照：裸行 + Divider 的老写法会被抓到', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              SettingGroup(
                title: '分组内',
                children: [ListTile(title: Text('在组里'))],
              ),
              ListTile(title: Text('忘了包进分组的一行')),
              Divider(height: 1),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_rowsOutsideGroup(tester), 1);
    expect(find.byType(Divider), findsOneWidget);
  });
}
