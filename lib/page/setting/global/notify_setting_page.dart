import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/service/notify/notify_topic.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';

/// 提示个性化：哪些**后台自己冒出来**的应用内提示允许打扰你。
///
/// 只讲「能不能弹」。外观（位置、时长、宽度、透明度、进度条）在
/// 「提示样式」那一页（`ToastSettingPage`）；系统通知栏那一路本轮不在这里管
/// （口径见 `docs/adr/0020-in-app-notification-personalization.md`），
/// 页尾那一行说明就是为这条边界写的，别让读者以为这里能全关掉。
@RoutePage()
class NotifySettingPage extends StatelessWidget {
  const NotifySettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final setting = cubit.state.notifySetting;

    return SettingPageShell(
      title: t.settings.notifyPersonalize,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          settingSectionTitle(
            context,
            t.settings.notifySectionAmbient,
            icon: AppGlyphs.bell,
          ),
          SwitchListTile(
            secondary: const GlyphIcon(AppGlyphs.bellOff),
            title: Text(t.settings.notifyMaster),
            subtitle: Text(t.settings.notifyMasterHint),
            thumbIcon: kSettingSwitchThumbIcon,
            value: setting.enabled,
            onChanged: (bool value) {
              cubit.updateNotifySetting(
                (current) => current.copyWith(enabled: value),
              );
            },
          ),
          // 层叠关系要显示出来：总闸关着时逐事项仍是用户设的那个值，但当下不起作用。
          // 不说会被读成设置自相矛盾；也不把它们禁成灰块 —— 关着总闸时先把某一项
          // 安排好是合理操作，禁掉等于逼用户两步走。
          if (!setting.enabled)
            _Note(icon: AppGlyphs.info, text: t.settings.notifyMasterOffNote),
          for (final topic in NotifyTopic.ambientTopics)
            SwitchListTile(
              secondary: GlyphIcon(_topicIcon(topic)),
              title: Text(topic.label),
              subtitle: Text(topic.hint),
              thumbIcon: kSettingSwitchThumbIcon,
              value: topic.enabledIn(setting),
              onChanged: (bool value) => _setTopic(cubit, topic, value),
            ),
          const SizedBox(height: 16),
          settingSectionTitle(
            context,
            t.settings.notifySectionOutside,
            icon: AppGlyphs.block,
          ),
          _Note(
            icon: AppGlyphs.touch,
            text: '${NotifyTopic.action.label}：${NotifyTopic.action.hint}',
          ),
          _Note(
            icon: AppGlyphs.openBook,
            text:
                '${NotifyTopic.readerSwitch.label}：${NotifyTopic.readerSwitch.hint}',
          ),
          _Note(icon: AppGlyphs.bell, text: t.settings.notifySystemChannelNote),
          const SizedBox(height: 16),
          SettingSectionCard(
            title: t.settings.notifyPersonalize,
            icon: AppGlyphs.reset,
            children: [
              TextButton.icon(
                onPressed: () {
                  cubit.updateNotifySetting((_) => const NotifySettingState());
                  showInfoToast(t.settings.toastResetDone, context: context);
                },
                icon: const GlyphIcon(AppGlyphs.reset),
                label: Text(t.settings.toastReset),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 写回逐事项覆盖。
  ///
  /// 与出厂默认一致时**删掉这一项**，不写成 `true` 留在表里：这张表只存真正的
  /// 偏离，才不会永远只增不减，也让「这一事项我没动过」在同步载荷里看得出来。
  void _setTopic(GlobalSettingCubit cubit, NotifyTopic topic, bool value) {
    cubit.updateNotifySetting((current) {
      final next = Map<String, bool>.from(current.topics);
      if (value == topic.defaultEnabled) {
        next.remove(topic.id);
      } else {
        next[topic.id] = value;
      }
      return current.copyWith(topics: next);
    });
  }

  Glyph _topicIcon(NotifyTopic topic) => switch (topic) {
    NotifyTopic.syncAutoSuccess => AppGlyphs.cloudDone,
    NotifyTopic.syncAutoFailure => AppGlyphs.wifiOff,
    NotifyTopic.downloadComplete => AppGlyphs.downloadDone,
    NotifyTopic.downloadFailed => AppGlyphs.download,
    NotifyTopic.followUpdate => AppGlyphs.playCircle,
    NotifyTopic.pluginMessage => AppGlyphs.puzzle,
    NotifyTopic.intentOpen => AppGlyphs.openExternal,
    NotifyTopic.systemPermission => AppGlyphs.shield,
    NotifyTopic.action => AppGlyphs.touch,
    NotifyTopic.readerSwitch => AppGlyphs.openBook,
  };
}

/// 一条不可操作的说明行。
///
/// 刻意不做成开关：这几类的真源不在本表里（操作反馈永不可关、切换提示有自己的
/// 设置块、系统通知归操作系统）。摆一个关不掉的「开关」比不摆更糟。
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final Glyph icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: GlyphIcon(icon, size: 20),
      title: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
      ),
    );
  }
}
