import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:markdown_widget/widget/markdown_block.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/webdav_sync/webdav_sync.dart';

import 'package:zephyr/main.dart';
import 'package:zephyr/page/setting/common/setting_group.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/widgets/dialog.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/util/event/event.dart';

@RoutePage()
class WebDavSyncPage extends StatefulWidget {
  const WebDavSyncPage({super.key});

  @override
  State<WebDavSyncPage> createState() => _WebDavSyncPageState();
}

class _WebDavSyncPageState extends State<WebDavSyncPage> {
  final TextEditingController _webdavHost = TextEditingController();
  final TextEditingController _webdavUsername = TextEditingController();
  final TextEditingController _webdavPassword = TextEditingController();
  final TextEditingController _s3Endpoint = TextEditingController();
  final TextEditingController _s3AccessKey = TextEditingController();
  final TextEditingController _s3SecretKey = TextEditingController();
  final TextEditingController _s3Bucket = TextEditingController();
  final TextEditingController _s3Region = TextEditingController();
  final TextEditingController _s3Port = TextEditingController();
  bool _s3UseSSL = true;
  bool _s3PathStyle = false;

  @override
  void initState() {
    super.initState();
    final settings = objectbox.userSettingBox.get(1)!.globalSetting;
    _webdavHost.text = settings.syncSetting.webdavSetting.host;
    _webdavUsername.text = settings.syncSetting.webdavSetting.username;
    _webdavPassword.text = settings.syncSetting.webdavSetting.password;
    _s3Endpoint.text = settings.syncSetting.s3Setting.endpoint;
    _s3AccessKey.text = settings.syncSetting.s3Setting.accessKey;
    _s3SecretKey.text = settings.syncSetting.s3Setting.secretKey;
    _s3Bucket.text = settings.syncSetting.s3Setting.bucket;
    _s3Region.text = settings.syncSetting.s3Setting.region;
    _s3Port.text = settings.syncSetting.s3Setting.port > 0
        ? settings.syncSetting.s3Setting.port.toString()
        : '';
    _s3UseSSL = settings.syncSetting.s3Setting.useSSL;
    _s3PathStyle = settings.syncSetting.s3Setting.pathStyle;
  }

