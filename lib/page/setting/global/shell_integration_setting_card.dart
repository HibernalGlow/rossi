import 'package:zephyr/page/setting/common/setting_group.dart';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/platform/desktop/windows_shell_context_menu.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';

/// 「系统集成」卡片：从文件管理器的右键菜单直接打开本地漫画。
///
/// # 为什么这颗开关不存进 GlobalSetting
/// 它的值不是用户的意愿，而是**这台机器上注册表现在有没有那些键**。用户在 regedit
/// 里删掉、或者装到别处让命令值失效，界面若还按持久化的值显示"开"，就是在撒谎，
/// 而且撒的是一个他自己按不动的谎。所以这里每次进页面现查（见 `readStatus`）。
///
/// # 为什么 macOS 那一边只有一个说明
/// 访达的「打开方式 → Rossi」来自应用包自己声明的文档类型（`Info.plist`），
/// 系统读取它的时机是登记的瞬间，不由应用在运行时开关。没有可关的东西，
/// 摆一颗关不动的开关比不摆更糟。
class ShellIntegrationSettingCard extends StatefulWidget {
  const ShellIntegrationSettingCard({super.key});

  @override
  State<ShellIntegrationSettingCard> createState() =>
      _ShellIntegrationSettingCardState();
}

class _ShellIntegrationSettingCardState
    extends State<ShellIntegrationSettingCard> {
  WindowsShellIntegrationStatus? _status;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) _refresh();
  }

  void _refresh() {
    _status = WindowsShellContextMenu.readStatus();
  }

  void _toggle(bool value) {
    try {
      if (value) {
        WindowsShellContextMenu.register();
      } else {
        WindowsShellContextMenu.unregister();
      }
      if (value) {
        showSuccessToast(
          t.settings.shellIntegrationRegistered,
          context: context,
        );
      } else {
        showInfoToast(
          t.settings.shellIntegrationUnregistered,
          context: context,
        );
      }
    } on WindowsShellIntegrationException catch (e) {
      showErrorToast(e.toString(), context: context);
    }
    // 成败都重读：半途失败会留下「一部分键已经写上」的状态，
    // 那既不是开也不是关，只有注册表知道自己现在是什么。
    setState(_refresh);
  }

  /// 只重写命令值（不先删）：菜单项不会在用户眼前闪一下消失又回来。
  void _repair() {
    try {
      WindowsShellContextMenu.register();
      showSuccessToast(t.settings.shellIntegrationRegistered, context: context);
    } on WindowsShellIntegrationException catch (e) {
      showErrorToast(e.toString(), context: context);
    }
    setState(_refresh);
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) return _buildWindows(context);
    if (Platform.isMacOS) return _buildMacOS();
    return const SizedBox.shrink();
  }

  Widget _buildWindows(BuildContext context) {
    final status =
        _status ?? const WindowsShellIntegrationStatus(registered: false);
    final stale = status.registered && !status.pointsToCurrentExecutable;

    return SettingSectionCard(
      title: t.settings.shellIntegration,
      icon: AppGlyphs.devices,
      children: [
        SettingGroup.switchTile(
          leading: const GlyphIcon(AppGlyphs.mouse),
          title: Text(t.settings.shellIntegrationContextMenu),
          subtitle: Text(t.settings.shellIntegrationContextMenuSubtitle),
          value: status.isOn,
          onChanged: _toggle,
        ),
        if (stale)
          ListTile(
            leading: GlyphIcon(
              AppGlyphs.lock,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(t.settings.shellIntegrationStalePath),
            subtitle: Text(
              status.commandLine ?? status.executablePath ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: FilledButton.tonal(
              onPressed: _repair,
              child: Text(t.settings.shellIntegrationRepair),
            ),
          ),
      ],
    );
  }

  Widget _buildMacOS() {
    return SettingSectionCard(
      title: t.settings.shellIntegration,
      icon: AppGlyphs.devices,
      children: [
        ListTile(
          leading: const GlyphIcon(AppGlyphs.mouse),
          title: Text(t.settings.shellIntegrationContextMenu),
          subtitle: Text(t.settings.shellIntegrationMacHint),
        ),
      ],
    );
  }
}
