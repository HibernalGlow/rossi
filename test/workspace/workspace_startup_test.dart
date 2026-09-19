import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/workspace/model/workspace_startup.dart';

/// 「启动时直接打开工作台」的判据。
///
/// 这一层刻意**不碰** `NavigationBar`：那一页依赖 ObjectBox、通知、下载队列，
/// 本机起不来（`libobjectbox.dylib` 基线红）。所以落点判定抽成纯函数，
/// 界面那一侧只负责「按判定结果做动作」。
void main() {
  group('resolveStartupLanding', () {
    test('开关关着：任何情况下都落在导航栏（默认关 = 改造前的行为）', () {
      for (final hasEntry in [true, false]) {
        expect(
          resolveStartupLanding(
            startWithWorkspace: false,
            workspaceEntryAvailable: hasEntry,
          ),
          StartupLanding.navigationBar,
          reason: 'hasEntry=$hasEntry',
        );
      }
    });

    test('本机没有工作台入口：开关开着也不去工作台', () {
      expect(
        resolveStartupLanding(
          startWithWorkspace: true,
          workspaceEntryAvailable: false,
        ),
        StartupLanding.navigationBar,
      );
    });

    test('两个条件都成立才去工作台', () {
      expect(
        resolveStartupLanding(
          startWithWorkspace: true,
          workspaceEntryAvailable: true,
        ),
        StartupLanding.workspace,
      );
    });

    test('不变式：入口为假时，开关取任何值都不会进工作台', () {
      for (final enabled in [true, false]) {
        expect(
          resolveStartupLanding(
            startWithWorkspace: enabled,
            workspaceEntryAvailable: false,
          ),
          isNot(StartupLanding.workspace),
          reason: 'startWithWorkspace=$enabled',
        );
      }
    });
  });

  group('isWorkspaceDesktopPlatform', () {
    test('桌面三平台都算有入口', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      ]) {
        expect(
          isWorkspaceDesktopPlatform(platform),
          isTrue,
          reason: '$platform',
        );
      }
    });

    test('其余平台都不算，且两张表合起来覆盖 TargetPlatform 全集', () {
      const desktop = {
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      };
      final others = TargetPlatform.values
          .where((platform) => !desktop.contains(platform))
          .toList();
      expect(desktop.length + others.length, TargetPlatform.values.length);
      expect(others, isNotEmpty);
      for (final platform in others) {
        expect(
          isWorkspaceDesktopPlatform(platform),
          isFalse,
          reason: '$platform',
        );
      }
    });
  });

  group('hasWorkspaceEntry', () {
    Future<bool> probe(WidgetTester tester, {required Size size}) async {
      late bool result;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: Builder(
            builder: (context) {
              result = hasWorkspaceEntry(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return result;
    }

    /// 平台覆写要在**测试体内**复位，别用 `addTearDown`：`TestWidgetsFlutterBinding`
    /// 在测试体结束、tearDown 之前就校验 foundation 变量已清空
    /// （`debugAssertAllFoundationVarsUnset`），用 tearDown 会以「测试失败」收场。
    Future<void> withPlatform(
      TargetPlatform platform,
      Future<void> Function() body,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    }

    testWidgets('窄窗口 + 手机平台：没有入口（开关在那边不落地）', (tester) async {
      await withPlatform(TargetPlatform.android, () async {
        expect(await probe(tester, size: const Size(400, 800)), isFalse);
      });
    });

    testWidgets('窄窗口 + 桌面平台：仍有入口（四边栏布局不看宽度）', (tester) async {
      await withPlatform(TargetPlatform.macOS, () async {
        expect(await probe(tester, size: const Size(400, 800)), isTrue);
      });
    });

    testWidgets('平板宽度 + 手机平台：有入口', (tester) async {
      await withPlatform(TargetPlatform.android, () async {
        expect(await probe(tester, size: const Size(900, 1200)), isTrue);
      });
    });
  });

  group('开屏页下拉（工作台并进了那一条）', () {
    test('哨兵不占标签页编号空间', () {
      expect(splashWorkspaceOption, lessThan(0));
    });

    test('开关开 + 有入口：下拉显示「工作台」', () {
      expect(
        resolveSplashDropdownValue(
          startWithWorkspace: true,
          workspaceEntryAvailable: true,
          welcomePageNum: 2,
        ),
        splashWorkspaceOption,
      );
    });

    test('开关关：下拉显示原来那个标签页', () {
      expect(
        resolveSplashDropdownValue(
          startWithWorkspace: false,
          workspaceEntryAvailable: true,
          welcomePageNum: 2,
        ),
        2,
      );
    });

    test('没有入口：开关开着也显示标签页（手机端显示了也落不了地）', () {
      expect(
        resolveSplashDropdownValue(
          startWithWorkspace: true,
          workspaceEntryAvailable: false,
          welcomePageNum: 2,
        ),
        2,
      );
    });

    test('选「工作台」：打开开关，且不动退出后的落回标签页', () {
      final next = resolveSplashSelection(
        selected: splashWorkspaceOption,
        currentWelcomePageNum: 2,
      );
      expect(next.startWithWorkspace, isTrue);
      expect(next.welcomePageNum, 2);
    });

    test('选某个标签页：关掉开关并记下这个编号', () {
      final next = resolveSplashSelection(selected: 1, currentWelcomePageNum: 2);
      expect(next.startWithWorkspace, isFalse);
      expect(next.welcomePageNum, 1);
    });

    test('往返一致：选完之后再读回来还是同一项', () {
      for (final startWithWorkspace in [true, false]) {
        for (final welcomePageNum in [0, 1, 2]) {
          final selected = resolveSplashDropdownValue(
            startWithWorkspace: startWithWorkspace,
            workspaceEntryAvailable: true,
            welcomePageNum: welcomePageNum,
          );
          final next = resolveSplashSelection(
            selected: selected,
            currentWelcomePageNum: welcomePageNum,
          );
          expect(
            resolveSplashDropdownValue(
              startWithWorkspace: next.startWithWorkspace,
              workspaceEntryAvailable: true,
              welcomePageNum: next.welcomePageNum,
            ),
            selected,
            reason: 'start=$startWithWorkspace page=$welcomePageNum',
          );
        }
      }
    });
  });

  group('设置字段', () {
    test('默认关 —— 没进过设置页的用户启动落点不变', () {
      expect(const GlobalSettingState().startWithWorkspace, isFalse);
    });

    test('copyWith 只动这一个字段', () {
      const base = GlobalSettingState();
      final next = base.copyWith(startWithWorkspace: true);
      expect(next.startWithWorkspace, isTrue);
      expect(next.welcomePageNum, base.welcomePageNum);
      expect(next.oldPageRollbackEnabled, base.oldPageRollbackEnabled);
      expect(next.comicInfoInlineReadButton, base.comicInfoInlineReadButton);
      expect(next.leftHandModeEnabled, base.leftHandModeEnabled);
    });
  });
}
