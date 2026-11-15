import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/util/doh_setting.dart';
import 'package:zephyr/widgets/toast.dart';

/// DoH（DNS over HTTPS）开关与端点管理。
///
/// 开启且有端点时，Rust 侧所有 HTTP 请求（含 ECH 引导）都会优先走 DoH，
/// 与是否开启代理无关。每个端点优先用 JSON API，失败时回退 RFC 8484。
@RoutePage()
class DohSettingPage extends StatelessWidget {
  const DohSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final setting = cubit.state.dohSetting;

    return SettingPageShell(
      title: t.settings.doh,
      child: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.shield_outlined),
            title: Text(t.settings.doh),
            subtitle: Text(t.settings.dohEnabledSubtitle),
            thumbIcon: kSettingSwitchThumbIcon,
            value: setting.enabled,
            onChanged: (value) =>
                _update(cubit, setting.copyWith(enabled: value)),
          ),
          const Divider(height: 1, thickness: 0.3),
          settingSectionTitle(
            context,
            t.settings.dohProviders,
            icon: Icons.dns_outlined,
          ),
          if (setting.providers.isEmpty)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(t.settings.dohEmpty),
            ),
          for (final provider in setting.providers)
            ListTile(
              leading: const Icon(Icons.language_outlined),
              title: Text(_hostOf(provider)),
              subtitle: Text(
                provider,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: t.common.delete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _remove(cubit, setting, provider),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(t.settings.dohAdd),
            subtitle: Text(t.settings.dohAddHint),
            onTap: () => _add(context, cubit, setting),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.settings.dohIpHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: Text(t.settings.dohReset),
            onTap: () => _update(
              cubit,
              setting.copyWith(providers: defaultDohProviders),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Text(
              t.settings.dohNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  static void _update(GlobalSettingCubit cubit, DohSettingState next) {
    cubit.updateState((current) => current.copyWith(dohSetting: next));
    // 立刻应用到 Rust HTTP 客户端，不需要重启。
    applyDohSetting(next);
    showSuccessToast(t.common.settingSaved);
  }

  static void _remove(
    GlobalSettingCubit cubit,
    DohSettingState setting,
    String provider,
  ) {
    final providers = setting.providers
        .where((item) => item != provider)
        .toList(growable: false);
    _update(cubit, setting.copyWith(providers: providers));
  }

  static Future<void> _add(
    BuildContext context,
    GlobalSettingCubit cubit,
    DohSettingState setting,
  ) async {
    var input = '';
    String? error;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(t.settings.dohAdd),
          content: TextField(
            autofocus: true,
            onChanged: (value) {
              input = value.trim();
              if (error != null) {
                setState(() => error = null);
              }
            },
            decoration: InputDecoration(
              hintText: t.settings.dohAddHint,
              errorText: error,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              child: Text(t.common.cancel),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            TextButton(
              child: Text(t.common.ok),
              onPressed: () {
                final value = input.trim();
                final uri = Uri.tryParse(value);
                if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
                  setState(() => error = t.settings.dohInvalidUrl);
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final providers = [...setting.providers];
    if (!providers.contains(result)) {
      providers.add(result);
    }
    _update(cubit, setting.copyWith(providers: providers));
  }

  static String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.host.isNotEmpty ? uri.host : url;
  }
}
