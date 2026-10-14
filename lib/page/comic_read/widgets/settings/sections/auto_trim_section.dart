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
        ? (enabled ? '已开启 · 白边和黑边自动检测' : '已关闭 · 显示完整页面')
        : (effective ? '本书已单独开启裁边 · 全局为关闭' : '本书已单独关闭裁边 · 全局为开启，当前阅读不会裁边');
    return ValueListenableBuilder(
      valueListenable: AutoTrimSettings.options,
      builder: (context, options, _) => ProcessingSettingsCard(
        title: '自动裁边',
        icon: Icons.crop_free,
        description: '在线和本地漫画共用；阅读时放大内容区域',
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
            title: const Text(
              '默认启用自动裁边',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('不修改原图；单本开关仍可在阅读设置覆盖'),
            value: enabled,
            onChanged: (value) {
              HapticFeedback.lightImpact();
              cubit.updateReadSetting(
                (current) => current.copyWith(autoTrimPageMargins: value),
              );
            },
          ),
          ProcessingAdvancedDisclosure(
            title: '裁边高级设置',
            child: Column(
              children: [
                ProcessingSlider(
                  title: '背景检测容差',
                  description: '增大可容忍纸张底色和轻微噪点；浅色细节较多时使用较小值',
                  value: options.tolerance,
                  min: 0,
                  max: 64,
                  labelOf: (v) => '$v',
                  onChanged: (v) => unawaited(
                    AutoTrimSettings.save(options.copyWith(tolerance: v)),
                  ),
                ),
                ProcessingSlider(
                  title: '单边裁切上限',
                  description: '限制每一侧最多裁掉的比例；0% 等同于保留完整页面',
                  value: options.maxCropPercent,
                  min: 0,
                  max: 20,
                  labelOf: (v) => '$v%',
                  onChanged: (v) => unawaited(
                    AutoTrimSettings.save(options.copyWith(maxCropPercent: v)),
                  ),
                ),
                ProcessingSlider(
                  title: '安全留边',
                  description: '在检测内容周围额外保留空间，保护文字、页码和线条',
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
                const Text('条漫只裁左右，保留上下接缝。满版或检测不可靠的页面保留原样。'),
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
                    label: const Text('恢复保守默认值'),
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
