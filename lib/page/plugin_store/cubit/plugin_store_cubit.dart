import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/plugin_store/models/cloud_plugin_item.dart';
import 'package:zephyr/plugin/source_visibility_policy.dart';
import 'package:zephyr/plugin/plugin_install_service.dart';
import 'package:zephyr/plugin/utils/plugin_cloud_download_utils.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/toast.dart';

class PluginStoreState {
  const PluginStoreState({
    this.installing = false,
    this.installMessage = '',
    this.cloudLoading = false,
    this.cloudError = '',
    this.cloudPlugins = const <CloudPluginItem>[],
  });

  final bool installing;
  final String installMessage;
  final bool cloudLoading;
  final String cloudError;
  final List<CloudPluginItem> cloudPlugins;

  PluginStoreState copyWith({
    bool? installing,
    String? installMessage,
    bool? cloudLoading,
    String? cloudError,
    List<CloudPluginItem>? cloudPlugins,
  }) {
    return PluginStoreState(
      installing: installing ?? this.installing,
      installMessage: installMessage ?? this.installMessage,
      cloudLoading: cloudLoading ?? this.cloudLoading,
      cloudError: cloudError ?? this.cloudError,
      cloudPlugins: cloudPlugins ?? this.cloudPlugins,
    );
  }
}

class PluginStoreCubit extends Cubit<PluginStoreState> {
  PluginStoreCubit() : super(const PluginStoreState());

  Future<void> loadCloudPlugins() async {
    emit(state.copyWith(cloudLoading: true, cloudError: ''));

    try {
      final payload = await fetchCloudPluginListWithCdnFallback();
      final decoded = jsonDecode(payload);
      final entries = asJsonList(decoded)
          .map((item) => CloudPluginItem.fromJson(asJsonMap(item)))
          .where((item) => item.manifest.uuid.trim().isNotEmpty)
          .toList();

      emit(
        state.copyWith(
          cloudPlugins: entries,
          cloudLoading: false,
          cloudError: '',
        ),
      );
    } catch (e, stackTrace) {
      logger.w('拉取云端插件列表失败', error: e, stackTrace: stackTrace);
      emit(
        state.copyWith(
          cloudLoading: false,
          cloudError: t.plugin.cloudPluginsLoadFailed(error: e),
        ),
      );
    }
  }

  Future<void> installFromCloud(CloudPluginItem item) async {
    if (state.installing) {
      return;
    }
    // 列表那层已经在关掉开关时过滤掉了受限来源，这里再挡一次：入口不止一个
    // （搜索结果、深链），判定收在 policy 里，两边口径天然一致。
    if (!_showRestrictedSources &&
        SourceVisibilityPolicy.isRestricted(
          uuid: item.manifest.uuid,
          name: item.manifest.name,
          describe: item.manifest.describe,
          repo: item.repo,
          declaredRestricted: item.manifest.declaredRestricted,
        )) {
      showErrorToast(t.plugin.restrictedSourceBlocked);
      return;
    }
    final name = item.manifest.name.trim().isEmpty
        ? item.repo
        : item.manifest.name.trim();
    _beginInstall(t.plugin.installingFromCloud(name: name));

    try {
      final message = await PluginInstallService.I.installFromCloud(item);
      _reportInstallSuccess(message);
    } catch (e) {
      _reportInstallFailure(
        t.plugin.cloudDownloadFailed(
          error: normalizePluginInstallErrorMessage(e),
        ),
      );
    }
  }

  Future<void> installFromLocalBytes(
    List<int> bytes, {
    required String fileName,
  }) async {
    if (state.installing) {
      return;
    }
    _beginInstall(t.plugin.installingFromLocal);

    try {
      final message = await PluginInstallService.I.installFromLocalBytes(
        bytes,
        fileName: fileName,
      );
      _reportInstallSuccess(message);
    } catch (e) {
      _reportInstallFailure(
        t.plugin.readLocalPluginFailed(
          error: normalizePluginInstallErrorMessage(e),
        ),
      );
    }
  }

  Future<void> installFromNetworkUrl(String rawUrl) async {
    if (state.installing) {
      return;
    }
    _beginInstall(t.plugin.installingFromNetwork);

    try {
      final message = await PluginInstallService.I.installFromNetworkUrl(
        rawUrl,
      );
      _reportInstallSuccess(message);
    } catch (e) {
      _reportInstallFailure(
        t.plugin.networkDownloadFailed(
          error: normalizePluginInstallErrorMessage(e),
        ),
      );
    }
  }

  void _beginInstall(String message) {
    emit(state.copyWith(installing: true, installMessage: message));
  }

  /// 设置读取失败时按「关闭」处理：宁可少展示，也不要因为读不到配置
  /// 把受限来源放出来。库没初始化时（启动早期）这里会抛，必须兜住。
  bool get _showRestrictedSources {
    try {
      return objectbox.userSettingBox
              .get(1)
              ?.globalSetting
              .showRestrictedSources ??
          false;
    } catch (_) {
      return false;
    }
  }

  void _reportInstallFailure(String message) {
    emit(state.copyWith(installing: false, installMessage: ''));
    showErrorToast(message);
  }

  void _reportInstallSuccess(String message) {
    emit(state.copyWith(installing: false, installMessage: ''));
    showSuccessToast(message);
  }
}
