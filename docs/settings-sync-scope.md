# 设置与配置的云同步范围

> 对应代码：`lib/network/sync/sync_service.dart`（块表与合并）、
> `lib/network/sync/workspace_sync_codec.dart`（布局块编解码）、
> `lib/workspace/service/workspace_layout_bridge.dart`（布局落点）。
>
> 漫画数据（收藏 / 历史 / 文件夹 / 链接）那条链路不在本文 —— 见 `docs/sync_logic.md`。

## 1. 一句话口径

**同步的是「用户偏好」，不同步的是「这一秒的画面」与「这一台机器的事实」。**

这条线决定了后面每一个字段的去留，也是判断一个新字段该不该进块时唯一要问的问题。

## 2. 同步块一览

设置类的载荷是 `blocks`：一个块名 → `{updatedAt, data}` 的映射。
每个块**独立**做 Last-Write-Wins（比 `updatedAt`，谁新用谁）——比字段级合并好解释，
也避免了「两个字段来自两台设备」的中间态。

| 块 | 内容 | 落点 |
|----|------|------|
| `appearance` | 主题（dynamicColor / themeMode / AMOLED / seedColor / tweakcn）、语言与地区、开屏页、简繁转换 | `GlobalSettingState` 顶层字段 |
| `library` | 屏蔽词、图源选择、下载（并发 / 延时 / 重试 / 元数据）、追更与收藏联动、书架设置、**漫画卡片设置**、发现页标签条、**收藏 tag（含别名）** | 同上 |
| `reader` | 整个 `readSetting`（阅读模式、翻页、预载、双页、E-Ink、进度条、悬停揭示、**顶栏材质与蒙层不透明度**…） | `readSetting` 子对象 |
| `shell` | 启动落点（`startWithWorkspace`）、Impeller 强制、Android 保活 / 返回键退出、**桌面端透明标题栏** | 顶层字段 |
| `toast` | 提示条（位置 / 时长 / 尺寸 / 透明度 / 玻璃）与切换提示 | 顶层字段 |
| `fileManager` | 文件管理器卡片：主页键、启动落主页、记住视图状态、**写操作总开关** | `fileManagerSetting` 子对象（**不含 `homePath`**） |
| `operationBinding` | 操作绑定表、轮盘形状、绑定总开关（ADR-0015） | `operationBindingSetting` 子对象 |
| `workspace` | 工作台布局：呈现模式、泳道顺序 / 宽度 / 折叠 / 面板操作栏、**面板与卡片记账**（谁在哪个面板、次序、可见、展开）、每条泳道激活的面板、交互延时与唤出区 | `workspace_layout.json`（**唯一**数据源不在 `GlobalSettingState` 里的块） |
| `plugins` | 插件信息与插件配置（独立开关 `syncPlugins`） | ObjectBox + 插件注册表 |

`syncSetting.syncSettings` 统辖前八块；`syncSetting.syncPlugins` 单独管插件。

### 2.1 三份「唯一真相」

这三个东西从前各写各的，是这一片最容易分叉的地方：

1. **块 → 顶层键**：`_settingsBlockKeys`。抽块（上传）与应用（下载）读同一张表。
   想同步一个新字段，只在表里加一个键。从前是两份手工列表，漏改一边的表现是
   「上传带上去了、下载回来却不生效」，而两边分开看都自洽。
2. **本机事实名单**：`_blockNestedKeyExclusions`（子对象内部的例外）与
   `_applySyncableBlocksToState` 里那段 `copyWith`（整字段的例外）。
3. **布局的取与放**：`WorkspaceSyncCodec`（纯函数，可 `dart run` 判据）+ `WorkspaceLayoutBridge`。

### 2.2 `reader` 块的载荷形状**冻结**

老版本直接拿整个 `readSetting` 对象当块数据（不是 `{'readSetting': {...}}`），
旧客户端下载时执行的是 `json['readSetting'] = <块数据>`。
把它「顺手统一」成顶层键映射，老客户端会把外层对象整个当成 `ReadSettingState`
—— **所有阅读设置静默读成默认值，且不报错**。所以它单独一条路，不并入块表。

## 3. 显式不同步的清单

每一条都写清理由，因为这些「不像偏好」的判断下一个人未必同意 ——
真要改的话，改的是这里，不是顺手加个键。

| 字段 / 数据 | 理由 |
|-------------|------|
| `customExportPath`、`fileManagerSetting.homePath` | 本机绝对路径。对方机器上不存在，同步过去只会得到「点了没反应」 |
| `windowWidth/Height/X/Y` | 窗口几何绑定本机屏幕尺寸与摆放 |
| `socks5ProxyEnabled`、`socks5Proxy`、`proxySetting` | 代理绑定网络环境（家里 / 公司）。同步过去会让另一台设备走一条连不通的代理而**上不了网** —— 「少同步一项」比「沉默地断网」好得多 |
| `appLockSetting`（开屏密码 / PIN） | 安全 |
| `favoriteArtistSetting` | 本地私有偏好（用户明确要求不出本机）。**与 `favoriteTagSetting` 相对**：tag 名单（连同别名）是跨端偏好，走 `library` 块，换设备要继续用同一份标签集 |
| `cacheSetting`、`needCleanCache` | 缓存是本机的 |
| `enableMemoryDebug`、`blockRustHttpRequests`、`logAddress`、`showLayoutOverflowStripes` | 调试开关（最后一条是「黄黑溢出条纹画不画」：本机的调试观感，不是跨端偏好） |
| `syncSetting` 自身 | 否则会把「对方的 WebDAV 地址与凭据」写到自己头上，两台设备互相顶 |
| `themeInitState`、`compatibleVersion` | 内部记账，不是偏好 |
| 实时滚动偏移、瞬态边缘揭示、当前在读的那一本 | 见 `WorkspaceLayoutSnapshot` 的「什么刻意不进」 |
| `workspace` 块里的 `activeLaneId`、四个 `edge*Open` | 同步它等于「B 机一启动，抽屉自己全拉开了 / 交互跳到别的泳道」 |
| 阅读位置 / 视频播放进度 | 属**阅读历史**，不是布局偏好；漫画那边的历史同步已覆盖 |
| 字体路径（`font_profile`）、超分引擎与模型 revision（`real_sr_settings`） | 各自独立键值存储，且**平台专属**：字体路径是本机绝对路径，`realsr_apple_engine` 只在 iOS/macOS 有意义，`realsr_mimage_revision_*` 是模型缓存版本号。要纳入得先给它们各自定语义，不是「搬过去就行」 |

