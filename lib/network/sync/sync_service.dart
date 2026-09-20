import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';

import 'package:zephyr/network/sync/comic_sync_core.dart';
import 'package:zephyr/network/sync/s3_sync_service.dart';
import 'package:zephyr/network/sync/webdav_sync_service.dart';
import 'package:zephyr/network/sync/workspace_sync_codec.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/service/workspace_layout_bridge.dart';

const String _settingsSyncSchemaVersion = 'v2';
const String _settingsBlockMetaPrefsKey = 'sync.settings.block.meta.v3';

const String _appearanceBlockName = 'appearance';
const String _libraryBlockName = 'library';
const String _readerBlockName = 'reader';
const String _shellBlockName = 'shell';
const String _toastBlockName = 'toast';
const String _fileManagerBlockName = 'fileManager';
const String _operationBindingBlockName = 'operationBinding';

/// 工作台布局（泳道 / 面板 / 卡片 / 交互）那一块。
///
/// 它是**唯一**一个数据源不在 `GlobalSettingState` 里的块 —— 布局的真相是磁盘上的
/// `workspace_layout.json`（见 `WorkspaceSyncCodec`）。因此它不参与
/// [_applySyncableBlocksToState] 的那次「平铺回状态」，而是自己走一条
/// 读文件 / 改写文件的路（[_applyWorkspaceBlockData]）。
const String _workspaceBlockName = 'workspace';
const String _pluginsBlockName = 'plugins';

/// 「块 → `GlobalSettingState` **顶层键**」的唯一真相。
///
/// 抽块（上传）与应用（下载）都读这一张表。从前是两份手工列表 ——
/// 一份挑键、一份 `addAll` 回去，漏改一边的表现是「上传带上去了、下载回来却不生效」，
/// 而两边分开看都自洽。想同步一个新字段，只在这里加一个键。
///
/// **`reader` 块刻意不在这张表里**：它的载荷形状是**冻结**的 ——
/// 老版本把整个 `readSetting` 对象直接当块数据（不是 `{'readSetting': {...}}`），
/// 旧客户端下载时会 `json['readSetting'] = <块数据>`；这里若顺手统一成
/// 「顶层键映射」，老客户端就会把 `{'readSetting': {...}}` 整个当成
/// `ReadSettingState`，**所有阅读设置静默回默认**。形状不动，只在代码里单独写。
const Map<String, List<String>> _settingsBlockKeys = <String, List<String>>{
  _appearanceBlockName: <String>[
    'dynamicColor',
    'themeMode',
    'isAMOLED',
    'seedColor',
    'tweakcnThemeJson',
    'tweakcnThemeEnabled',
    'locale',
    'localeFollowsSystem',
    'welcomePageNum',
    'chineseConvertMode',
  ],
  _libraryBlockName: <String>[
    'maskedKeywords',
    'comicChoice',
    'disableBika',
    'updateAccelerate',
    'retryDownloadUntilSuccess',
    'searchHistory',
    'downloadConcurrency',
    'downloadDelayMs',
    'downloadAutoRetryCount',
    'autoFavoriteOnDownload',
    'writeDownloadMetadataFile',
    'oldPageRollbackEnabled',
    'cloudFavoritePreferred',
    'autoFollowOnCollect',
    'leftHandModeEnabled',
    'clickCoverToStartReading',
    'comicInfoInlineReadButton',
    'bookshelfSetting',
    'comicCardSetting',
    'discoverSetting',
    // 收藏 tag（含别名）与画师名单不同，是**跨端偏好**：换设备继续要同一份标签集。
    'favoriteTagSetting',
  ],
  _shellBlockName: <String>[
    // 启动落点。手机端没有工作台入口时会自己忽略（`resolveStartupLanding`），
    // 所以从桌面同步到手机无害。
    'startWithWorkspace',
    // 下面三条是**平台专属**开关：本平台不读它，同步过去也就不会有效果，
    // 但两台 Android / 两台桌面之间是有意义的，所以一并带走。
    'forceEnableImpeller',
    'androidKeepAliveEnabled',
    'backPressExitEnabled',
    // 桌面端「透明标题栏」。同样是平台专属：手机端根本没这条栏，
    // 同步过去不会有效果，但两台桌面之间是有意义的。
    'transparentDesktopTitleBar',
    // 透明档的摆放方式（独立行 / 融合浮层），只在开关打开时被读到，
    // 但它是用户偏好不是本机事实 —— 跟主开关一起走，不然两台机器会分裂。
    'transparentTitleBarFused',
  ],
  _toastBlockName: <String>['toastSetting', 'switchToastSetting'],
  _fileManagerBlockName: <String>['fileManagerSetting'],
  _operationBindingBlockName: <String>['operationBindingSetting'],
};

/// 块里**带走整个子对象、但要剔掉其中几项**的顶层键。
///
/// 与 `_settingsBlockKeys` 的分工：那张表管「哪些顶层键进哪个块」，这张管
/// 「某个子对象内部哪几项是本机事实、不许跟着走」。
///
/// 现在只有一条 —— 文件管理器的 `homePath`：它是本机绝对路径（Windows 与 macOS
/// 上对方的用户目录根本不存在），同步过去只会得到「主页键点了没反应」；
/// 而 Rust 侧 `set_home_path` 只接受真实存在的目录，等于每同步一次就把对方
/// 的主页路径清空一次。与 `customExportPath` 同一条口径：**路径是本机事实，
/// 不是偏好**。
///
/// 这一层必须是**显式**的名单，而不是「反正 `_applySyncableBlocksToState` 会
/// 按本位写回」：那条写回只能护住 `homePath` 一个字段，而这里要表达的是一条
/// 通用规矩。
const Map<String, List<String>> _blockNestedKeyExclusions =
    <String, List<String>>{
      'fileManagerSetting': <String>['homePath'],
    };

/// 上面那张表里**住在 `GlobalSettingState` 内**的块名。
const List<String> _settingsStateBlockNames = <String>[
  _appearanceBlockName,
  _libraryBlockName,
  _readerBlockName,
  _shellBlockName,
  _toastBlockName,
  _fileManagerBlockName,
  _operationBindingBlockName,
];

/// 由「同步设置」总开关（`syncSetting.syncSettings`）统辖的全部块。
const List<String> _syncableSettingsBlockNames = <String>[
  ..._settingsStateBlockNames,
  _workspaceBlockName,
];

bool isSyncServiceConfigured(GlobalSettingState state) {
  switch (state.syncSetting.syncServiceType) {
    case SyncServiceType.none:
      return false;
    case SyncServiceType.webdav:
      return WebDavSyncService.isConfigured(state);
    case SyncServiceType.s3:
      return S3SyncService.isConfigured(state);
  }
}

ComicSyncRemoteAdapter? createSyncAdapter(GlobalSettingState state) {
  if (!isSyncServiceConfigured(state)) {
    return null;
  }

  switch (state.syncSetting.syncServiceType) {
    case SyncServiceType.none:
      return null;
    case SyncServiceType.webdav:
      return WebDavSyncService(state);
    case SyncServiceType.s3:
      return S3SyncService(state);
  }
}

Future<void> autoSync(
  GlobalSettingState state, {
  GlobalSettingCubit? globalSettingCubit,
  ComicFollowCubit? comicFollowCubit,
}) async {
  final adapter = createSyncAdapter(state);
  if (adapter == null) {
    return;
  }

  await runComicSync(adapter);

  // 同步后重新加载追更列表，确保内存状态与数据库一致。
  await comicFollowCubit?.loadFromDatabase();

  if (!state.syncSetting.syncSettings && !state.syncSetting.syncPlugins) {
    logger.d('设置同步和插件同步均未启用，跳过配置同步');
    return;
  }

  await _syncSettings(
    adapter,
    globalSettingCubit: globalSettingCubit,
    currentGlobalSetting: state,
  );
}

/// 手动上传：以本机数据为准，覆盖云端。
///
/// 包含漫画数据，以及开关已启用的设置 / 插件配置。
Future<void> manualUploadToCloud({
  required GlobalSettingState state,
  GlobalSettingCubit? globalSettingCubit,
  ComicFollowCubit? comicFollowCubit,
}) async {
  final adapter = createSyncAdapter(state);
  if (adapter == null) {
    throw StateError('未配置同步服务，请先选择并配置 WebDAV 或 S3');
  }

  await uploadComicData(adapter);
  await _manualUploadSettings(
    adapter,
    state: state,
    globalSettingCubit: globalSettingCubit,
  );

  // 同步后重新加载追更列表，确保内存状态与数据库一致。
  await comicFollowCubit?.loadFromDatabase();
}

