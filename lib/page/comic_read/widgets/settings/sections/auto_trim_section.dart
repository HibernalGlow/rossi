import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/page/setting/real_sr/widgets/image_processing/processing_example.dart';
import 'package:zephyr/page/setting/real_sr/widgets/image_processing/processing_settings_card.dart';
import 'package:zephyr/reader/auto_trim_settings.dart';
import 'package:zephyr/widgets/expressive/expressive_shape.dart';
import 'package:zephyr/workspace/widgets/cards/expressive_widgets.dart';
import 'package:zephyr/i18n/strings.g.dart';

class AutoTrimSection extends StatefulWidget {
  const AutoTrimSection({super.key});
  @override
  State<AutoTrimSection> createState() => _AutoTrimSectionState();
}

class _AutoTrimSectionState extends State<AutoTrimSection> {
  @override
  void initState() {
    super.initState();
    unawaited(AutoTrimSettings.load());
  }

  /// 阅读器路由下才有本漫覆盖的 cubit；工作区卡片等处没有，就只看全局。
  ComicReadPreferenceCubit? _preferenceCubit(BuildContext context) {
    try {
      return context.read<ComicReadPreferenceCubit>();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final preference = _preferenceCubit(context);

    if (preference == null) return _buildCard(context, null);
    return BlocBuilder<ComicReadPreferenceCubit, ComicReadPreferenceState>(
      bloc: preference,
      builder: (context, state) => _buildCard(context, state.override),
    );
  }

  Widget _buildCard(
    BuildContext context,
    ({ReadSettingState setting, Set<String> keys})? override,
  ) {
    final cubit = context.read<GlobalSettingCubit>();
    final global = context
        .watch<GlobalSettingCubit>()
        .state
        .readSetting
        .autoTrimPageMargins;
    // 阅读器渲染用的是「全局 + 本漫覆盖」的生效值；开关本身仍然只改全局。
    final effective = ComicReadPreferenceService.resolveEffective(
      context.watch<GlobalSettingCubit>().state.readSetting,
      override,
    ).autoTrimPageMargins;
    final enabled = global;

    final status = effective == global
        ? (enabled ? t.reader.trimOnAutoDetect : t.reader.trimOffFullPage)
        : (effective
              ? t.reader.bookTrimOnOverride
              : t.reader.bookTrimOffOverride);
    return ValueListenableBuilder(
      valueListenable: AutoTrimSettings.options,
      builder: (context, options, _) => ProcessingSettingsCard(
        title: '自动裁边',
        icon: Icons.crop_free,
        description: t.reader.sharedUpscaleEnlarge,
        status: status,
        children: [
          ProcessingExample(
            kind: ProcessingExampleKind.autoTrim,
            enabled: effective,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: ExpressiveShapeBadge(
              icon: AppGlyphs.cropFree,
              shape: ExpressiveButtonShape.clover8Leaf,
              size: 36,
              glyphSize: 18,
              tone: ExpressiveTone.primary,
              active: enabled,
            ),
            title: Text(
              t.reader.autoTrimEnabledByDefault,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(t.reader.denoiseOriginalSafeBookOverride),
            value: enabled,
            onChanged: (value) {
              HapticFeedback.lightImpact();
              cubit.updateReadSetting(
                (current) => current.copyWith(autoTrimPageMargins: value),
              );
            },
          ),
          ProcessingAdvancedDisclosure(
            title: t.reader.trimAdvancedSettings,
            child: Column(
              children: [
                ProcessingSlider(
                  title: t.reader.backgroundTolerance,
                  description: t.reader.bgToleranceHint,
                  value: options.tolerance,
                  min: 0,
                  max: 64,
                  labelOf: (v) => '$v',
                  onChanged: (v) => unawaited(
                    AutoTrimSettings.save(options.copyWith(tolerance: v)),
                  ),
                ),
                ProcessingSlider(
                  title: t.reader.trimSideLimit,
                  description: t.reader.trimSideLimitHint,
                  value: options.maxCropPercent,
                  min: 0,
                  max: 20,
                  labelOf: (v) => '$v%',
                  onChanged: (v) => unawaited(
                    AutoTrimSettings.save(options.copyWith(maxCropPercent: v)),
                  ),
                ),
                ProcessingSlider(
                  title: t.reader.safeMargin,
                  description: t.reader.trimSafeMarginKeeps,
                  value: options.safetyMarginPermille,
                  min: 6,
                  max: 40,
                  labelOf: (v) => '${(v / 10).toStringAsFixed(1)}%',
                  onChanged: (v) => unawaited(
                    AutoTrimSettings.save(
                      options.copyWith(safetyMarginPermille: v),
                    ),
                  ),
                ),
                Text(t.reader.webtoonTrimSidesOnly),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    style: processingActionStyle(),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      unawaited(AutoTrimSettings.save(const AutoTrimOptions()));
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: Text(t.reader.restoreConservativeDefaults),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