## 4. `workspace` 块的三个特殊之处

### 4.1 数据源不在 `GlobalSettingState`

布局的真相是磁盘上的 `workspace_layout.json`（工作台在场时是活的 cubit）。
所以它**不参与** `_applySyncableBlocksToState` 那次「把块平铺回状态」，
而是自己走读文件 / 改写文件：`WorkspaceSyncCodec.decode(data, base: 本机那份)`
→ `WorkspaceLayoutBridge.apply`。

`decode` 的方向是「拿云端覆盖本机」而不是「从零构造」，于是本机独有的字段
（`activeLaneId`、四个抽屉开关）天然存活 —— 但**四个抽屉开关必须显式写回**：
`WorkspaceLayoutConfig.fromJson` 对缺失项一律取 `false`，而云端不带这四个键，
不写回就是「每同步一次，四个抽屉全被合上」。

### 4.2 本机是出厂值时，`updatedAt` 写 0

其余块第一次同步时，本地块的时间戳取「现在」，于是**本机说了算**。
布局不能照抄这条：一台新装设备、或者一台从没打开过工作台的手机，手上那份布局
**就是出厂值**；给它现在的时间戳，它就会在一轮自动同步里把云端那套精心摆好的
泳道 / 面板 / 卡片冲掉，而用户事后无从解释（他什么都没动过）。

所以 `_resolveWorkspaceBlockUpdatedAt` 多了一条：

- 本机没有这一块的 meta（从没同步过它）+ 本机那份**等于出厂值** ⇒ `updatedAt = 0`
  （谁都比它大 ⇒ 云端赢）；
- 本机没有 meta + 本机那份与出厂**不同**（先摆好布局、后打开同步开关）⇒ 现在（本机赢）；
- 有 meta 且内容哈希没变 ⇒ 沿用原来的时间（**不能**让它退回「现在」，
  否则这台设备永远赢、另一台的修改永远进不来）。

还有一条与时间戳无关、但同样重要的：**读不到布局时整块不带**。
`WorkspaceLayoutBridge.readIfAvailable` 读不到就返回 `null`（而不是兜出厂值），
于是「本机还没存过布局」与「拿不到数据目录 / 读盘失败」都表现为「这块不存在」。
用 `read()` 那个兜底会把出厂值当成本机布局传上去 —— 一次读盘失败就冲掉对方
设备上真正的那套布局，而用户看不到任何提示。顺带的好处：新装设备第一次同步
就直接采纳云端那套，而不是先上传一份出厂值。

> **遗留**：其余几块仍是老口径（第一次同步 = 本机赢）。在新装设备上打开同步开关，
> 会用本机的默认值覆盖云端那套配置。这是既有行为，未在本轮改动
> —— 改动它等于改已发布块的语义，需要单独一轮。

### 4.3 工作台在场时必须改活的 cubit

直接写盘会被 `WorkspaceLayoutPersistence` 的去抖落盘覆盖回去，
现象是「同步说明明成功了，界面纹丝不动，一秒后连文件也回去了」。
这条收在 `WorkspaceLayoutBridge.apply`（与「设置 → 布局」同一个口子）。

## 5. 判据

```bash
# 布局块编解码（纯 Dart，不依赖 flutter_tester / 文件系统）
dart run test/network/sync/workspace_sync_codec_check.dart

# 块表范围、homePath 排除、操作绑定往返、布局时间戳判定
env -u HTTP_PROXY -u HTTPS_PROXY flutter test test/network/sync/settings_sync_block_test.dart
```

判据刻意分两层：能抽成纯函数的一律抽走（布局编解码、时间戳判定），
因为这两处错了**都不会报错**，只会「东西没同步过去」或「东西被同步没了」。

## 6. 加一个新字段的清单

1. 问「这是偏好还是这一台机器的事实」。是后者 ⇒ 进第 3 节那张表，到此为止。
2. 是偏好 ⇒ 在 `_settingsBlockKeys` 对应块里加一个**顶层键**
   （子对象内部要剔掉某项，额外登记 `_blockNestedKeyExclusions`）。
3. 若这个字段还住在别处（另一个文件 / 另一个键值存储），先想清楚它的
   「缺失 / 坏值」各自退化成什么，再照 `WorkspaceSyncCodec` 的样子写一层编解码。
4. 在 `test/network/sync/` 里补两条判据：**该带的带走了**、**不该带的没带**。