  @override
  void dispose() {
    _webdavHost.dispose();
    _webdavUsername.dispose();
    _webdavPassword.dispose();
    _s3Endpoint.dispose();
    _s3AccessKey.dispose();
    _s3SecretKey.dispose();
    _s3Bucket.dispose();
    _s3Region.dispose();
    _s3Port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final globalSettingCubit = context.watch<GlobalSettingCubit>();
    final syncServiceType =
        globalSettingCubit.state.syncSetting.syncServiceType;
    final title = syncServiceType == SyncServiceType.none
        ? t.webdavSync.title
        : t.webdavSync.serviceTitle(service: syncServiceType.label);

    return SettingPageShell(
      title: title,
      child: ListView(
        padding: kSettingPagePadding,
        children: <Widget>[
          if (syncServiceType == SyncServiceType.none) ...[
            _buildNoneTip(),
          ] else ...[
            SettingSectionCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: syncServiceType == SyncServiceType.webdav
                      ? _buildWebDavForm()
                      : _buildS3Form(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: settingDangerButtonStyle(context),
                    onPressed: () => _clearConfig(syncServiceType),
                    child: Text(t.webdavSync.deleteConfig),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _testAndSave(syncServiceType),
                    child: Text(t.webdavSync.testAndSave),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: () => _showQA(context),
              child: Text(t.webdavSync.faq),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildNoneTip() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Text(t.webdavSync.noneTip, style: const TextStyle(fontSize: 16)),
    );
  }

  Widget _buildWebDavForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _webdavHost,
          decoration: InputDecoration(
            labelText: t.webdavSync.webdavHost,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _webdavUsername,
          decoration: InputDecoration(
            labelText: t.webdavSync.username,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _webdavPassword,
          decoration: InputDecoration(
            labelText: t.webdavSync.password,
            border: const OutlineInputBorder(),
          ),
          obscureText: true,
        ),
      ],
    );
  }

  Widget _buildS3Form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _s3Endpoint,
          decoration: InputDecoration(
            labelText: t.webdavSync.s3Endpoint,
            hintText: t.webdavSync.s3EndpointHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _s3AccessKey,
          decoration: const InputDecoration(
            labelText: 'Access Key',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _s3SecretKey,
          decoration: const InputDecoration(
            labelText: 'Secret Key',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _s3Bucket,
          decoration: InputDecoration(
            labelText: t.webdavSync.s3Bucket,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _s3Region,
          decoration: InputDecoration(
            labelText: t.webdavSync.s3Region,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _s3Port,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: t.webdavSync.s3Port,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 4),
        SettingGroup.switchTile(
          title: Text(t.webdavSync.useSsl),
          value: _s3UseSSL,
          onChanged: (value) {
            setState(() {
              _s3UseSSL = value;
            });
          },
        ),
        SettingGroup.switchTile(
          title: Text(t.webdavSync.pathStyle),
          subtitle: Text(t.webdavSync.pathStyleSubtitle),
          value: _s3PathStyle,
          onChanged: (value) {
            setState(() {
              _s3PathStyle = value;
            });
          },
        ),
      ],
    );
  }

  void _testAndSave(SyncServiceType syncServiceType) async {
    if (syncServiceType == SyncServiceType.webdav) {
      await _testWebDavServer();
      return;
    }

    if (syncServiceType == SyncServiceType.s3) {
      await _testS3Server();
    }
  }

  void _clearConfig(SyncServiceType syncServiceType) {
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    globalSettingCubit.resetState((current, defaults) {
      if (syncServiceType == SyncServiceType.webdav) {
        return current.copyWith(
          syncSetting: current.syncSetting.copyWith(
            webdavSetting: defaults.syncSetting.webdavSetting,
            syncSettings: false,
          ),
        );
      }

      if (syncServiceType == SyncServiceType.s3) {
        return current.copyWith(
          syncSetting: current.syncSetting.copyWith(
            s3Setting: defaults.syncSetting.s3Setting,
            syncSettings: false,
          ),
        );
      }

      return current;
    });

    if (syncServiceType == SyncServiceType.webdav) {
      _webdavHost.clear();
      _webdavUsername.clear();
      _webdavPassword.clear();
    } else if (syncServiceType == SyncServiceType.s3) {
      _s3Endpoint.clear();
      _s3AccessKey.clear();
      _s3SecretKey.clear();
      _s3Bucket.clear();
      _s3Region.clear();
      _s3Port.clear();
      setState(() {
        _s3UseSSL = true;
      });
    }
  }

  Future<void> _testWebDavServer() async {
    showPopupPanel(
      context: context,
      // 原来 barrierDismissible: false（连接结果返回前不可关闭），新入口不支持该参数，点遮罩即可关闭
      builder: (BuildContext context) {
        return PopupPanel(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(t.webdavSync.connectingWebdav),
            ],
          ),
        );
      },
    );

    try {
      await testWebDavServer(
        _webdavHost.text.trim(),
        _webdavUsername.text.trim(),
        _webdavPassword.text,
      );

      if (mounted) {
        context.pop();
      }

      logger.d('WebDAV连接成功');

      if (!mounted) return;

      final globalSettingCubit = context.read<GlobalSettingCubit>();

      globalSettingCubit.updateWebDavSetting(
        (current) => current.copyWith(
          host: _webdavHost.text.trim(),
          username: _webdavUsername.text.trim(),
          password: _webdavPassword.text,
        ),
      );

      eventBus.fire(const NoticeSync(force: true));

      if (!mounted) return;
      commonDialog(context, t.webdavSync.success, t.webdavSync.webdavConnected);
    } catch (e) {
      logger.e(e);
      if (mounted) {
        context.pop();
      }

      if (!mounted) return;
      commonDialog(
        context,
        t.webdavSync.error,
        t.webdavSync.webdavConnectFailed(error: e.toString()),
      );
    }
  }

  Future<void> _testS3Server() async {
    final portText = _s3Port.text.trim();
    final port = portText.isEmpty ? 0 : int.tryParse(portText);
    if (port == null || port < 0 || port > 65535) {
      commonDialog(context, t.webdavSync.error, t.webdavSync.invalidPort);
      return;
    }

    showPopupPanel(
      context: context,
      // 原来 barrierDismissible: false（连接结果返回前不可关闭），新入口不支持该参数，点遮罩即可关闭
      builder: (BuildContext context) {
        return PopupPanel(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(t.webdavSync.connectingS3),
            ],
          ),
        );
      },
    );

    try {
      await testS3Server(
        endpoint: _s3Endpoint.text.trim(),
        accessKey: _s3AccessKey.text.trim(),
        secretKey: _s3SecretKey.text,
        bucket: _s3Bucket.text.trim(),
        useSSL: _s3UseSSL,
        port: port,
        pathStyle: _s3PathStyle,
        region: _s3Region.text.trim(),
      );

      if (mounted) {
        context.pop();
      }

      if (!mounted) return;

      final globalSettingCubit = context.read<GlobalSettingCubit>();
      globalSettingCubit.updateSyncSetting(
        (current) => current.copyWith(
          s3Setting: current.s3Setting.copyWith(
            endpoint: _s3Endpoint.text.trim(),
            accessKey: _s3AccessKey.text.trim(),
            secretKey: _s3SecretKey.text,
            bucket: _s3Bucket.text.trim(),
            region: _s3Region.text.trim(),
            useSSL: _s3UseSSL,
            port: port,
            pathStyle: _s3PathStyle,
          ),
        ),
      );

      eventBus.fire(const NoticeSync(force: true));

      if (!mounted) return;
      commonDialog(context, t.webdavSync.success, t.webdavSync.s3Connected);
    } catch (e) {
      logger.e(e);
      if (mounted) {
        context.pop();
      }

      if (!mounted) return;
      commonDialog(
        context,
        t.webdavSync.error,
        t.webdavSync.s3ConnectFailed(error: e.toString()),
      );
    }
  }

  void _showQA(BuildContext context) {
    final String disclaimerMarkdown = t.webdavSync.faqMarkdown;

    showPopupPanel(
      context: context,
      builder: (context) {
        return PopupPanel(
          content: SingleChildScrollView(
            child: MarkdownBlock(data: disclaimerMarkdown),
          ),
          actions: [
            TextButton(
              onPressed: () {
                context.pop();
              },
              child: Text(t.webdavSync.close),
            ),
          ],
        );
      },
    );
  }
}
