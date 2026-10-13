part of '../sync_service.dart';

const String _libraryPresentationBlockName = 'libraryPresentation';

Future<_SettingsBlockPayload?> _buildLocalLibraryPresentationBlock() async =>
    _libraryPresentationBlock(
      await LibraryPresentationStore.instance.readAll(),
    );

_SettingsBlockPayload? _libraryPresentationBlock(
  Map<String, LibraryPresentationPreference> preferences,
) {
  // 新设备没有保存过偏好，不能用宿主默认值冲掉云端设置。
  if (preferences.isEmpty) return null;
  return _SettingsBlockPayload(
    name: _libraryPresentationBlockName,
    updatedAt: preferences.values.fold(
      0,
      (latest, preference) =>
          preference.updatedAt > latest ? preference.updatedAt : latest,
    ),
    data: LibraryPresentationPreferences.encode(preferences),
  );
}

_SettingsBlockPayload? _mergeLibraryPresentationBlocks(
  _SettingsBlockPayload? local,
  _SettingsBlockPayload? remote,
) => _libraryPresentationBlock(
  LibraryPresentationPreferences.merge(
    LibraryPresentationPreferences.decode(local?.data),
    LibraryPresentationPreferences.decode(remote?.data),
  ),
);

Future<void> _applyLibraryPresentationBlockData(
  Map<String, dynamic> data, {
  bool force = false,
}) => LibraryPresentationStore.instance.apply(
  LibraryPresentationPreferences.decode(data),
  force: force,
);

@visibleForTesting
Future<Map<String, dynamic>?> localLibraryPresentationBlockForTest() async =>
    (await _buildLocalLibraryPresentationBlock())?.toJson();

/// 走生产快照合并路径，验证开关、旧载荷、各位置的独立合并和再次上传。
@visibleForTesting
Future<Map<String, dynamic>> mergeSettingsPayloadsForTest(
  GlobalSettingState state,
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
) async {
  final merged = await _mergeSettingsSnapshots(
    state,
    _snapshotFromPayload(local, fallbackSyncTime: 1),
    _snapshotFromPayload(remote, fallbackSyncTime: 1),
  );
  return _buildSettingsPayload(merged.mergedState, merged.mergedSnapshot);
}

@visibleForTesting
Future<void> applyLibraryPresentationBlockForTest(
  Map<String, dynamic> data, {
  bool force = false,
}) => _applyLibraryPresentationBlockData(data, force: force);
