import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/registry/workspace_card_registry.dart';
import 'package:zephyr/workspace/registry/workspace_panel_registry.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/page/discover/view/discover_page.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/widgets/collapsible_card.dart';
import 'package:zephyr/workspace/widgets/panels/lane_panel_host.dart';

import '../test_helper.dart';

/// 发现页独占面板，暂时隐藏插件小组件及其入口。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Finder card(String id) =>
      find.byWidgetPredicate((w) => w is CollapsibleCard && w.cardId == id);

  group('发现面板注册表契约', () {
    test('发现面板保持整页模式', () {
      final panel = WorkspacePanelRegistry.I.find(WorkspacePanelId.discover)!;
      expect(panel.acceptsCards, isFalse);
      expect(panel.exclusive, isTrue);
      expect(panel.page, isNotNull);
      expect(panel.canMove, isFalse);
      expect(panel.canHide, isFalse);
    });

    test('只有两张插件卡默认住在发现面板', () {
      for (final id in [
        WorkspaceCardRegistry.pluginStatus,
        WorkspaceCardRegistry.pluginShortcuts,
      ]) {
        final definition = WorkspaceCardRegistry.I.find(id);
        expect(definition, isNotNull, reason: id);
        expect(
          definition!.defaultPanelId,
          WorkspacePanelId.discover,
          reason: id,
        );
        expect(definition.defaultVisible, isFalse, reason: id);
      }
    });

    test('插件组件可收起，发现页始终保留', () {
      expect(
        WorkspaceCardRegistry.I
            .find(WorkspaceCardRegistry.pluginStatus)!
            .canHide,
        isTrue,
      );
      expect(
        WorkspaceCardRegistry.I
            .find(WorkspaceCardRegistry.pluginShortcuts)!
            .canHide,
        isTrue,
      );
    });

    test('信息与控制面板的卡片仍然全部在册', () {
      final cards = WorkspaceCardRegistry.I;
      for (final id in [
        WorkspaceCardRegistry.bookInformation,
        WorkspaceCardRegistry.imageInformation,
        WorkspaceCardRegistry.storageInformation,
        WorkspaceCardRegistry.timeInformation,
        WorkspaceCardRegistry.preloadStatus,
      ]) {
        expect(cards.find(id), isNotNull, reason: id);
        expect(
          cards.find(id)!.defaultPanelId,
          WorkspacePanelId.info,
          reason: id,
        );
      }
      for (final id in [
        WorkspaceCardRegistry.switchToast,
        WorkspaceCardRegistry.superResolution,
        WorkspaceCardRegistry.translate,
        WorkspaceCardRegistry.imageTuning,
      ]) {
        expect(
          cards.find(id)!.defaultPanelId,
          WorkspacePanelId.control,
          reason: id,
        );
      }
    });
  });

  group('发现面板渲染', () {
    setUp(TestObjectBoxHelper.setUpTestObjectBox);
    tearDown(TestObjectBoxHelper.tearDownTestObjectBox);

    Future<void> pump(
      WidgetTester tester,
      double width, {
      bool savedWidgetsVisible = false,
    }) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cubit = WorkspaceCubit();
      addTearDown(cubit.close);
      cubit.setActivePanel('right', WorkspacePanelId.discover);
      if (savedWidgetsVisible) {
        cubit.setCardVisible(WorkspaceCardRegistry.pluginStatus, true);
        cubit.setCardVisible(WorkspaceCardRegistry.pluginShortcuts, true);
      }
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocaleUtils.supportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: cubit),
              BlocProvider(create: (_) => GlobalSettingCubit()),
              BlocProvider(create: (_) => PluginRegistryCubit()),
            ],
            child: const Scaffold(
              body: SafeArea(
                child: LanePanelHost(side: WorkspacePanelSide.right),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('发现页占满面板，不显示组件或抽出入口', (tester) async {
      await pump(tester, 640);

      expect(
        find.byKey(const ValueKey('discover-widget-pull-handle')),
        findsNothing,
      );
      expect(find.byType(DiscoverPage), findsOneWidget);
      expect(card('plugin_status'), findsNothing);
      expect(card('plugin_shortcuts'), findsNothing);
      expect(find.byType(PanelHeaderBar), findsNothing);
      expect(
        tester.getSize(find.byType(DiscoverPage)),
        tester.getSize(find.byType(LanePanelHost)),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('旧布局即使保存了显示组件，窄面板也仍只显示完整发现页', (tester) async {
      await pump(tester, 320, savedWidgetsVisible: true);
      expect(find.byType(DiscoverPage), findsOneWidget);
      expect(card('plugin_status'), findsNothing);
      expect(card('plugin_shortcuts'), findsNothing);
      expect(
        find.byKey(const ValueKey('discover-widget-pull-handle')),
        findsNothing,
      );
      expect(
        tester.getSize(find.byType(DiscoverPage)),
        tester.getSize(find.byType(LanePanelHost)),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
