import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_book_scope.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/page/setting/real_sr/widgets/super_resolution_engine_settings.dart';
import 'package:zephyr/page/setting/real_sr/widgets/upscale_conditions_card.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/type/enum.dart';

/// 「AI 超分辨率」这一节 —— 阅读设置面板与工作台控制面板卡片**共用的一份实现**。
///
/// 面板里是**两条**开关，作用域不同，别混：
/// - 「本书」：写这本书自己的覆盖（`RealSrBookScope`），关掉只影响这本书，
///   别的书仍按全局走；重开这本书仍是你上次的选择。
/// - 「全局」：与设置页「自动超分」同一条（`realsr_auto_upscale`），所有书的默认。
class SuperResolutionSection extends StatefulWidget {
  const SuperResolutionSection({super.key});

  @override
  State<SuperResolutionSection> createState() => SuperResolutionSectionState();
}

class SuperResolutionSectionState extends State<SuperResolutionSection> {
  bool _loading = true;

  /// 这本书最终是否超分（覆盖 ?? 全局）。本地书以呈现器的实时值为准。
  bool _bookEnabled = false;

  /// 全局那条总闸（所有书的默认）。
  bool _globalEnabled = false;

  RealSrResolutionThreshold _threshold = RealSrResolutionThreshold.p720;
  bool _modelReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // 另一处拨了同一条（顶栏芯片 / 全局设置 / 卡片）要跟着刷新，别两颗控件各说各话。
    RealSrBookScope.changes.addListener(_onScopeChanged);
    // 开书 / 关书会改「本书」这颗该不该亮着 —— 卡片住在面板里，
    // 书是在另一条泳道里开的，只能靠会话中枢通知。
    ReaderSessionCoordinator.instance.addListener(_onScopeChanged);
  }

  @override
  void dispose() {
    RealSrBookScope.changes.removeListener(_onScopeChanged);
    ReaderSessionCoordinator.instance.removeListener(_onScopeChanged);
    super.dispose();
  }

  void _onScopeChanged() {
    if (mounted) unawaited(_load());
  }

  /// 当前这本书的身份；没有可信会话时为 null（= 跟随全局）。
  String? get _bookKey => activeReaderBookKey();

  /// 有没有一本「拨了会生效」的书。没有就灰显，而不是藏起来 ——
  /// 藏起来用户会以为这个版本没有书级开关。
  bool get _hasBook => _bookKey != null;

  Future<void> _load() async {
    try {
      final global = await RealSrSettings.loadAutoUpscale();
      final book = await RealSrBookScope.enabledFor(_bookKey);
      final threshold = await RealSrSettings.loadResolutionThreshold();
      final modelReady = await RealSrSuperResolution.isAvailable;
      if (!mounted) return;
      setState(() {
        _globalEnabled = global;
        _bookEnabled = book;
        _threshold = threshold;
        _modelReady = modelReady;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setBookUpscale(bool value) async {
    setState(() => _bookEnabled = value);
    try {
      await RealSrBookScope.save(_bookKey, value);
      // 本地书：呈现器立刻跟随（写覆盖那条链也会通知，但带着明确的值更直接）。
      final presenter = LocalReadSession.instance.presenter;
      if (presenter != null) await presenter.setUpscaleEnabled(value);
    } catch (_) {}
  }

  Future<void> _setGlobalUpscale(bool value) async {
    setState(() => _globalEnabled = value);
    try {
      await RealSrSettings.saveAutoUpscale(value);
      // 本书没有自己的覆盖时，呈现器会经 `RealSrBookScope.changes` 当场跟随；
      // 有覆盖的书不受影响 —— 这正是「本书」与「全局」的区分。
    } catch (_) {}
  }

  Future<void> _setThreshold(RealSrResolutionThreshold value) async {
    setState(() => _threshold = value);
    try {
      await RealSrSettings.saveResolutionThreshold(value);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final presenter = LocalReadSession.instance.presenter;
    final presenterReady = presenter != null && presenter.canPresent;
    final hasEngineChoice = hasSuperResolutionEngineChoice;
    final hasBook = _hasBook;

    Widget section() {
      final cardItems = <Widget>[
        if (!_loading)
          SettingsSwitchTile(
            title: '本书：启用 AI 超分辨率',
            subtitle: !hasBook
                ? '现在没有打开的书 —— 开一本之后这一颗才能给它单独设'
                : _modelReady
                ? '只影响这本书，其它书仍按全局设置'
                : '只影响这本书；模型未下载，开启时会先问一句',
            value: presenterReady ? presenter.isUpscaleEnabled : _bookEnabled,
            disabled: !hasBook,
            onChanged: _setBookUpscale,
          ),
        if (presenterReady) ...[
          SettingsAnimatedCollapse(
            isExpanded: presenter.isUpscaleEnabled,
            child: SettingsSwitchTile(
              title: '对比原图',
              subtitle: '临时查看原图，关闭后恢复超分图',
              value: presenter.isOriginalPreview,
              onChanged: presenter.setOriginalPreview,
            ),
          ),
        ],
        if (!_loading)
          SettingsSwitchTile(
            title: t.realSr.autoUpscale,
            subtitle: _globalEnabled
                ? '所有书的默认（与设置页那条同一条）'
                : '所有书的默认，现在关着；打开后没有单独设置的书都会跟着开',
            value: _globalEnabled,
            onChanged: _setGlobalUpscale,
          ),
        if (!_loading)
          SettingsDropdownTile<RealSrResolutionThreshold>(
            title: t.realSr.resolutionThreshold,
            subtitle: t.realSr.resolutionThresholdSubtitle,
            value: RealSrSettings.effectiveThreshold(_threshold),
            values: RealSrSettings.availableThresholds,
            labelOf: (threshold) => threshold.label,
            onChanged: _setThreshold,
          ),
      ];

      if (cardItems.isEmpty && !hasEngineChoice) return const SizedBox.shrink();

      final colorScheme = Theme.of(context).colorScheme;

      return SettingsSection(
        title: 'AI 超分辨率',
        icon: Icons.auto_awesome_outlined,
        children: [
          SettingsCardGroup(children: cardItems),
          if (hasEngineChoice) ...[
            // 底色走 Material，理由与 [SettingsCardGroup] 一样：
            // 这段里嵌的 `ExpansionTile` 把水波画在**最近的 Material 祖先**上，
            // 被一层带色 DecoratedBox 挡住就永远看不见（Flutter 会直接抛断言）。
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                type: MaterialType.canvas,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: const SuperResolutionEngineSettings(
                    isReaderCompact: true,
                  ),
                ),
              ),
            ),
          ],
          const UpscaleConditionsCard(isReaderCompact: true),
        ],
      );
    }

    if (!presenterReady) return section();
    return ListenableBuilder(
      listenable: presenter,
      builder: (_, _) => section(),
    );
  }
}

/// 当前这本书的身份：本地书用读会话登记的那条路径，在线书用 `插件id:漫画id`。
///
/// **身份只从会话拿**，不写成 `activeLocalBook ?? …`。那个短路写法在
/// 「本地书 A 上再 push 一本在线书 B」时会返回 A 的路径 —— 于是这一颗
/// 读的是 B、写的却是 A 的覆盖：`activeLocalBook` 是全局静态，
/// 而 `LocalReadSession.dispose` 的清理卡在路径比对与 `isLocalComicSource` 之后，
/// 在线书那条路根本不会把它置空。
///
/// 没有登记会话时返回 null，调用方按「跟随全局」处理，而不是编一个键出来。
String? activeReaderBookKey() {
  final coordinator = ReaderSessionCoordinator.instance;
  if (!coordinator.hasActiveSession) return null;
  return RealSrBookScope.keyFor(localPath: coordinator.localSource?.path) ??
      RealSrBookScope.keyFor(
        from: coordinator.from,
        comicId: coordinator.comicId,
      );
}
