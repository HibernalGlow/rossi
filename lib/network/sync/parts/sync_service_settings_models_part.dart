part of '../sync_service.dart';

class _SettingsSnapshot {
  const _SettingsSnapshot({required this.blocks});

  final Map<String, _SettingsBlockPayload> blocks;

  int get syncTime => _computeSnapshotSyncTime(blocks);
}

class _SettingsBlockPayload {
  _SettingsBlockPayload({
    required this.name,
    required this.updatedAt,
    required this.data,
  }) : contentMd5 = _calculateStructuredMd5(data);

  final String name;
  final int updatedAt;
  final Map<String, dynamic> data;
  final String contentMd5;

  Map<String, dynamic> toJson() {
    return {'updatedAt': updatedAt, 'data': data};
  }
}

class _LocalSettingsBlockMeta {
  const _LocalSettingsBlockMeta({required this.updatedAt, required this.hash});

  factory _LocalSettingsBlockMeta.fromBlock(_SettingsBlockPayload block) {
    return _LocalSettingsBlockMeta(
      updatedAt: block.updatedAt,
      hash: block.contentMd5,
    );
  }

  factory _LocalSettingsBlockMeta.fromJson(Map<String, dynamic> json) {
    return _LocalSettingsBlockMeta(
      updatedAt: int.tryParse(json['updatedAt']?.toString() ?? '') ?? 0,
      hash: json['hash']?.toString() ?? '',
    );
  }

  final int updatedAt;
  final String hash;

  Map<String, dynamic> toJson() {
    return {'updatedAt': updatedAt, 'hash': hash};
  }
}

class _SettingsMergeResult {
  const _SettingsMergeResult({
    required this.mergedState,
    required this.mergedSnapshot,
    required this.syncTime,
    required this.shouldApplyLocalState,
    required this.shouldApplyPluginData,
    required this.pluginBlockData,
    required this.shouldApplyWorkspace,
    required this.workspaceBlockData,
    required this.localBlockMeta,
  });

  final GlobalSettingState mergedState;
  final _SettingsSnapshot mergedSnapshot;
  final int syncTime;
  final bool shouldApplyLocalState;
  final bool shouldApplyPluginData;
  final Map<String, dynamic> pluginBlockData;

  /// 云端那份布局赢了、且与本机不同 ⇒ 要把 [workspaceBlockData] 落到布局上。
  final bool shouldApplyWorkspace;
  final Map<String, dynamic> workspaceBlockData;

  final Map<String, _LocalSettingsBlockMeta> localBlockMeta;
}
