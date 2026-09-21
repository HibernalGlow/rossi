part of '../sync_service.dart';
// rossi

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
    // 详情页那颗悬浮胶囊的材质。跟着同屏的 `comicInfoInlineReadButton` 走 library 块，
    // 不另立一块：两条都是「详情页怎么摆」的偏好，分开放只会让同步范围更难读。
    'comicInfoRailLiquidGlass',
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
      : _LocalSettingsBlockMeta(
          updatedAt: previousUpdatedAt,
          hash: previousHash,
        ),
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
