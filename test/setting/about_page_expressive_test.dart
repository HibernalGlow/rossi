import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/about/view/about_page.dart';
import 'package:zephyr/page/setting/common/setting_detail_scope.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';

void main() {
  tearDown(() {
    AboutPage.debugVersionLoader = null;
    AboutPage.debugContributorsLoader = null;
    AboutPage.debugUrlLauncher = null;
  });

  Widget buildSubject({
    Color seedColor = const Color(0xFF8B4148),
    Brightness brightness = Brightness.dark,
    double textScale = 1.0,
    bool embedded = false,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    Widget child = const AboutPage();
    if (embedded) {
      child = SettingDetailScope(child: child);
    }
    return MaterialApp(
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
      ),
      builder: (context, navigator) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: navigator!,
      ),
      home: child,
    );
  }

  testWidgets('使用全局 MD3E 主色调与动态 SVG 品牌图标，彻底移除静态图与荧光蓝配色', (tester) async {
    AboutPage.debugVersionLoader = () async => '0.1.0+1';
    AboutPage.debugContributorsLoader = () async => const [
      {
        'login': 'HibernalGlow',
        'contributions': 42,
        'avatar_url': '',
        'html_url': 'https://github.com/HibernalGlow',
      },
    ];

    for (final seed in const [Color(0xFF8B4148), Color(0xFF2E6B4E)]) {
      for (final brightness in Brightness.values) {
        final expectedScheme = ColorScheme.fromSeed(
          seedColor: seed,
          brightness: brightness,
        );
        await tester.pumpWidget(
          buildSubject(seedColor: seed, brightness: brightness),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SettingPageShell), findsOneWidget);
        expect(find.byType(SettingGroup), findsNWidgets(3));
        expect(find.byType(M3EList), findsNWidgets(3));
        expect(find.byType(ExpressiveIconBadge), findsWidgets);
        expect(find.byType(Divider), findsNothing);
        // 不再使用静态 asset/image/app-icon.png，改用跟随主题色的 BrandAppIcon
        expect(find.byType(BrandAppIcon), findsOneWidget);

        final brandIcon = tester.widget<BrandAppIcon>(
          find.byKey(const ValueKey('about-brand-icon')),
        );
        expect(brandIcon.foregroundColor, expectedScheme.primary);
        expect(brandIcon.backgroundColor, expectedScheme.primaryContainer);

        final heroContainer = tester.widget<Container>(
          find.byKey(const ValueKey('about-hero-card')),
        );
        final heroDecoration = heroContainer.decoration! as BoxDecoration;
        expect(heroDecoration.color, expectedScheme.surfaceContainerLow);
        expect(heroDecoration.borderRadius, expressiveCornerLg);
        expect(heroDecoration.boxShadow, isNull);

        final versionPill = tester.widget<Container>(
          find.byKey(const ValueKey('about-version-pill')),
        );
        final pillDecoration = versionPill.decoration! as ShapeDecoration;
        expect(pillDecoration.color, expectedScheme.primary);
        expect(pillDecoration.shape, isA<StadiumBorder>());

        expect(find.text(appDisplayName), findsOneWidget);
        expect(find.text(t.about.tagline), findsOneWidget);
        expect(find.text(t.about.version(version: '0.1.0+1')), findsOneWidget);
      }
    }
  });

  testWidgets('项目链接、贡献者芯片与免责声明弹层按 MD3E 交互工作', (tester) async {
    final launchedUrls = <String>[];
    AboutPage.debugVersionLoader = () async => '0.1.0';
    AboutPage.debugContributorsLoader = () async => const [
      {
        'login': 'HibernalGlow',
        'contributions': 128,
        'avatar_url': '',
        'html_url': 'https://github.com/HibernalGlow',
      },
    ];
    AboutPage.debugUrlLauncher = (url) async {
      launchedUrls.add(url);
    };

    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    // 点击项目地址、反馈、上游与许可证链接
    await tester.tap(find.byKey(const ValueKey('about-link:project')));
    await tester.pumpAndSettle();
    expect(launchedUrls.last, kProjectRepoUrl);

    await tester.tap(find.byKey(const ValueKey('about-link:feedback')));
    await tester.pumpAndSettle();
    expect(launchedUrls.last, kProjectIssuesUrl);

    await tester.tap(find.byKey(const ValueKey('about-link:upstream')));
    await tester.pumpAndSettle();
    expect(launchedUrls.last, kUpstreamRepoUrl);

    // 贡献者芯片展示与点击跳转
    expect(find.text('HibernalGlow'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('about-contributor:HibernalGlow')),
    );
    await tester.pumpAndSettle();
    expect(launchedUrls.last, 'https://github.com/HibernalGlow');

    await tester.ensureVisible(
      find.byKey(const ValueKey('about-link:license')),
    );
    await tester.tap(find.byKey(const ValueKey('about-link:license')));
    await tester.pumpAndSettle();
    expect(launchedUrls.last, kProjectLicenseUrl);

    // 打开免责声明弹层（走统一 PopupPanel，无 Divider）
    await tester.ensureVisible(
      find.byKey(const ValueKey('about-link:disclaimer')),
    );
    await tester.tap(find.byKey(const ValueKey('about-link:disclaimer')));
    await tester.pumpAndSettle();

    expect(find.byType(PopupPanel), findsOneWidget);
    expect(find.text(t.about.disclaimerItem1Title), findsOneWidget);
    expect(find.text(t.about.disclaimerImportant), findsOneWidget);
    expect(find.byType(Divider), findsNothing);

    await tester.tap(find.text(t.common.gotIt));
    await tester.pumpAndSettle();
    expect(find.byType(PopupPanel), findsNothing);
  });

  testWidgets('贡献者加载失败时展示 Expressive 空态并支持重试恢复', (tester) async {
    var attempts = 0;
    AboutPage.debugVersionLoader = () async => '0.1.0';
    AboutPage.debugContributorsLoader = () async {
      attempts++;
      if (attempts == 1) {
        throw Exception('network error');
      }
      return const [
        {
          'login': 'RossiDev',
          'contributions': 16,
          'avatar_url': '',
          'html_url': 'https://github.com/RossiDev',
        },
      ];
    };

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.text(t.about.fetchFailed), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('about-contributors-retry')));
    await tester.pumpAndSettle();

    expect(find.text('RossiDev'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
  });

  testWidgets('窄屏 2 倍字号与双栏嵌入模式下均无布局溢出', (tester) async {
    AboutPage.debugVersionLoader = () async => '0.1.0+1';
    AboutPage.debugContributorsLoader = () async => const [
      {
        'login': 'ContributorWithLongUsername',
        'contributions': 99,
        'avatar_url': '',
        'html_url': 'https://github.com/ContributorWithLongUsername',
      },
    ];

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildSubject(textScale: 2.0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(buildSubject(embedded: true));
    await tester.pumpAndSettle();
    expect(find.byType(M3EAppBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