/// 手动下载：以云端数据为准，应用到本机。
///
/// 包含漫画数据，以及开关已启用的设置 / 插件配置。
Future<void> manualDownloadFromCloud({
  required GlobalSettingState state,
  GlobalSettingCubit? globalSettingCubit,
  ComicFollowCubit? comicFollowCubit,
}) async {
  final adapter = createSyncAdapter(state);
  if (adapter == null) {
    throw StateError('未配置同步服务，请先选择并配置 WebDAV 或 S3');
  }

  await downloadComicData(adapter);
  await _manualDownloadSettings(
    adapter,
    state: state,
    globalSettingCubit: globalSettingCubit,
  );

  // 同步后重新加载追更列表，确保内存状态与数据库一致。
  await comicFollowCubit?.loadFromDatabase();
}

/// 手动上传设置与插件数据（以本地为准，直接覆盖云端）。
Future<void> _manualUploadSettings(
  ComicSyncRemoteAdapter adapter, {
  required GlobalSettingState state,
  GlobalSettingCubit? globalSettingCubit,
}) async {
  if (!state.syncSetting.syncSettings && !state.syncSetting.syncPlugins) {
    return;
  }

  final localSnapshot = await _buildLocalSettingsSnapshot(state);
  final localPayload = _buildSettingsPayload(state, localSnapshot);
  final localBytes = await ComicSyncCore.encodeEncryptedPayload(
    utf8.encode(jsonEncode(localPayload)),
  );
  final localMd5 = ComicSyncCore.calculateMd5(localBytes);

  await _uploadSettingsPayload(
    adapter,
    payloadBytes: localBytes,
    payloadMd5: localMd5,
    syncTime: localSnapshot.syncTime,
  );
  await _updateLocalSettingsSyncTime(
    state,
    syncTime: localSnapshot.syncTime,
    globalSettingCubit: globalSettingCubit,
  );
  await _cleanupRemoteSettingsFiles(adapter);
}

/// 手动下载设置与插件数据（以云端为准，应用到本机）。
Future<void> _manualDownloadSettings(
  ComicSyncRemoteAdapter adapter, {
  required GlobalSettingState state,
  GlobalSettingCubit? globalSettingCubit,
}) async {
  if (!state.syncSetting.syncSettings && !state.syncSetting.syncPlugins) {
    return;
  }

  final allRemote = await adapter.listRemoteDataFiles();
  final syncRootFiles = allRemote.where(ComicSyncCore.isSyncRootPath).toList();
  final remoteMd5 = await _downloadRemoteText(
    adapter,
    _remoteSettingsMd5Path,
    returnEmptyIfMissing: true,
  );
  final remoteData = await _selectLatestRemoteSettingsData(
    adapter,
    syncRootFiles,
    remoteMd5,
  );
  if (remoteData == null) {
    logger.d('[sync][settings] manual_download skipped reason=remote_missing');
    return;
  }

  final remoteSnapshot = await _decodeSettingsPayload(
    remoteData.bytes,
    fallbackSyncTime: remoteData.timestamp,
  );

  final blocksToApply = <String, _SettingsBlockPayload>{};
  if (state.syncSetting.syncSettings) {
    for (final blockName in _syncableSettingsBlockNames) {
      final block = remoteSnapshot.blocks[blockName];
      if (block != null) {
        blocksToApply[blockName] = block;
      }
    }
  }
  if (state.syncSetting.syncPlugins) {
    final pluginBlock = remoteSnapshot.blocks[_pluginsBlockName];
    if (pluginBlock != null) {
      blocksToApply[_pluginsBlockName] = pluginBlock;
    }
  }
  if (blocksToApply.isEmpty) {
    return;
  }

  final mergedState = _applySyncableBlocksToState(state, blocksToApply)
      .copyWith(
        syncSetting: state.syncSetting.copyWith(
          settingsSyncTime: remoteSnapshot.syncTime,
        ),
      );
  await _applyMergedGlobalState(
    mergedState,
    globalSettingCubit: globalSettingCubit,
  );

  final pluginBlock = blocksToApply[_pluginsBlockName];
  if (pluginBlock != null) {
    await _applyPluginBlockData(pluginBlock.data);
  }

  // 手动下载 = 「以云端为准」，布局块不做时间戳比较，直接采纳。
  final workspaceBlock = blocksToApply[_workspaceBlockName];
  if (workspaceBlock != null) {
    await _applyWorkspaceBlockData(workspaceBlock.data);
  }

  await _persistLocalSettingsBlockMeta({
    for (final entry in blocksToApply.entries)
      entry.key: _LocalSettingsBlockMeta.fromBlock(entry.value),
  });
}

Future<void> _syncSettings(
  ComicSyncRemoteAdapter adapter, {
  required GlobalSettingState currentGlobalSetting,
  GlobalSettingCubit? globalSettingCubit,
}) async {
  final localGlobal = globalSettingCubit?.state ?? currentGlobalSetting;
  final localSnapshot = await _buildLocalSettingsSnapshot(localGlobal);
  final localPayload = _buildSettingsPayload(localGlobal, localSnapshot);
  final localBytes = await ComicSyncCore.encodeEncryptedPayload(
    utf8.encode(jsonEncode(localPayload)),
  );
  final localMd5 = ComicSyncCore.calculateMd5(localBytes);

  final allRemote = await adapter.listRemoteDataFiles();
  final legacyFiles = allRemote
      .where(ComicSyncCore.isLegacyRemotePath)
      .toList();
  if (legacyFiles.isNotEmpty) {
    await adapter.deleteRemoteFiles(legacyFiles);
  }
  final syncRootFiles = allRemote.where(ComicSyncCore.isSyncRootPath).toList();

  final remoteMd5 = await _downloadRemoteText(
    adapter,
    _remoteSettingsMd5Path,
    returnEmptyIfMissing: true,
  );

  logger.d(
    '[sync][settings] precheck localTime=${localSnapshot.syncTime} '
    'localMd5=$localMd5 remoteMd5=$remoteMd5 remoteFiles=${syncRootFiles.length}',
  );

  if (remoteMd5.isNotEmpty && remoteMd5 == localMd5) {
    logger.d('[sync][settings] decision=skip reason=md5_equal');
    await _cleanupRemoteSettingsFiles(adapter);
    await _updateLocalSettingsSyncTime(
      localGlobal,
      syncTime: localSnapshot.syncTime,
      globalSettingCubit: globalSettingCubit,
    );
    return;
  }

  final remoteData = await _selectLatestRemoteSettingsData(
    adapter,
    syncRootFiles,
    remoteMd5,
  );

  if (remoteMd5.isEmpty || remoteData == null) {
    logger.d('[sync][settings] decision=upload reason=remote_missing');
    await _uploadSettingsPayload(
      adapter,
      payloadBytes: localBytes,
      payloadMd5: localMd5,
      syncTime: localSnapshot.syncTime,
    );
    await _updateLocalSettingsSyncTime(
      localGlobal,
      syncTime: localSnapshot.syncTime,
      globalSettingCubit: globalSettingCubit,
    );
    await _cleanupRemoteSettingsFiles(adapter);
    return;
  }

  final remoteSnapshot = await _decodeSettingsPayload(
    remoteData.bytes,
    fallbackSyncTime: remoteData.timestamp,
  );
  final mergeResult = await _mergeSettingsSnapshots(
    localGlobal,
    localSnapshot,
    remoteSnapshot,
  );

  logger.d(
    '[sync][settings] compare localTime=${localSnapshot.syncTime} '
    'remoteTime=${remoteSnapshot.syncTime} mergedTime=${mergeResult.syncTime} '
    'localMd5=$localMd5 remoteMd5=$remoteMd5',
  );

  if (mergeResult.shouldApplyLocalState) {
    logger.d('[sync][settings] decision=apply_remote_blocks');
    await _applyMergedGlobalState(
      mergeResult.mergedState,
      globalSettingCubit: globalSettingCubit,
    );
  } else {
    await _updateLocalSettingsSyncTime(
      localGlobal,
      syncTime: mergeResult.syncTime,
      globalSettingCubit: globalSettingCubit,
    );
  }

  if (mergeResult.shouldApplyPluginData) {
    await _applyPluginBlockData(mergeResult.pluginBlockData);
  }

  if (mergeResult.shouldApplyWorkspace) {
    await _applyWorkspaceBlockData(mergeResult.workspaceBlockData);
  }

  await _persistLocalSettingsBlockMeta(mergeResult.localBlockMeta);

  final mergedPayload = _buildSettingsPayload(
    mergeResult.mergedState,
    mergeResult.mergedSnapshot,
  );
  final mergedBytes = await ComicSyncCore.encodeEncryptedPayload(
    utf8.encode(jsonEncode(mergedPayload)),
  );
  final mergedMd5 = ComicSyncCore.calculateMd5(mergedBytes);

  if (mergedMd5 != remoteMd5) {
    logger.d('[sync][settings] decision=upload reason=merged_snapshot_changed');
    await _uploadSettingsPayload(
      adapter,
      payloadBytes: mergedBytes,
      payloadMd5: mergedMd5,
      syncTime: mergeResult.syncTime,
    );
  } else {
    logger.d(
      '[sync][settings] decision=skip_upload reason=merged_snapshot_equals_remote',
    );
  }

  await _cleanupRemoteSettingsFiles(adapter);
}

