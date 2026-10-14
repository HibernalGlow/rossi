import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/image_download.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/icons/icons.dart';

/// 下载管理页顶部的并发与节流设置。
///
/// 放在这里而不是全局设置页：调这些值的人正站在「下载慢 / 被风控」的现场，
/// 让他跑去设置翻完再回来，等于每试一个取值都要多走两步。
///
/// 默认只占一行（当前取值浓缩成一颗摘要胶囊），点开才是三行控件：任务列表才是
/// 这页的主角，常驻一叠滑杆会把下载中的行挤到第二屏。
class DownloadSettingsCard extends StatefulWidget {
  const DownloadSettingsCard({super.key});

  @override
  State<DownloadSettingsCard> createState() => _DownloadSettingsCardState();
}

class _DownloadSettingsCardState extends State<DownloadSettingsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;
    final colorScheme = context.theme.colorScheme;
    final chapters = state.downloadTaskConcurrency.clamp(
      1,
      kMaxParallelChapters,
    );
    final images = state.downloadConcurrency.clamp(1, kMaxImageConcurrency);
    final delayMs = state.downloadDelayMs.clamp(0, kMaxDownloadDelayMs);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: SettingsCardGroup(
        children: [
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: GlyphIcon(
              AppGlyphs.sliders,
              size: 18,
              color: colorScheme.primary,
            ),
            title: Text(
              t.download.settingsTitle,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            // 摘要走 subtitle 而不是 trailing 胶囊：手机窄屏上标题+胶囊+箭头会顶出
            // 一行，subtitle 自带省略号，长了也只是被截断。展开后每个控件自己带取值
            // 胶囊，这行摘要就成重复信息，收起。
            subtitle: _expanded
                ? null
                : Text(
                    t.download.settingsValueSummary(
                      chapters: chapters,
                      images: images,
                      delayMs: delayMs,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = !_expanded);
            },
            trailing: AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: ExpressiveMotion.duration(
                context,
                ExpressiveMotion.spatialDuration,
              ),
              curve: ExpressiveMotion.spatialCurve,
              child: GlyphIcon(
                AppGlyphs.chevronDown,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SettingsAnimatedCollapse(
            isExpanded: _expanded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SettingsSliderCard(
                  title: t.settings.downloadTaskConcurrency,
                  value: chapters,
                  min: 1,
                  max: kMaxParallelChapters,
                  divisions: kMaxParallelChapters - 1,
                  suffix: '',
                  onChanged: (value) {
                    cubit.updateState(
                      (current) =>
                          current.copyWith(downloadTaskConcurrency: value),
                    );
                  },
                ),
                SettingsSliderCard(
                  title: t.settings.downloadConcurrency,
                  value: images,
                  min: 1,
                  max: kMaxImageConcurrency,
                  divisions: kMaxImageConcurrency - 1,
                  suffix: '',
                  onChanged: (value) {
                    cubit.updateState(
                      (current) => current.copyWith(downloadConcurrency: value),
                    );
                  },
                ),
                SettingsSliderCard(
                  title: t.settings.downloadDelay,
                  value: delayMs,
                  min: 0,
                  max: kMaxDownloadDelayMs,
                  divisions: kMaxDownloadDelayMs ~/ 100,
                  suffix: ' ms',
                  onChanged: (value) {
                    cubit.updateState(
                      (current) => current.copyWith(downloadDelayMs: value),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HelpLine(
                        text: t.download.settingsBudgetHint(
                          count: chapters * images,
                        ),
                      ),
                      _HelpLine(
                        text: t.settings.downloadTaskConcurrencySubtitle,
                      ),
                      _HelpLine(text: t.settings.downloadConcurrencySubtitle),
                      _HelpLine(text: t.settings.downloadDelaySubtitle),
                    ],
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

/// 说明行：material_ui 的 textTheme token 不带字号，这里把 12 号写死。
class _HelpLine extends StatelessWidget {
  const _HelpLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: context.theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
