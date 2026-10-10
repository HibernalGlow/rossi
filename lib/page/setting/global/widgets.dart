import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_socks_proxy/socks_proxy.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/src/rust/api/qjs.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/icons/icons.dart';

Widget changeThemeColor(BuildContext context) {
  return ListTile(
    leading: const GlyphIcon(AppGlyphs.palette),
    title: Text(t.settings.themeColor),
    subtitle: Text(t.settings.themeColorSubtitle),
    trailing: const GlyphIcon(AppGlyphs.chevronForward),
    onTap: () {
      AutoRouter.of(context).push(const ThemeColorRoute());
    },
  );
}

Widget proxyToggle(
  BuildContext context, {
  required bool enabled,
  required ProxyType type,
  required String currentProxy,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SwitchListTile(
        secondary: const GlyphIcon(AppGlyphs.router),
        title: Text(t.settings.proxy),
        subtitle: Text(t.settings.proxyEnabledSubtitle),
        thumbIcon: kSettingSwitchThumbIcon,
        value: enabled,
        onChanged: (value) async {
          final globalSettingCubit = context.read<GlobalSettingCubit>();
          globalSettingCubit.updateState(
            (current) => current.copyWith(
              proxySetting: current.proxySetting.copyWith(enabled: value),
            ),
          );

          if (!value) {
            try {
              setSocks5Proxy(proxy: '');
            } catch (_) {}
            SocksProxy.setProxy('DIRECT');
          }

          showSuccessToast(t.common.restartToTakeEffect);
        },
      ),
      if (enabled) proxyTypeEdit(context, type),
      if (enabled) proxyAddressEdit(context, currentProxy),
    ],
  );
}

Widget proxyTypeEdit(BuildContext context, ProxyType type) {
  final items = <ProxyType, String>{
    ProxyType.http: t.settings.proxyTypeHttp,
    ProxyType.socks5: t.settings.proxyTypeSocks5,
  };
  return ListTile(
    leading: const GlyphIcon(AppGlyphs.router),
    title: Text(t.settings.proxyType),
    subtitle: Text(t.settings.proxyTypeSubtitle),
    trailing: FluentDropdown<ProxyType>(
      value: type,
      displayValue: items[type]!,
      items: items,
      onChanged: (ProxyType value) {
        if (value == type) return;
        final globalSettingCubit = context.read<GlobalSettingCubit>();
        globalSettingCubit.updateState(
          (current) => current.copyWith(
            proxySetting: current.proxySetting.copyWith(type: value),
          ),
        );
        showSuccessToast(t.common.restartToTakeEffect);
      },
    ),
  );
}

Widget proxyAddressEdit(BuildContext context, String currentProxy) {
  return ListTile(
    leading: const GlyphIcon(AppGlyphs.link),
    title: Text(t.settings.proxyAddress),
    subtitle: Text(
      currentProxy.isEmpty
          ? t.settings.proxySubtitle
          : t.settings.proxyCurrent(currentProxy: currentProxy),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const GlyphIcon(AppGlyphs.chevronForward),
    onTap: () async {
      final globalSettingCubit = context.read<GlobalSettingCubit>();
      var inputValue = currentProxy;

      final result = await showPopupPanel<String>(
        presentation: PopupPresentation.relative,
        context: context,
        builder: (context) => PopupPanel(
          title: Text(t.settings.proxyAddress),
          content: TextFormField(
            initialValue: currentProxy,
            autofocus: true,
            onChanged: (value) => inputValue = value.trim(),
            decoration: InputDecoration(
              hintText: t.settings.proxyHint,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              child: Text(t.common.cancel),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: Text(t.common.ok),
              onPressed: () => Navigator.pop(context, inputValue),
            ),
          ],
        ),
      );

      if (result != null && result != currentProxy) {
        globalSettingCubit.updateState(
          (current) => current.copyWith(
            proxySetting: current.proxySetting.copyWith(address: result),
          ),
        );
        showSuccessToast(t.common.restartToTakeEffect);
      }
    },
  );
}

Widget webdavSync(BuildContext context, SyncServiceType syncServiceType) {
  final title = switch (syncServiceType) {
    SyncServiceType.none => t.settings.syncConfig,
    _ => t.webdavSync.serviceTitle(
      service: switch (syncServiceType) {
        SyncServiceType.webdav => t.settings.syncServiceWebdav,
        SyncServiceType.s3 => t.settings.syncServiceS3,
        SyncServiceType.none => '',
      },
    ),
  };

  return ListTile(
    leading: const GlyphIcon(AppGlyphs.cloud),
    title: Text(title),
    subtitle: Text(t.settings.syncConfigSubtitle),
    trailing: const GlyphIcon(AppGlyphs.chevronForward),
    onTap: () {
      AutoRouter.of(context).push(const WebDavSyncRoute());
    },
  );
}

Widget editMaskedKeywords(BuildContext context) {
  return ListTile(
    leading: const GlyphIcon(AppGlyphs.shield),
    title: Text(t.settings.maskedKeywords),
    subtitle: Text(t.settings.maskedKeywordsSubtitle),
    trailing: const GlyphIcon(AppGlyphs.chevronForward),
    onTap: () {
      showPopupPanel(
        context: context,
        // 设置里的一条表单：宽屏上从这一行设置项飞出来。
        presentation: PopupPresentation.relative,
        builder: (context) => const _KeywordManagementDialog(),
      );
    },
  );
}

class _KeywordManagementDialog extends StatefulWidget {
  const _KeywordManagementDialog();

  @override
  State<_KeywordManagementDialog> createState() =>
      _KeywordManagementDialogState();
}

class _KeywordManagementDialogState extends State<_KeywordManagementDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 只需要在这里获取 Cubit
    final globalSettingCubit = context.read<GlobalSettingCubit>();

    return BlocBuilder<GlobalSettingCubit, GlobalSettingState>(
      builder: (context, state) {
        return PopupPanel(
          title: Text(t.settings.maskedKeywords),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.settings.maskedKeywordsSubtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(
                  minHeight: 120,
                  maxHeight: 240,
                ),
                width: double.infinity,
                child: SingleChildScrollView(
                  child: state.maskedKeywords.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Text(
                              t.settings.maskedKeywordsEmpty,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(
                            state.maskedKeywords.length,
                            (index) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                constraints: const BoxConstraints(
                                  maxWidth: 280,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        state.maskedKeywords[index],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: GestureDetector(
                                        onTap: () {
                                          final newList = List<String>.from(
                                            state.maskedKeywords,
                                          );
                                          newList.removeAt(index);
                                          globalSettingCubit.updateState(
                                            (current) => current.copyWith(
                                              maskedKeywords: newList,
                                            ),
                                          );
                                        },
                                        child: GlyphIcon(
                                          AppGlyphs.close,
                                          size: 14,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer
                                              .withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: t.settings.maskedKeywordsInputHint,
                        hintStyle: const TextStyle(fontSize: 14),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) =>
                          _addKeyword(globalSettingCubit, state),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () => _addKeyword(globalSettingCubit, state),
                    icon: const GlyphIcon(AppGlyphs.add, size: 20),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t.common.done),
            ),
          ],
        );
      },
    );
  }

  void _addKeyword(GlobalSettingCubit cubit, GlobalSettingState state) {
    final text = _controller.text.trim();
    if (text.isNotEmpty && !state.maskedKeywords.contains(text)) {
      final newList = [...state.maskedKeywords, text];
      cubit.updateState((current) => current.copyWith(maskedKeywords: newList));
      _controller.clear();
    }
  }
}