Map<String, dynamic> _buildSettingsPayload(
  GlobalSettingState globalSetting,
  _SettingsSnapshot snapshot,
) {
  final sanitizedGlobal = globalSetting.copyWith(
    syncSetting: globalSetting.syncSetting.copyWith(settingsSyncTime: 0),
  );

  final globalSettingJson = sanitizedGlobal.toJson();
  globalSettingJson.remove('customExportPath');
  globalSettingJson.remove('appLockSetting');
  globalSettingJson.remove('cacheSetting');
  globalSettingJson.remove('favoriteArtistSetting');

  final pluginBlock = snapshot.blocks[_pluginsBlockName];
  final pluginConfigs = pluginBlock == null
      ? <Map<String, dynamic>>[]
      : _toJsonMapList(pluginBlock.data['pluginConfigs']);
  final pluginInfos = pluginBlock == null
      ? <Map<String, dynamic>>[]
      : _toJsonMapList(pluginBlock.data['pluginInfos']);

  return {
    'version': syncDataVersion,
    'schemaVersion': _settingsSyncSchemaVersion,
    'syncTime': snapshot.syncTime,
    'globalSetting': globalSettingJson,
    'pluginConfigs': pluginConfigs,
    'pluginInfos': pluginInfos,
    'blocks': {
      for (final entry in snapshot.blocks.entries)
        entry.key: entry.value.toJson(),
    },
  };
}

Future<_SettingsSnapshot> _buildLocalSettingsSnapshot(
  GlobalSettingState globalSetting,
) async {
  final existingMeta = await _loadLocalSettingsBlockMeta();
  final nextMeta = Map<String, _LocalSettingsBlockMeta>.from(existingMeta);
  final blockPayloads = <String, _SettingsBlockPayload>{};
  final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
  final baseTimestamp = _normalizeTimestamp(
    globalSetting.syncSetting.settingsSyncTime,
    fallback: nowMs,
  );

  if (globalSetting.syncSetting.syncSettings) {
    final blockData = _extractSyncableSettingsBlocks(globalSetting);
    for (final entry in blockData.entries) {
      final blockName = entry.key;
      final data = entry.value;
      final hash = _calculateStructuredMd5(data);
      final previous = existingMeta[blockName];
      final updatedAt = previous == null
          ? baseTimestamp
          : previous.hash == hash
          ? _normalizeTimestamp(previous.updatedAt, fallback: baseTimestamp)
          : nowMs;
      final payload = _SettingsBlockPayload(
        name: blockName,
        updatedAt: updatedAt,
        data: data,
      );
      blockPayloads[blockName] = payload;
      nextMeta[blockName] = _LocalSettingsBlockMeta.fromBlock(payload);
    }

    // 工作台布局单独抽一次：它的真相在 `workspace_layout.json`（活的 cubit 优先），
    // 不在 `GlobalSettingState` 里，所以上面那次 `_extractSyncableSettingsBlocks`
    // 抽不到它。
    await _appendLocalWorkspaceBlock(
      blockPayloads,
      nextMeta: nextMeta,
      existingMeta: existingMeta,
      nowMs: nowMs,
    );
  }

  if (globalSetting.syncSetting.syncPlugins) {
    final pluginData = _buildPluginBlockData();
    final hash = _calculateStructuredMd5(pluginData);
    final previous = existingMeta[_pluginsBlockName];
    final pluginBaseTimestamp = _derivePluginBlockTimestamp(
      pluginData,
      fallback: baseTimestamp,
    );
    final updatedAt = previous == null
        ? pluginBaseTimestamp
        : previous.hash == hash
        ? _normalizeTimestamp(previous.updatedAt, fallback: pluginBaseTimestamp)
        : nowMs;
    final pluginBlock = _SettingsBlockPayload(
      name: _pluginsBlockName,
      updatedAt: updatedAt,
      data: pluginData,
    );
    blockPayloads[_pluginsBlockName] = pluginBlock;
    nextMeta[_pluginsBlockName] = _LocalSettingsBlockMeta.fromBlock(
      pluginBlock,
    );
    logger.d(
      '[sync][plugins] local_snapshot '
      'count=${_toJsonMapList(pluginData['pluginInfos']).length} '
      'hash=$hash baseTs=$pluginBaseTimestamp finalTs=$updatedAt '
      'prevTs=${previous?.updatedAt ?? 0}',
    );
  }

  await _persistLocalSettingsBlockMeta(nextMeta);
  return _SettingsSnapshot(blocks: blockPayloads);
}

/// 本机那份布局**就是出厂值**时写在块上的时间戳。
///
/// 用 0 而不是「现在」：合并时 `_pickPreferredBlock` 判的是大小，0 一定输给
/// 云端那份真实时间戳 —— 这正是「本机没动过，云端说了算」。
///
/// 只有**布局块**会用到它（见 [_appendLocalWorkspaceBlock]）：其余块的第一次同步
/// 沿用「本机 = 现在」的老口径，不去动它们（那是另一件事，见 `docs/settings-sync-scope.md`）。
const int _factoryEqualBlockTimestamp = 0;

/// 出厂布局编码后的内容哈希 —— 「本机这份布局动过没有」的判据。
///
/// 与块哈希走**同一个**编码函数（`WorkspaceSyncCodec.encode`）：
/// 换一个编码方式去比，等于两边对「出厂」的定义悄悄分叉，判据就永远不成立。
final String _workspaceFactoryHash = _calculateStructuredMd5(
  WorkspaceSyncCodec.encode(WorkspaceLayoutSnapshot.defaults()),
);

/// 把本机布局作为一块补进本轮快照。
///
/// **为什么这一块的 `updatedAt` 规则与另外几块不同**：布局是用户手摆出来的东西，
/// 而「本机那份」在一台新装设备、或者一台从没打开过工作台的手机上就是**出厂值**。
/// 照抄老口径（首次同步 = 现在）会让那台设备在一轮自动同步里把云端那套精心摆好的
/// 泳道 / 面板 / 卡片冲掉 —— 而且事后无从解释（用户没动过任何东西）。
///
/// 「等于出厂值」这一半很要紧：装完机先把布局摆好、再打开同步开关的用户
/// （这时本地同样没有 meta）仍然按「本机说了算」走，不会被他自己的云端旧值盖掉。
Future<void> _appendLocalWorkspaceBlock(
  Map<String, _SettingsBlockPayload> blockPayloads, {
  required Map<String, _LocalSettingsBlockMeta> nextMeta,
  required Map<String, _LocalSettingsBlockMeta> existingMeta,
  required int nowMs,
}) async {
  final data = await _buildLocalWorkspaceBlockData();
  // 读不到布局 ⇒ 本轮整块不带。**不是**「按出厂值上传」——见助手函数的说明。
  if (data.isEmpty) return;

  final hash = _calculateStructuredMd5(data);
  final previous = existingMeta[_workspaceBlockName];
  final updatedAt = _resolveWorkspaceBlockUpdatedAt(
    hash: hash,
    previous: previous,
    nowMs: nowMs,
  );

  final payload = _SettingsBlockPayload(
    name: _workspaceBlockName,
    updatedAt: updatedAt,
    data: data,
  );
  blockPayloads[_workspaceBlockName] = payload;
  nextMeta[_workspaceBlockName] = _LocalSettingsBlockMeta.fromBlock(payload);
  logger.d(
    '[sync][workspace] local_snapshot hash=$hash factory=$_workspaceFactoryHash '
    'ts=$updatedAt prevTs=${previous?.updatedAt ?? -1}',
  );
}

/// 布局块的 `updatedAt`（**纯函数**，判据直接跑它 —— 验的就是上线跑的这段）。
///
/// 三种情况：
/// 1. 本机还没有这一块的 meta（从没同步过它）：
///    - 本机那份**就是出厂值** ⇒ [_factoryEqualBlockTimestamp]（= 0，云端说了算）；
///    - 本机那份与出厂不同（用户先摆好布局、后打开同步开关）⇒ 现在，本机说了算；
/// 2. 内容哈希没变 ⇒ 沿用原来的时间。**不能**碰 `_normalizeTimestamp`：
///    它把 0 当作「没设过」而退回 now，于是第 1 条的判断每轮都被刷新成
///    「本机刚改过」，云端那套布局永远进不来；
/// 3. 内容变了 ⇒ 现在。
int _resolveWorkspaceBlockUpdatedAt({
  required String hash,
  required _LocalSettingsBlockMeta? previous,
  required int nowMs,
}) {
  if (previous == null) {
    return hash == _workspaceFactoryHash ? _factoryEqualBlockTimestamp : nowMs;
  }
  return previous.hash == hash ? previous.updatedAt : nowMs;
}

