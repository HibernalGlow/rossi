import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/cubit/discover_cubit.dart';
import 'package:zephyr/page/discover/widgets/plugin_card.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/widgets/plugin_icon.dart';

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('GeneratedPluginIcon 在深浅主题与各种种子下均满足 MD3E 对比度 (>= 4.5:1)', () {
    const seeds = [
      'wnacg',
      'e-hentai',
      'j-hentai',
      'wnacg-zip',
      'jm',
      'bika',
      'copymanga',
      'hitomi',
    ];
    for (final seedColor in const [Color(0xFF8B4148), Color(0xFF2E6B4E)]) {
      for (final brightness in Brightness.values) {
        final scheme = ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: brightness,
        );
        for (final seed in seeds) {
          final pair = GeneratedPluginIcon.tonalPairOfSeed(scheme, seed);
          final ratio = _contrastRatio(pair.background, pair.foreground);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: 'seed=$seed brightness=$brightness 的生成图标对比度不足: $ratio',
          );
        }
      }
    }
  });

  testWidgets('PluginCard 采用超椭圆图标座、M3ESwitch 与超椭圆/胶囊功能标签', (tester) async {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF8B4148),
      brightness: Brightness.dark,
    );
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(useMaterial3: true, colorScheme: scheme),
        home: Scaffold(
          body: PluginCard(
            pluginUuid: 'e-hentai',
            pluginState: PluginRuntimeState(
              uuid: 'e-hentai',
              version: '1.0.0',
              originScript: '',
              isEnabled: true,
              isDeleted: false,
              debug: false,
              debugUrl: null,
              lastLoadSuccess: true,
              lastLoadError: null,
              sortOrder: null,
              insertedAt: DateTime(2026, 10, 13),
              updatedAt: DateTime(2026, 10, 13),
              deletedAt: null,
            ),
            infoState: const DiscoverPluginInfoState(
              loading: false,
              data: {
                'name': 'e-hentai',
                'functions': [
                  {
                    'id': 'latest',
                    'title': '最新',
                    'action': {'type': 'openComicList'},
                  },
                  {
                    'id': 'favorite',
                    'title': '收藏',
                    'action': {'type': 'openCloudFavorite'},
                  },
                ],
              },
            ),
            isToggling: false,
            onSearch: () {},
            onSettings: (_) {},
            onToggleEnabled: (_) {},
            onRetry: () {},
            onAction: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('e-hentai'), findsOneWidget);
    expect(find.byType(ClipRSuperellipse), findsOneWidget);
    expect(find.byType(M3ESwitch), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(2));

    final chips = tester
        .widgetList<ActionChip>(find.byType(ActionChip))
        .toList();
    expect(chips[0].backgroundColor, scheme.secondaryContainer);
    expect(chips[1].backgroundColor, scheme.primaryContainer);
    expect(chips[0].shape, isA<RoundedSuperellipseBorder>());
    expect(tester.takeException(), isNull);
  });
}
