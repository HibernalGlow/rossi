import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/setting/real_sr/widgets/image_processing/processing_example.dart';
import 'package:zephyr/page/setting/real_sr/widgets/image_processing/processing_settings_card.dart';
import 'package:zephyr/reader/auto_trim_settings.dart';

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

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GlobalSettingCubit>();
    final enabled = context
        .watch<GlobalSettingCubit>()
        .state
        .readSetting
        .autoTrimPageMargins;
    return ValueListenableBuilder(
      valueListenable: AutoTrimSettings.options,
      builder: (context, options, _) => ProcessingSettingsCard(
        title: '自动裁边',
        icon: Icons.crop_free,
        description: '在线和本地漫画共用；阅读时放大内容区域',
        status: enabled ? '已开启 · 白边和黑边自动检测' : '已关闭 · 显示完整页面',
        children: [
          const ProcessingExample(kind: ProcessingExampleKind.autoTrim),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('默认启用自动裁边'),
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