/// 本机布局 → 块数据；**读不到就返回空表**（调用方据此整块不带）。
///
/// 这里刻意用 `readIfAvailable` 而不是 `read`：后者的兜底是「给出厂值」，
/// 而「读盘失败」与「用户没改过布局」在同步里的处置**正好相反** ——
/// 前者必须整块不带（否则拿一份假的「本机布局」去冲掉对方设备上的真布局，
/// 而原因只是一次读盘失败），后者才该让云端说了算（那由块时间戳 0 表达）。
Future<Map<String, dynamic>> _buildLocalWorkspaceBlockData() async {
  try {
    final snapshot = await WorkspaceLayoutBridge.instance.readIfAvailable();
    if (snapshot == null) {
      logger.d('[sync][workspace] 本机还没有可读的布局，本轮不带布局块');
      return const <String, dynamic>{};
    }
    return WorkspaceSyncCodec.encode(snapshot);
  } on Object catch (e) {
    logger.w('[sync][workspace] 读取本机布局失败，本轮不带布局块: $e');
    return const <String, dynamic>{};
  }
}

/// 云端布局块 → 本机（本机独有的字段按本位保留，见 `WorkspaceSyncCodec.decode`）。
///
/// 工作台在场时改的是活的 cubit —— 直接写盘会被它的去抖落盘覆盖回去，
/// 现象是「同步说明明成功了，界面纹丝不动」。这条路收在 `WorkspaceLayoutBridge`。
Future<void> _applyWorkspaceBlockData(Map<String, dynamic> data) async {
  if (!WorkspaceSyncCodec.isUsableBlock(data)) {
    logger.d('[sync][workspace] apply skipped reason=unusable_block');
    return;
  }
  try {
    final base = await WorkspaceLayoutBridge.instance.read();
    final merged = WorkspaceSyncCodec.decode(data, base: base);
    await WorkspaceLayoutBridge.instance.apply(merged);
    logger.d(
      '[sync][workspace] applied mode=${merged.mode.name} '
      'laneOrder=${merged.layout.laneOrder.join(",")} '
      'panels=${merged.board.panels.length} cards=${merged.board.cards.length} '
      'activePanel=${merged.activePanel.length}',
    );
  } on Object catch (e) {
    // 一份读不懂的云端布局不该把整轮设置同步带走（后面的 meta 落盘与合并上传
    // 都还等着跑），也不该让用户在同步结果里看到一条红字。
    logger.w('[sync][workspace] 应用云端布局失败，已跳过: $e');
  }
}

Future<_SettingsSnapshot> _decodeSettingsPayload(
  List<int> payloadBytes, {
  required int fallbackSyncTime,
}) async {
  final raw = await ComicSyncCore.decodeEncryptedPayload(payloadBytes);
  final payloadRaw = jsonDecode(utf8.decode(raw));
  return _snapshotFromPayload(
    _toJsonMap(payloadRaw),
    fallbackSyncTime: fallbackSyncTime,
  );
}

_SettingsSnapshot _snapshotFromPayload(
  Map<String, dynamic> payload, {
  required int fallbackSyncTime,
}) {
  final blocksJson = _toJsonMap(payload['blocks']);
  final remoteSyncTime = _extractSyncTimeFromPayload(
    payload,
    fallbackFromFileName: fallbackSyncTime,
  );
  final blocks = <String, _SettingsBlockPayload>{};

  for (final entry in blocksJson.entries) {
    final blockJson = _toJsonMap(entry.value);
    final data = _toJsonMap(blockJson['data']);
    if (data.isEmpty) {
      continue;
    }
    blocks[entry.key] = _SettingsBlockPayload(
      name: entry.key,
      updatedAt: _normalizeTimestamp(
        int.tryParse(blockJson['updatedAt']?.toString() ?? ''),
        fallback: remoteSyncTime,
      ),
      data: data,
    );
  }

  if (blocks.isEmpty) {
    final globalSettingJson = _toJsonMap(payload['globalSetting']);
    if (globalSettingJson.isNotEmpty) {
      final remoteGlobal = GlobalSettingState.fromJson(globalSettingJson);
      final legacyBlocks = _extractSyncableSettingsBlocks(remoteGlobal);
      for (final entry in legacyBlocks.entries) {
        blocks[entry.key] = _SettingsBlockPayload(
          name: entry.key,
          updatedAt: remoteSyncTime,
          data: entry.value,
        );
      }
    }
  }

  if (!blocks.containsKey(_pluginsBlockName)) {
    final pluginConfigs = _toJsonMapList(payload['pluginConfigs']);
    final pluginInfos = _toJsonMapList(payload['pluginInfos']);
    if (pluginConfigs.isNotEmpty || pluginInfos.isNotEmpty) {
      blocks[_pluginsBlockName] = _SettingsBlockPayload(
        name: _pluginsBlockName,
        updatedAt: remoteSyncTime,
        data: {'pluginConfigs': pluginConfigs, 'pluginInfos': pluginInfos},
      );
    }
  }

  return _SettingsSnapshot(blocks: blocks);
}

Future<_SettingsMergeResult> _mergeSettingsSnapshots(
  GlobalSettingState localGlobal,
  _SettingsSnapshot localSnapshot,
  _SettingsSnapshot remoteSnapshot,
) async {
  final mergedBlocks = <String, _SettingsBlockPayload>{};
  final localBlockMeta = await _loadLocalSettingsBlockMeta();
  final nextMeta = Map<String, _LocalSettingsBlockMeta>.from(localBlockMeta);
  var shouldApplyLocalState = false;

  if (localGlobal.syncSetting.syncSettings) {
    // 只跑**住在 `GlobalSettingState` 内**的块。`workspace` 的数据源是布局
    // （文件 / 活的 cubit），单独处理一段 —— 把它混进这里会被
    // `_applySyncableBlocksToState` 当成「一批顶层键」平铺到全局设置 JSON 上。
    for (final blockName in _settingsStateBlockNames) {
      final localBlock = localSnapshot.blocks[blockName];
      if (localBlock == null) {
        continue;
      }
      final remoteBlock = remoteSnapshot.blocks[blockName];
      final mergedBlock = _pickPreferredBlock(localBlock, remoteBlock)!;
      mergedBlocks[blockName] = mergedBlock;
      nextMeta[blockName] = _LocalSettingsBlockMeta.fromBlock(mergedBlock);
      if (!_sameBlock(localBlock, mergedBlock)) {
        shouldApplyLocalState = true;
      }
    }
  } else {
    for (final blockName in _settingsStateBlockNames) {
      final remoteBlock = remoteSnapshot.blocks[blockName];
      if (remoteBlock != null) {
        mergedBlocks[blockName] = remoteBlock;
      }
    }
  }

  Map<String, dynamic> pluginBlockData = const <String, dynamic>{};
  var shouldApplyPluginData = false;

  final localPluginBlock = localSnapshot.blocks[_pluginsBlockName];
  final remotePluginBlock = remoteSnapshot.blocks[_pluginsBlockName];

  if (localGlobal.syncSetting.syncPlugins) {
    final mergedPluginBlock = _mergePluginBlocks(
      localPluginBlock,
      remotePluginBlock,
    );
    final decision = mergedPluginBlock == null
        ? 'none'
        : (localPluginBlock != null &&
              mergedPluginBlock.contentMd5 == localPluginBlock.contentMd5)
        ? 'local_or_merged_local'
        : (remotePluginBlock != null &&
              mergedPluginBlock.contentMd5 == remotePluginBlock.contentMd5)
        ? 'remote_or_merged_remote'
        : 'merged_union';
    logger.d(
      '[sync][plugins] merge '
      'localCount=${_pluginBlockCount(localPluginBlock)} '
      'localTs=${localPluginBlock?.updatedAt ?? 0} '
      'localHash=${localPluginBlock?.contentMd5 ?? ''} '
      'remoteCount=${_pluginBlockCount(remotePluginBlock)} '
      'remoteTs=${remotePluginBlock?.updatedAt ?? 0} '
      'remoteHash=${remotePluginBlock?.contentMd5 ?? ''} '
      'decision=$decision',
    );
    if (mergedPluginBlock != null) {
      mergedBlocks[_pluginsBlockName] = mergedPluginBlock;
      nextMeta[_pluginsBlockName] = _LocalSettingsBlockMeta.fromBlock(
        mergedPluginBlock,
      );
      pluginBlockData = mergedPluginBlock.data;
      if (!_sameBlock(localPluginBlock, mergedPluginBlock)) {
        shouldApplyPluginData = true;
      }
    }
  } else if (remotePluginBlock != null) {
    mergedBlocks[_pluginsBlockName] = remotePluginBlock;
    logger.d(
      '[sync][plugins] merge skipped_apply '
      'reason=local_sync_disabled remoteCount=${_pluginBlockCount(remotePluginBlock)} '
      'remoteTs=${remotePluginBlock.updatedAt}',
    );
  }

  // 工作台布局：与上面几块同一套 LWW（比块时间戳，谁新用谁），
  // 只是**落点不同** —— 不回到 `GlobalSettingState`，而是写回布局本身
  // （见 `_applyWorkspaceBlockData`）。
  Map<String, dynamic> workspaceBlockData = const <String, dynamic>{};
  var shouldApplyWorkspace = false;
  final localWorkspaceBlock = localSnapshot.blocks[_workspaceBlockName];
  final remoteWorkspaceBlock = remoteSnapshot.blocks[_workspaceBlockName];

  if (localGlobal.syncSetting.syncSettings) {
    final mergedWorkspaceBlock = _pickPreferredBlock(
      localWorkspaceBlock,
      remoteWorkspaceBlock,
    );
    if (mergedWorkspaceBlock != null) {
      mergedBlocks[_workspaceBlockName] = mergedWorkspaceBlock;
      nextMeta[_workspaceBlockName] = _LocalSettingsBlockMeta.fromBlock(
        mergedWorkspaceBlock,
      );
      if (!_sameBlock(localWorkspaceBlock, mergedWorkspaceBlock)) {
        shouldApplyWorkspace = true;
        workspaceBlockData = mergedWorkspaceBlock.data;
      }
    }
    logger.d(
      '[sync][workspace] merge localTs=${localWorkspaceBlock?.updatedAt ?? -1} '
      'localHash=${localWorkspaceBlock?.contentMd5 ?? ''} '
      'remoteTs=${remoteWorkspaceBlock?.updatedAt ?? -1} '
      'remoteHash=${remoteWorkspaceBlock?.contentMd5 ?? ''} '
      'apply=$shouldApplyWorkspace',
    );
  } else if (remoteWorkspaceBlock != null) {
    // 关着同步设置时，云端那块原样带回去再传（与另外几块同一条 passthrough），
    // 但**不**动本机布局。
    mergedBlocks[_workspaceBlockName] = remoteWorkspaceBlock;
  }

  final syncTimeBlocks = <String, _SettingsBlockPayload>{
    if (localGlobal.syncSetting.syncSettings)
      for (final blockName in _syncableSettingsBlockNames)
        if (mergedBlocks.containsKey(blockName))
          blockName: mergedBlocks[blockName]!,
  };
  if (localGlobal.syncSetting.syncPlugins &&
      mergedBlocks.containsKey(_pluginsBlockName)) {
    syncTimeBlocks[_pluginsBlockName] = mergedBlocks[_pluginsBlockName]!;
  }

  final mergedSyncTime = _computeSnapshotSyncTime(syncTimeBlocks);
  final mergedState = _applySyncableBlocksToState(localGlobal, mergedBlocks)
      .copyWith(
        syncSetting: localGlobal.syncSetting.copyWith(
          settingsSyncTime: mergedSyncTime,
        ),
      );

  return _SettingsMergeResult(
    mergedState: mergedState,
    mergedSnapshot: _SettingsSnapshot(blocks: mergedBlocks),
    syncTime: mergedSyncTime,
    shouldApplyLocalState: shouldApplyLocalState,
    shouldApplyPluginData: shouldApplyPluginData,
    pluginBlockData: pluginBlockData,
    shouldApplyWorkspace: shouldApplyWorkspace,
    workspaceBlockData: workspaceBlockData,
    localBlockMeta: nextMeta,
  );
}

Map<String, Map<String, dynamic>> _extractSyncableSettingsBlocks(
  GlobalSettingState state,
) {
  final json = _materializeJsonMap(state.toJson());
  return <String, Map<String, dynamic>>{
    // 表驱动：想同步一个字段只在 `_settingsBlockKeys` 里加一个键，
    // 抽块与应用两侧自动同时生效（从前是两份手工列表，漏改一边会得到
    // 「上传带上去了、下载却不生效」）。
    for (final entry in _settingsBlockKeys.entries)
      entry.key: <String, dynamic>{
        for (final key in entry.value)
          if (json.containsKey(key)) key: _stripNestedExclusions(key, json[key]),
      },
    // reader 块的载荷形状是**冻结**的：老版本直接拿整个 `readSetting` 对象当块数据。
    // 详见 `_settingsBlockKeys` 上那段说明 —— 统一成顶层键映射会让旧客户端
    // 把所有阅读设置静默读成默认值。
    _readerBlockName: _toJsonMap(json['readSetting']),
  };
}

/// 把某个顶层键的值里、登记为「本机事实」的内层字段剔掉
/// （名单见 `_blockNestedKeyExclusions`）。
///
/// 只重建一层 Map，不动原对象：`json` 是整份状态的物化副本，就地删键虽然
/// 当下看不出问题，但会让「上传的块」与「状态本身」变成同一份东西，
/// 后面任何一次调用方复用都会踩到。
Object? _stripNestedExclusions(String topLevelKey, Object? value) {
  final excluded = _blockNestedKeyExclusions[topLevelKey];
  if (excluded == null || value is! Map) return value;
  final copy = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = '${entry.key}';
    if (excluded.contains(key)) continue;
    copy[key] = entry.value;
  }
  return copy;
}

Map<String, dynamic> _buildPluginBlockData() {
  final deletedUuids = objectbox.pluginInfoBox
      .getAll()
      .where((item) => item.isDeleted)
      .map((item) => item.uuid.trim())
      .where((uuid) => uuid.isNotEmpty)
      .toSet();
  final blockedConfigNames = <String>{
    for (final uuid in deletedUuids)
      ..._buildPluginConfigNameCandidatesForSync(uuid),
  };

  final pluginConfigs = objectbox.pluginConfigBox
      .getAll()
      .map((item) {
        final name = item.name.trim();
        if (name.isEmpty || blockedConfigNames.contains(name)) {
          return <String, dynamic>{};
        }
        final json = item.toJson();
        json.remove('id');
        json['name'] = name;
        return json;
      })
      .where((item) => item.isNotEmpty)
      .toList();
  pluginConfigs.sort((a, b) {
    final aName = a['name']?.toString() ?? '';
    final bName = b['name']?.toString() ?? '';
    return aName.compareTo(bName);
  });

  final pluginInfos = objectbox.pluginInfoBox
      .getAll()
      .where((item) => !item.isDeleted)
      .map((item) {
        final json = item.toJson();
        json.remove('id');
        return json;
      })
      .toList();
  pluginInfos.sort((a, b) {
    final aKey = '${a['uuid'] ?? ''}:${a['version'] ?? ''}';
    final bKey = '${b['uuid'] ?? ''}:${b['version'] ?? ''}';
    return aKey.compareTo(bKey);
  });

  return {'pluginConfigs': pluginConfigs, 'pluginInfos': pluginInfos};
}

GlobalSettingState _applySyncableBlocksToState(
  GlobalSettingState localState,
  Map<String, _SettingsBlockPayload> blocks,
) {
  final json = _materializeJsonMap(localState.toJson());

  // 表驱动（与 `_extractSyncableSettingsBlocks` 共用同一张表）。
  //
  // **只认表里登记过的键**，不整块 `addAll`：块来自更新的版本时可能带着本版本
  // 不认识的字段，整块铺进状态 JSON 会让它们从「被 `fromJson` 忽略」变成
  // 「混进状态对象、再被写回本地库」—— 于是版本回退一次就留下一堆幽灵字段。
  for (final entry in _settingsBlockKeys.entries) {
    final data = blocks[entry.key]?.data;
    if (data == null) continue;
    for (final key in entry.value) {
      if (data.containsKey(key)) json[key] = data[key];
    }
  }

  final reader = blocks[_readerBlockName]?.data;
  if (reader != null) {
    json['readSetting'] = reader;
  }

  // 同步设置时，以下本地/安全相关配置保持本地值不变：
  // - 自定义导出路径、文件管理器主页路径、开屏密码/PIN、缓存管理配置：
  //   都是**本机事实**（路径在对方机器上多半不存在），不进云端；
  // - 收藏作者名单：属于本地私有偏好，不参与多端云同步；
  // - 同步配置本身、调试日志开关/地址：仍可能出现在旧版或未来的云端块中，
  //   这里显式跳过覆盖，确保本地值不被同步下来的内容修改。
  final merged = GlobalSettingState.fromJson(json);
  return merged.copyWith(
    syncSetting: localState.syncSetting,
    customExportPath: localState.customExportPath,
    appLockSetting: localState.appLockSetting,
    cacheSetting: localState.cacheSetting,
    enableMemoryDebug: localState.enableMemoryDebug,
    blockRustHttpRequests: localState.blockRustHttpRequests,
    logAddress: localState.logAddress,
    // 「黄黑溢出斜纹」也归这一档：它是本机的调试观感，不是跨端偏好
    // （它不在 `_settingsBlockKeys` 里，本来就同步不出去；这里显式写回是为了
    // 不依赖「块里恰好没这个键」这种巧合 —— 同上一条 `homePath` 的理由）。
    showLayoutOverflowStripes: localState.showLayoutOverflowStripes,
    favoriteArtistSetting: localState.favoriteArtistSetting,
    // 文件管理器那块只有 `homePath` 不同步（见 `_settingsBlockKeys`）。
    // 这里**显式**按本位写回，而不是依赖上面那次逐键覆盖的巧合 ——
    // 那条路保住 homePath 只是因为块里恰好没这个键，太隐晦：
    // 改一次合并口径（比如换成整块替换）就会静默把对方的主页路径清空。
    fileManagerSetting: merged.fileManagerSetting.copyWith(
      homePath: localState.fileManagerSetting.homePath,
    ),
  );
}

Future<void> _applyMergedGlobalState(
  GlobalSettingState value, {
  required GlobalSettingCubit? globalSettingCubit,
}) async {
  if (globalSettingCubit != null) {
    globalSettingCubit.applySyncedState(value);
    return;
  }

  final user = objectbox.userSettingBox.get(1);
  if (user != null) {
    user.globalSetting = value;
    objectbox.userSettingBox.put(user);
  }
}

Future<void> _applyPluginBlockData(Map<String, dynamic> pluginBlockData) async {
  final previousSnapshot = PluginRegistryService.I.snapshot;
  final pluginConfigJsonList = _toJsonMapList(pluginBlockData['pluginConfigs']);
  final pluginInfoJsonList = _toJsonMapList(pluginBlockData['pluginInfos']);
  logger.d(
    '[sync][plugins] apply_remote '
    'incomingInfos=${pluginInfoJsonList.length} incomingConfigs=${pluginConfigJsonList.length} '
    'previousRegistry=${previousSnapshot.length}',
  );

  final localPluginInfos = objectbox.pluginInfoBox.getAll();
  final localPluginByUuid = <String, PluginInfo>{
    for (final item in localPluginInfos)
      if (item.uuid.trim().isNotEmpty) item.uuid.trim(): item,
  };
  final localDeletedUuids = localPluginByUuid.values
      .where((item) => item.isDeleted)
      .map((item) => item.uuid.trim())
      .where((uuid) => uuid.isNotEmpty)
      .toSet();

  final remotePluginInfos = <PluginInfo>[];
  for (final json in pluginInfoJsonList) {
    try {
      final parsed = PluginInfo.fromJson(json);
      final uuid = parsed.uuid.trim();
      if (uuid.isEmpty || parsed.isDeleted) {
        continue;
      }
      remotePluginInfos.add(
        PluginInfo(
          uuid: uuid,
          version: parsed.version,
          originScript: parsed.originScript,
          insertedAt: parsed.insertedAt.toUtc(),
          updatedAt: parsed.updatedAt.toUtc(),
          isEnabled: parsed.isEnabled,
          isDeleted: false,
          deletedAt: null,
          lastLoadSuccess: parsed.lastLoadSuccess,
          lastLoadError: parsed.lastLoadError,
          sortOrder: parsed.sortOrder,
          debug: parsed.debug,
          debugUrl: parsed.debugUrl,
          getInfoJson: parsed.getInfoJson,
        ),
      );
    } catch (e) {
      logger.w('[sync][plugins] 忽略无效插件信息: $e');
    }
  }

  final infoUpserts = <PluginInfo>[];
  var skippedDeletedLocal = 0;
  for (final incoming in remotePluginInfos) {
    final uuid = incoming.uuid.trim();
    if (localDeletedUuids.contains(uuid)) {
      skippedDeletedLocal++;
      continue;
    }
    final existing = localPluginByUuid[uuid];
    if (existing != null &&
        !_shouldApplyIncomingPluginInfo(existing, incoming)) {
      continue;
    }
    final upsert = PluginInfo(
      id: existing?.id ?? 0,
      uuid: uuid,
      version: incoming.version,
      originScript: incoming.originScript,
      insertedAt: existing?.insertedAt ?? incoming.insertedAt,
      updatedAt: incoming.updatedAt,
      isEnabled: incoming.isEnabled,
      isDeleted: false,
      deletedAt: null,
      lastLoadSuccess: incoming.lastLoadSuccess,
      lastLoadError: incoming.lastLoadError,
      sortOrder: incoming.sortOrder ?? existing?.sortOrder,
      debug: incoming.debug,
      debugUrl: incoming.debugUrl,
      getInfoJson: incoming.getInfoJson.isNotEmpty
          ? incoming.getInfoJson
          : (existing?.getInfoJson ?? ''),
    );
    infoUpserts.add(upsert);
    localPluginByUuid[uuid] = upsert;
  }
  if (infoUpserts.isNotEmpty) {
    objectbox.pluginInfoBox.putMany(infoUpserts);
  }

  final blockedConfigNames = <String>{
    for (final uuid in localDeletedUuids)
      ..._buildPluginConfigNameCandidatesForSync(uuid),
  };
  final blockedConfigIds = <int>[];
  final localConfigByName = <String, PluginConfig>{
    for (final item in objectbox.pluginConfigBox.getAll())
      if (item.name.trim().isNotEmpty &&
          !blockedConfigNames.contains(item.name.trim()))
        item.name.trim(): PluginConfig(
          id: item.id,
          name: item.name.trim(),
          config: item.config,
        ),
  };
  for (final item in objectbox.pluginConfigBox.getAll()) {
    final name = item.name.trim();
    if (name.isNotEmpty && blockedConfigNames.contains(name)) {
      blockedConfigIds.add(item.id);
    }
  }
  if (blockedConfigIds.isNotEmpty) {
    objectbox.pluginConfigBox.removeMany(blockedConfigIds);
  }
  var skippedBlockedConfig = 0;
  for (final json in pluginConfigJsonList) {
    try {
      final parsed = PluginConfig.fromJson(json);
      final name = parsed.name.trim();
      if (name.isEmpty) {
        continue;
      }
      if (blockedConfigNames.contains(name)) {
        skippedBlockedConfig++;
        continue;
      }
      final existing = localConfigByName[name];
      localConfigByName[name] = PluginConfig(
        id: existing?.id ?? 0,
        name: name,
        config: parsed.config,
      );
    } catch (e) {
      logger.w('[sync][plugins] 忽略无效插件配置: $e');
    }
  }
  if (localConfigByName.isNotEmpty) {
    objectbox.pluginConfigBox.putMany(localConfigByName.values.toList());
  }
  logger.d(
    '[sync][plugins] apply_remote_db '
    'upsertInfos=${infoUpserts.length} totalLocalInfos=${localPluginByUuid.length} '
    'savedConfigs=${localConfigByName.length} '
    'skippedDeletedLocal=$skippedDeletedLocal skippedBlockedConfig=$skippedBlockedConfig',
  );

  await PluginRegistryService.I.reconcileAfterExternalSync(
    previousSnapshot: previousSnapshot,
  );
}

Future<Map<String, _LocalSettingsBlockMeta>>
_loadLocalSettingsBlockMeta() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_settingsBlockMetaPrefsKey);
  if (raw == null || raw.trim().isEmpty) {
    return <String, _LocalSettingsBlockMeta>{};
  }

  try {
    final json = _toJsonMap(jsonDecode(raw));
    return json.map(
      (key, value) =>
          MapEntry(key, _LocalSettingsBlockMeta.fromJson(_toJsonMap(value))),
    );
  } catch (e) {
    logger.w('[sync][settings] 本地块元数据读取失败，已忽略: $e');
    return <String, _LocalSettingsBlockMeta>{};
  }
}

Future<void> _persistLocalSettingsBlockMeta(
  Map<String, _LocalSettingsBlockMeta> nextMeta,
) async {
  final prefs = await SharedPreferences.getInstance();
  final payload = {
    for (final entry in nextMeta.entries) entry.key: entry.value.toJson(),
  };
  await prefs.setString(_settingsBlockMetaPrefsKey, jsonEncode(payload));
}

Future<void> _updateLocalSettingsSyncTime(
  GlobalSettingState localGlobal, {
  required int syncTime,
  required GlobalSettingCubit? globalSettingCubit,
}) async {
  final merged = localGlobal.copyWith(
    syncSetting: localGlobal.syncSetting.copyWith(settingsSyncTime: syncTime),
  );
  if (globalSettingCubit != null) {
    globalSettingCubit.applySyncedState(merged);
  } else {
    final user = objectbox.userSettingBox.get(1);
    if (user != null) {
      user.globalSetting = merged;
      objectbox.userSettingBox.put(user);
    }
  }
}

Future<void> _uploadSettingsPayload(
  ComicSyncRemoteAdapter adapter, {
  required List<int> payloadBytes,
  required String payloadMd5,
  required int syncTime,
}) async {
  final fileName = ComicSyncCore.buildSettingsDataFileName(syncTime);
  await adapter.uploadRemoteFile(fileName, payloadBytes);
  await adapter.uploadRemoteFile(
    _remoteSettingsMd5Path,
    utf8.encode(payloadMd5),
    contentType: 'text/plain; charset=utf-8',
  );
  logger.d('[sync][settings] uploaded file=$fileName md5=$payloadMd5');
}

Future<void> _cleanupRemoteSettingsFiles(ComicSyncRemoteAdapter adapter) async {
  final allRemote = await adapter.listRemoteDataFiles();

  final legacyFiles = allRemote
      .where(ComicSyncCore.isLegacyRemotePath)
      .toList();
  if (legacyFiles.isNotEmpty) {
    await adapter.deleteRemoteFiles(legacyFiles);
  }

  final syncRootFiles = allRemote.where(ComicSyncCore.isSyncRootPath).toList();
  final settingsFiles = syncRootFiles.where((path) {
    final fileName = ComicSyncCore.extractFileName(path);
    return ComicSyncCore.isSettingsDataFileName(fileName);
  }).toList();
  final sorted = ComicSyncCore.sortSettingsFilesByTimestampDesc(settingsFiles);

  final keep = <String>{
    '${ComicSyncCore.syncRemoteRootName}/${ComicSyncCore.settingsMd5FileName}',
  };
  for (var i = 0; i < sorted.length; i++) {
    if (i < 3) {
      keep.add(ComicSyncCore.normalizeRemotePathNoLeadingSlash(sorted[i]));
    }
  }

  final stale = settingsFiles.where((path) {
    final normalized = ComicSyncCore.normalizeRemotePathNoLeadingSlash(path);
    return !keep.contains(normalized);
  }).toList();
  if (stale.isNotEmpty) {
    await adapter.deleteRemoteFiles(stale);
  }
}

Future<_RemoteSettingsData?> _selectLatestRemoteSettingsData(
  ComicSyncRemoteAdapter adapter,
  List<String> remotePaths,
  String remoteMd5,
) async {
  final sorted = ComicSyncCore.sortSettingsFilesByTimestampDesc(remotePaths);
  if (sorted.isEmpty || remoteMd5.isEmpty) {
    return null;
  }

  for (final path in sorted) {
    try {
      final bytes = await adapter.downloadRemoteFile(path);
      final md5 = ComicSyncCore.calculateMd5(bytes);
      if (md5 == remoteMd5) {
        return _RemoteSettingsData(
          bytes: bytes,
          timestamp:
              ComicSyncCore.extractSettingsTimestampFromRemotePath(path) ?? 0,
        );
      }
    } catch (e) {
      logger.w('远端设置文件读取失败，尝试更旧版本: $path, error: $e');
    }
  }

  return null;
}

int _extractSyncTimeFromPayload(
  Map<String, dynamic> payload, {
  required int fallbackFromFileName,
}) {
  final syncTime = int.tryParse(payload['syncTime']?.toString() ?? '') ?? 0;
  if (syncTime > 0) {
    return syncTime;
  }
  return fallbackFromFileName;
}

Future<String> _downloadRemoteText(
  ComicSyncRemoteAdapter adapter,
  String remotePath, {
  bool returnEmptyIfMissing = false,
}) async {
  final bytes = await _downloadRemoteBytes(
    adapter,
    remotePath,
    returnEmptyIfMissing: returnEmptyIfMissing,
  );
  if (bytes.isEmpty) {
    return '';
  }
  return utf8.decode(bytes).trim();
}

Future<List<int>> _downloadRemoteBytes(
  ComicSyncRemoteAdapter adapter,
  String remotePath, {
  bool returnEmptyIfMissing = false,
}) async {
  try {
    return await adapter.downloadRemoteFile(remotePath);
  } catch (e) {
    if (returnEmptyIfMissing && _isNotFoundError(e)) {
      return const [];
    }
    rethrow;
  }
}

bool _isNotFoundError(Object error) {
  final message = error.toString();
  final lower = message.toLowerCase();
  return message.contains('404') ||
      message.contains('NoSuchKey') ||
      message.contains('NoSuchObject') ||
      message.contains('NotFound') ||
      lower.contains('does not exist') ||
      lower.contains('specified key') ||
      lower.contains('no such key');
}

Map<String, dynamic> _toJsonMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _toJsonMapList(Object? value) {
  final raw = (value as List? ?? const []);
  return raw
      .map((item) {
        if (item is Map<String, dynamic>) {
          return Map<String, dynamic>.from(item);
        }
        if (item is Map) {
          return item.map((key, val) => MapEntry(key.toString(), val));
        }
        return <String, dynamic>{};
      })
      .where((item) => item.isNotEmpty)
      .toList();
}

Map<String, dynamic> _materializeJsonMap(Map<String, dynamic> value) {
  return _toJsonMap(jsonDecode(jsonEncode(value)));
}

String _calculateStructuredMd5(Map<String, dynamic> data) {
  return ComicSyncCore.calculateMd5(utf8.encode(jsonEncode(data)));
}

int _derivePluginBlockTimestamp(
  Map<String, dynamic> pluginData, {
  required int fallback,
}) {
  final pluginInfos = _toJsonMapList(pluginData['pluginInfos']);
  var latest = 0;

  for (final item in pluginInfos) {
    final updatedAt = DateTime.tryParse(item['updatedAt']?.toString() ?? '');
    final insertedAt = DateTime.tryParse(item['insertedAt']?.toString() ?? '');
    final candidate = [
      updatedAt?.toUtc().millisecondsSinceEpoch ?? 0,
      insertedAt?.toUtc().millisecondsSinceEpoch ?? 0,
    ].fold<int>(0, (current, value) => value > current ? value : current);
    if (candidate > latest) {
      latest = candidate;
    }
  }

  return latest > 0 ? latest : fallback;
}

int _pluginBlockCount(_SettingsBlockPayload? block) {
  if (block == null) {
    return 0;
  }
  return _toJsonMapList(block.data['pluginInfos']).length;
}

_SettingsBlockPayload? _mergePluginBlocks(
  _SettingsBlockPayload? localBlock,
  _SettingsBlockPayload? remoteBlock,
) {
  if (localBlock == null) {
    return remoteBlock;
  }
  if (remoteBlock == null) {
    return localBlock;
  }
  if (_sameBlock(localBlock, remoteBlock)) {
    return localBlock;
  }

  final preferRemoteOnConflict = remoteBlock.updatedAt > localBlock.updatedAt;
  final mergedData = _mergePluginBlockData(
    localBlock.data,
    remoteBlock.data,
    preferRemoteOnConflict: preferRemoteOnConflict,
  );
  final mergedMd5 = _calculateStructuredMd5(mergedData);
  if (mergedMd5 == localBlock.contentMd5) {
    return localBlock;
  }
  if (mergedMd5 == remoteBlock.contentMd5) {
    return remoteBlock;
  }

  return _SettingsBlockPayload(
    name: _pluginsBlockName,
    updatedAt: localBlock.updatedAt >= remoteBlock.updatedAt
        ? localBlock.updatedAt
        : remoteBlock.updatedAt,
    data: mergedData,
  );
}

Map<String, dynamic> _mergePluginBlockData(
  Map<String, dynamic> localData,
  Map<String, dynamic> remoteData, {
  required bool preferRemoteOnConflict,
}) {
  final localInfos = _toJsonMapList(localData['pluginInfos'])
      .where((item) {
        final uuid = item['uuid']?.toString().trim() ?? '';
        return uuid.isNotEmpty && item['isDeleted'] != true;
      })
      .map((item) {
        final next = Map<String, dynamic>.from(item);
        next['uuid'] = item['uuid']?.toString().trim() ?? '';
        return next;
      })
      .toList();
  final remoteInfos = _toJsonMapList(remoteData['pluginInfos'])
      .where((item) {
        final uuid = item['uuid']?.toString().trim() ?? '';
        return uuid.isNotEmpty && item['isDeleted'] != true;
      })
      .map((item) {
        final next = Map<String, dynamic>.from(item);
        next['uuid'] = item['uuid']?.toString().trim() ?? '';
        return next;
      })
      .toList();

  final mergedInfoByUuid = <String, Map<String, dynamic>>{
    for (final item in localInfos) item['uuid'] as String: item,
  };
  for (final remote in remoteInfos) {
    final uuid = remote['uuid'] as String;
    final local = mergedInfoByUuid[uuid];
    if (local == null) {
      mergedInfoByUuid[uuid] = remote;
      continue;
    }
    final remoteUpdatedAt = _pluginInfoUpdatedAtMs(remote);
    final localUpdatedAt = _pluginInfoUpdatedAtMs(local);
    if (remoteUpdatedAt > localUpdatedAt ||
        (preferRemoteOnConflict && remoteUpdatedAt == localUpdatedAt)) {
      mergedInfoByUuid[uuid] = remote;
    }
  }

  final localConfigs = _toJsonMapList(localData['pluginConfigs']);
  final remoteConfigs = _toJsonMapList(remoteData['pluginConfigs']);
  final mergedConfigByName = <String, Map<String, dynamic>>{};

  for (final item in localConfigs) {
    final name = item['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      continue;
    }
    final next = Map<String, dynamic>.from(item);
    next['name'] = name;
    mergedConfigByName[name] = next;
  }
  for (final item in remoteConfigs) {
    final name = item['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      continue;
    }
    final next = Map<String, dynamic>.from(item);
    next['name'] = name;
    if (!mergedConfigByName.containsKey(name) || preferRemoteOnConflict) {
      mergedConfigByName[name] = next;
    }
  }

  final mergedInfos = mergedInfoByUuid.values.toList()
    ..sort((a, b) {
      final aKey = '${a['uuid'] ?? ''}:${a['version'] ?? ''}';
      final bKey = '${b['uuid'] ?? ''}:${b['version'] ?? ''}';
      return aKey.compareTo(bKey);
    });
  final mergedConfigs = mergedConfigByName.values.toList()
    ..sort((a, b) {
      final aName = a['name']?.toString() ?? '';
      final bName = b['name']?.toString() ?? '';
      return aName.compareTo(bName);
    });

  return <String, dynamic>{
    'pluginConfigs': mergedConfigs,
    'pluginInfos': mergedInfos,
  };
}

int _pluginInfoUpdatedAtMs(Map<String, dynamic> item) {
  final updatedAt = DateTime.tryParse(item['updatedAt']?.toString() ?? '');
  final insertedAt = DateTime.tryParse(item['insertedAt']?.toString() ?? '');
  final updatedAtMs = updatedAt?.toUtc().millisecondsSinceEpoch ?? 0;
  final insertedAtMs = insertedAt?.toUtc().millisecondsSinceEpoch ?? 0;
  return updatedAtMs > insertedAtMs ? updatedAtMs : insertedAtMs;
}

bool _shouldApplyIncomingPluginInfo(PluginInfo existing, PluginInfo incoming) {
  if (existing.isDeleted) {
    return false;
  }

  final remoteUpdatedAt = incoming.updatedAt.toUtc().millisecondsSinceEpoch;
  final localUpdatedAt = existing.updatedAt.toUtc().millisecondsSinceEpoch;
  if (remoteUpdatedAt > localUpdatedAt) {
    return true;
  }
  if (remoteUpdatedAt < localUpdatedAt) {
    return false;
  }
  return existing.version != incoming.version ||
      existing.originScript != incoming.originScript ||
      existing.isEnabled != incoming.isEnabled ||
      existing.debug != incoming.debug ||
      (existing.debugUrl ?? '') != (incoming.debugUrl ?? '') ||
      existing.lastLoadSuccess != incoming.lastLoadSuccess ||
      (existing.lastLoadError ?? '') != (incoming.lastLoadError ?? '') ||
      existing.sortOrder != incoming.sortOrder;
}

Set<String> _buildPluginConfigNameCandidatesForSync(String uuid) {
  final candidates = <String>{};
  for (final raw in <String>{uuid.trim()}) {
    for (final normalized in _normalizePluginNameCandidatesForSync(raw)) {
      candidates.add(normalized);
      candidates.add('($normalized)');
      final onceRuntime = 'plugin_info_${normalized.replaceAll('-', '_')}';
      candidates.add(onceRuntime);
      candidates.add('($onceRuntime)');
    }
  }
  return candidates.where((item) => item.trim().isNotEmpty).toSet();
}

Set<String> _normalizePluginNameCandidatesForSync(String raw) {
  final names = <String>{};
  var value = raw.trim();
  if (value.isEmpty) {
    return names;
  }
  names.add(value);

  while (value.length >= 2 && value.startsWith('(') && value.endsWith(')')) {
    value = value.substring(1, value.length - 1).trim();
    if (value.isEmpty) {
      break;
    }
    names.add(value);
  }

  return names;
}

_SettingsBlockPayload? _pickPreferredBlock(
  _SettingsBlockPayload? localBlock,
  _SettingsBlockPayload? remoteBlock,
) {
  if (localBlock == null) {
    return remoteBlock;
  }
  if (remoteBlock == null) {
    return localBlock;
  }

  if (localBlock.updatedAt > remoteBlock.updatedAt) {
    return localBlock;
  }
  if (localBlock.updatedAt < remoteBlock.updatedAt) {
    return remoteBlock;
  }

  if (_sameBlock(localBlock, remoteBlock)) {
    return localBlock;
  }

  return localBlock;
}

bool _sameBlock(_SettingsBlockPayload? a, _SettingsBlockPayload? b) {
  if (a == null || b == null) {
    return a == b;
  }
  return a.contentMd5 == b.contentMd5;
}

int _computeSnapshotSyncTime(Map<String, _SettingsBlockPayload> blocks) {
  var maxSyncTime = 0;
  for (final block in blocks.values) {
    if (block.updatedAt > maxSyncTime) {
      maxSyncTime = block.updatedAt;
    }
  }
  return maxSyncTime;
}

int _normalizeTimestamp(int? timestamp, {required int fallback}) {
  if (timestamp != null && timestamp > 0) {
    return timestamp;
  }
  return fallback;
}

String get _remoteSettingsMd5Path =>
    '${ComicSyncCore.syncRemoteRootName}/${ComicSyncCore.settingsMd5FileName}';

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

class _RemoteSettingsData {
  const _RemoteSettingsData({required this.bytes, required this.timestamp});

  final List<int> bytes;
  final int timestamp;
}

@visibleForTesting
Map<String, Map<String, dynamic>> extractSyncableSettingsBlocksForTest(
  GlobalSettingState state,
) => _extractSyncableSettingsBlocks(state);

/// 「块 → 顶层键」那张表（判据用）。
///
/// 判据要断言的正是**这张表本身**：该同步的字段登记了、不该同步的（`homePath`、
/// 开屏密码、本机路径…）一个都没登记 —— 光断言「某个字段能往返」会漏掉
/// 「顺手把 homePath 也带上了」这类误加。
@visibleForTesting
Map<String, List<String>> settingsBlockKeysForTest() => _settingsBlockKeys;

/// 受「同步设置」总开关统辖的全部块名（判据用）。
@visibleForTesting
List<String> syncableSettingsBlockNamesForTest() => _syncableSettingsBlockNames;

/// 布局**出厂值**的块哈希（判据用它构造「本机没动过」这一情形）。
@visibleForTesting
String workspaceFactoryHashForTest() => _workspaceFactoryHash;

/// 布局块 `updatedAt` 的判定（判据用）。
///
/// `previousHash == null` = 本机还没有这一块的 meta（从没同步过）。
@visibleForTesting
int resolveWorkspaceBlockUpdatedAtForTest({
  required String hash,
  required String? previousHash,
  required int previousUpdatedAt,
  required int nowMs,
}) => _resolveWorkspaceBlockUpdatedAt(
  hash: hash,
  previous: previousHash == null
      ? null
      : _LocalSettingsBlockMeta(updatedAt: previousUpdatedAt, hash: previousHash),
  nowMs: nowMs,
);

@visibleForTesting
GlobalSettingState applySyncableBlockDataForTest(
  GlobalSettingState localState,
  Map<String, Map<String, dynamic>> blocksData,
) {
  final blocks = {
    for (final entry in blocksData.entries)
      entry.key: _SettingsBlockPayload(
        name: entry.key,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        data: entry.value,
      ),
  };
  return _applySyncableBlocksToState(localState, blocks);
}
