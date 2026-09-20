# 文件操作与多选一并进 v0.1：删除走跨平台回收站，不搬 `IFileOperation`

**本 ADR 走的是 ADR-0008 定下的「进范围先改 ADR」流程**，与 ADR-0016（视频播放解冻）同一机制。
它加的不是一条纵向链路，而是一个**横切能力**：对用户数据做修改的动作。

## Context

差异核对（`docs/mimageviewer-gap-audit.md` §7.3）把 Rossi 与 mImageViewer 的差距归纳成四块，
第一块的原话是「**写不出去**」：

> `local_core` 生产代码里目前**一处用户路径写操作都没有**（实测：`fs::remove_file|rename|copy|create_dir`
> 只在测试夹具里出现）。

这一条的严重性不在「少几个按钮」，而在**文件管理器这个词的下限**：一个能列目录、
能搜索、能排序、能记住每个目录的视图状态，却**不能改名、不能删除、不能新建**的东西，
不是文件管理器，是一张浏览视图。

上游那台矿搬不动，卡在 ADR-0008 的 B2：

| 事实 | 取证 |
|---|---|
| `delete_worker.rs` 顶部 `use` 只有 `std` | 只看文件头会得出「纯逻辑、可以逐字搬」的**相反结论** |
| 但函数体内有 21 处 Windows API | `IFileOperation`、`IFileOperationProgressSink`、`IShellItem`、`COINIT_*`、`hwnd: Option<isize>` |
| 同族还有两处 | `cut_clipboard.rs`（11 处）、`shell_file_ops.rs`（14 处） |

**只看 `use` 头会把它归类成 T1（原文搬）；扫函数体才知道是 T4（平台等效重写）。**
这与 ADR-0011 回退 ComicRD 时犯的错是同一类：用容易拿到的指标（许可证、依赖数、`use` 头）
代替真正决定代价的那一列（调用面）。

另一件必须先解决的事：**多选是文件操作的前置**。上游 `delete_worker::spawn(paths: Vec<PathBuf>, …)`
原生收多路径，而 Rossi 的文件卡片**没有任何选中集合**。
把两者分开做，只会得到一个「只能删当前光标那一项」的形态。

## Decision

### 1. 落点分三层，来源各不相同

| 模块 | 做什么 | 来源与形态 |
|---|---|---|
| `local_core::file_ops::selection` | 多选的压缩表示与四则运算 | **T3**：逐行翻译 neoview `DirectorySelection.ts` |
| `local_core::file_ops::execute` | 一条变更的落地、逐条结果、批量与取消 | **T4**：搬上游 `delete_worker.rs` 的**形状**，不搬代码 |
| `local_core::file_ops::clipboard` | 两步式剪切/复制 → 粘贴 | **T3**：对齐 neoview `FolderClipboard` + `prepareDirectoryClipboard` 契约 |

多选**与文件操作同一个模块**，因为选中模型的产出（一串路径）就是执行层的输入；
`selection` 的 `generation` 直接取文件管理器的 `generation()` ——
选中是按**列表下标**表达的，下标只在某一份 `entries()` 上有意义。

### 2. 删除的跨平台等效：`trash` crate + `std::fs`

- **回收站** → `trash` crate 5（MIT）。它内部按平台分流：macOS `NSFileManager`、
  Windows `IFileOperation`、Linux Freedesktop 规范。
  **这正是上游那 21 处 Windows API 的等效物，且是跨平台的。**
- **永久删除 / 复制 / 移动 / 改名 / 新建** → `std::fs`，`move` 在 `CrossesDevices`
  时退回复制 + 删除（上游用 `move-file`，做的是同一件事）。

回收站后端抽成 `TrashBackend` trait，不是为了「好测试」而抽：
它是**唯一不能用 `std::fs` 表达**的动作，也就是平台差异唯一的收口点。

### 3. 「能不能撤销删除」是运行时能力，不是常量

`trash` crate 的 `list` / `restore_all` / `purge_all` 只对 Windows 与 Freedesktop 有效
（crate 里 `os_limited` 模块的 `cfg`）—— **macOS 没有程序化恢复**。
因此 `TrashBackend::supports_restore()` 是运行时查询，UI 靠它决定「撤销」出不出现、
以及菜单上那句「移到回收站」后面要不要缀「（无法撤销）」。
把它写成 `cfg!` 常量会在 macOS 上给出一个**承诺了做不到的事**的提示条。

### 4. macOS 上不用 Finder 那条路

`trash` crate 在 macOS 的默认 `DeleteMethod::Finder` 靠 `osascript` 让 Finder 去删，
于是要先拿到「自动化 Finder」的 TCC 授权。实测未授权时被系统拦成权限违例：

```text
execution error: "Finder"遇到一个错误：发生权限违例。(-10004)
```

用户看到的会是「删除失败」，而真正的原因藏在一个他从没听说过的授权里。
改用 `DeleteMethod::NsFileManager`（`trashItemAtURL`）—— crate 自己的对照表写明它
**不需要额外权限**。代价是部分 macOS 版本上 Finder 右键的「放回原处」会消失
（crate 注明这是 macOS 的已知 bug）；但「删不掉」比「少一个右键项」严重得多。

### 5. 契约对齐 neoview，而不是自己发明

`FileMutation` / `FileUndoReceipt` / `FileMutationGuard` / `FileOperationResult` 的字段与取值
逐条对齐 `packages/file-operations/src/types.ts`，`#execute` 的逐分支行为对齐 `platform.ts`：

- **默认冲突策略是 `Fail`**（= 上游 `overwrite: false`，撞名报 `EEXIST`）；
  本 ADR 另加 `Overwrite` 与 `KeepBoth`（顺延成 `名字 (2).ext`）两档，默认不变。
- **两步式剪贴板**，`move` 模式粘完清空、`copy` 模式保留。
- **部分失败逐条报告**：`{index, operation, status, errorCode, error}` +
  聚合 `succeeded / failed / cancelled` + 一句摘要。一条失败后其余标 `cancelled`（上游 `stopOnError: true`）。
- **撤销前必须校验守卫**（`kind/size/mtime/ctime/dev/inode`），变了就报 `ESTALE` ——
  先删后校验等于把「撤销」做成「无条件删除」。
- **撤销日志上限 50 条**（上游 `undoLimit`）。

### 6. 有意的偏离（登记）

| 偏离 | 理由 |
|---|---|
| `ConflictPolicy` 多 `Overwrite` / `KeepBoth` 两档 | 漫画库里「解压到已有目录」「新建同名文件夹」很常见；默认仍是 `Fail` |
| Windows 上 `ctime` 取创建时间、`dev/inode` 恒为 0 | `std` 在 Windows 不暴露 POSIX 的这三个字段。方向是**宁可多允许一次撤销**，也不要因为取不到字段把合法撤销判成 `ESTALE` |
| 批量**串行**执行（上游 `p-map` 并发 4） | 一批操作通常面向同一个目录/同一个卷，四条并发抵不过「部分成功后哪几条成功了」的推理成本 |
| `selection` 的 `explicit` 用 `BTreeMap`（路径序）而非 JS `Map`（插入序） | 唯一受影响处是「找出下标等于锚点的已记录路径」，索引正常唯一，两种序同答案 |
| 复制时的符号链接**按链接复制**（不跟进） | 与上游 `cp` 不开 `dereference` 一致；同时消掉「复制指向自己祖先的链接」的无限递归 |

### 7. 交互层：动作进**右键菜单**，按 MD3 做

用户明确要求「把这些操作放到右键菜单里，并且遵守 MD3 设计规范」，于是交互层也分三层，
与仓库既有习惯同构：

| 层 | 文件 | 判据 |
|---|---|---|
| **有哪些项、哪一项可用、要不要确认、点一下算哪种手势** | `lib/workspace/model/file_manager_entry_menu_spec.dart`（纯 Dart，**零 import**） | `dart run test/workspace/file_manager_entry_menu_check.dart`（145 条） |
| **长什么样、在哪儿弹** | `lib/workspace/widgets/cards/file_manager_entry_context_menu.dart` | 无可执行判据，靠看 |
| **动作怎么落地** | `lib/workspace/method/file_manager_actions.dart`（问参数 / 说结果）+ 卡片里的桥调用（只有它知道会话 id 与忙状态） | 同上 |

#### 7.1 为什么用 `MenuAnchor` 而不是同仓已有的 `showMenu`

同仓的 `shelf_entry_context_menu.dart` 用的是 `showMenu`，它走 **M2** 的 `PopupMenuTheme`
（2dp 圆角、`surface` 底色）。MD3 的菜单面是 `surfaceContainer` + 2dp 高度 + **4dp** 圆角 +
上下各 8dp 内边距，条目 48dp 高、24dp 前置图标、图标与文字间距 12dp。
这些在 `MenuItemButton` 里已是默认值，所以只需给菜单面一份 `md3MenuStyle()`
（收在一个函数里：文件管理器的目录列右键、工具栏菜单以后都要读同一份规格）。

**没有**回头改收藏 / 历史那两个菜单：它们是既成的，换观感不在这次的范围里。

#### 7.2 确认策略：**两个布尔**，与 `flutter-list-entry-context-menu` 技能的唯一偏离

| 布尔 | 含义 | 谁为真 |
|---|---|---|
| `destructive` | 需要**二次确认** | **只有**永久删除 |
| `dangerous` | 用危险色画 | 永久删除 + 移到回收站 |

技能里的规则是「一个布尔同时驱动危险色与确认」，理由是「只上色等于没保护」。
这里把它拆开的依据是：**回收站的保护不是确认框，是撤销通道**。
并成一个布尔只有两种结果 —— 要么「移到回收站」每次都弹一个用户明知能撤销的确认框
（neoview 默认就不弹），要么「永久删除」少了确认。不变式由判据钉着：
`destructive` 为真时 `dangerous` 必须为真（`assert`）。

平台能力（`trashRestoreSupported`）**只影响文案**（「移到回收站」vs「移到回收站（无法撤销）」），
**不影响**要不要确认 —— 否则同一个菜单项在不同平台上语义不同，判据没法写。
（macOS 的回收站仍然由系统废纸篓兜着，用户能自己去捞，所以不弹确认依然是对的。）

#### 7.3 点一下算「打开」还是「选上」：规则是纯函数

单击有三种含义，它们的优先级会打架，所以判断收在 `resolveFileManagerEntryTapGesture` 里：

- **什么都不按** → 打开（保持改造前的行为；顺手清掉选中集合 —— 打开是对**这一个**的动作）；
- **Ctrl / Cmd** → 切换这一项是否选中（`toggleModifier` 由界面层把 `control || meta` 合并，
  两键都认：代价只是「macOS 上按 Ctrl 也能多选」）；
- **Shift** → 从锚点连选（`extend`）；
- **两个一起按 → Shift 赢**：连选需要一个起点，而 toggle 会把起点改掉。

锚点**不在 Dart 记一份**：它的正本在 Rust 的选中模型里，记副本会和「全选 / 反选 /
撤销后清空选中」这些核心侧的状态变化对不上。

#### 7.4 右键时先收敛选中态（`onBeforeOpen` 的由来）

规则取自 neoview：**在选中集合里右键 = 对整批，在集合外右键 = 对这一个**。
后者必须先走一次桥调用把选中态收敛到这一行，否则菜单会以「这 3 项」为主语，
而用户一项都没选过。所以菜单宿主有一个异步的 `onBeforeOpen`，`await` 它之后才 `open()`。

这不会闪一下旧文案：菜单面的第一次构建必然晚于 `open()`，而 `open()` 又晚于状态更新。

#### 7.5 `paste` / `createFolder` 的落点 = **被右键的那个目录**

桥原先只认「当前目录」（`listing.active_path`），而菜单上写的是「粘贴到这一项」
「新建文件夹」——**照原样接起来就是菜单在说谎**。所以两处桥各加一个可选落点：

- `file_ops_paste(id, destination)`：给了路径就粘到那一项里，`None` 仍是当前目录；
- `file_ops_create_directory(id, name, parent)`：同上。

两个都**先确认落点确实是个目录**再往下走：交给 `paste_mutations` 去算的话，
它会老实算出一堆「<文件路径>/名字」形式的落点，然后在复制那一步才失败，
报出来的是「复制失败」而不是「你把它粘到一个文件上了」。

#### 7.6 多选操作条

右键菜单一次只能从一个条目进，**批量动作没有入口**；所以列表上方加一条操作条
（粘贴 / 撤销各只在可用时出现）。它不是常驻工具条，只在有选中时出现。
窄面板下横向滚动而不是换行 —— 换行会把列表往下顶一大截，而用户正看着那一批行。

#### 7.7 总开关：`fileManagerSetting.fileOperations`（默认开）

**这一层第一次具备修改用户磁盘的能力**，按用户的长期约定（「新功能都要有开关、
可随时关闭」）给一个总开关，而不是逐个动作给 —— 那样关到一半是最糟的状态。
关掉之后：没有右键菜单、没有多选、没有操作条，文件浏览器回到「只看不改」。
关掉的瞬间顺手清空选中集合，免得下次打开开关「复活」一批用户早忘了的选中项。

> **两个入口，都是同一个全局设置**（与 `rememberViewState` 一样）：
> 卡片工具栏的「更多」菜单（顺手关的入口，就在你正要删东西的地方）
> 与「设置 → 文件管理器 → **文件操作**」（找得到、说得清的入口）。
> 后者是 `file_manager_setting_page.dart` 里新加的一节，
> i18n 键 `settings.fileManager{SectionFileOps,FileOperations,FileOperationsSubtitle}`。

## Considered Options

- **照搬 `IFileOperation` + `SHFileOperation`**：在 Windows 上最"原生"（进度对话框、
  撤销栈都是系统的）。但它是 B2 明写的平台专有边界，且会把「回收站」这件事变成
  一份只有 1/5 平台能跑的代码。
- **自己写三套 `cfg` 分支的回收站**：macOS 的 `.DS_Store`/Put Back、Windows 的
  `IFileOperation` 标志位、Freedesktop 的 `.trashinfo` 写出各有各的坑，
  重写一遍只会重踩。`trash` 是 MIT、纯 Rust（macOS 侧只有 objc2 三个小依赖）。
- **先把多选做出来，文件操作下一轮**：多选单独存在没有出口 ——
  它唯一的用途就是让批量动作有个作用对象。
- **给删除加「路径白名单」防误删**：把安全建立在「猜用户不该删什么」上。
  真正的保护是**预览 + 确认 + 撤销通道**（回收站 + 撤销日志），已经包含在本 ADR 里。

## Consequences

- **`local_core` 不再是一层只读的核心**。它的模块头注释（「这一层**不**做什么」）与
  `Cargo.toml` 的克制清单都要跟着改：新增依赖 `trash`（MIT，纯 Rust），
  没有引入 C 依赖、没有引入外部二进制，交叉编译面不变。
- **G-30 从「还差的」移进「已具备」**（`docs/mimageviewer-gap-audit.md`），
  但它带进来一条新的常驻状态：选中集合与剪贴板**活在会话里**，不落盘。
  跨重启保留「待粘贴」会让「我以为已经粘好了」变成一个无法验证的猜测。
- **判据形态变了**：文件操作的判据必须**成对**写（正向 + 负例）——
  「文件没了」不是判据，「两边都还是原样」「失败之后第三条还在」
  「撤销被守卫拦住且目标未被破坏」才是。见 §判据。
- 上游 mImageViewer 的 `delete_worker.rs` / `cut_clipboard.rs` / `shell_file_ops.rs`
  三份**保持不搬**，继续留在 vendor 里作为形状参考。

### 显式没做的：G-03 的 crash-safe 事务壳

`mimageviewer-gap-audit.md` 里 G-30 那一行的方案原文是「`trash` crate + 纯 `std::fs`
逐项结果报告，**外面套 G-03 的事务壳**」。本 ADR 只交付了前半。

| 场景 | 本轮的行为 | 要 G-03 才有的行为 |
|---|---|---|
| 批量中途**某一条失败** | 后续标 `cancelled`，已成功的逐条列出，可整批撤销 | 同左 |
| 进程在批量中途**被杀死 / 崩溃** | 停在半路：已落地的留下、未做的不做；**撤销日志随进程一起没了** | 重启后按 journal 自证并回滚 |

理由是 G-03（`book_fs_journal.rs`，forward/rollback 各自从路径 + SHA-256 **自证状态**）
是自己一条独立的 A 档候选，它要解决的是「崩溃后重放」，与「跑完报结果 + 会话内可撤销」
不是同一件事。**不能因为 G-30 落地就把 G-03 划掉。**

## 判据

```bash
cd rust && cargo test -p rossi_local_core       # 多选 / 执行 / 剪贴板 + 文件管理器回归
python script/sync_vendored_modules.py          # 自检：有没有未登记的偏离
dart analyze lib/
dart run test/workspace/file_manager_entry_menu_check.dart
flutter test test/workspace/file_manager_card_test.dart   # 卡片回归护栏（已知 3 红，见下）
```

> **本机跑法（2026-09-20 实测）**：这份判据是**纯 Dart、零 import**，而 `dart run`
> 在本仓会先跑 native asset hook（去编 windcore，几分钟）。只想验这份规格时可以绕开：
> 把两个文件拷进一个空目录、把 `package:zephyr/...` 那条 import 改成相对路径，
> 用独立 Dart SDK 跑即可（`/opt/homebrew/bin/dart`）。另外 sandbox 里 `dart` / `flutter`
> 不在 `PATH` 上（要写全路径），且 hook 找 `rustup` 是**先查 PATH**、再退
> `~/.cargo/bin/rustup` —— 而本机 rustup 在 `/opt/homebrew/bin`，所以跑 `dart run`
> 必须把 `/opt/homebrew/bin` 放进 PATH。
>
> **卡片回归（2026-09-20 实测）**：`flutter test test/workspace/file_manager_card_test.dart`
> = **54 通过 / 3 失败**。3 个失败全在文件树那一组（`_openTree` 里 `pumpAndSettle` 超时），
> 与本 ADR **无关**：卡片改动一行都没碰文件树代码（`git diff HEAD --` 里树相关行增删为空），
> 且同一轮里 51 个含 `pumpAndSettle` 的用例都正常收敛。属**既有红**，另案处理。
>
> **新增桥函数时必做**：卡片那侧的判据桩（`_FileManagerApi`）是 `noSuchMethod` + switch
> 出来的，`default` 分支回的是 `FileManagerSnapshot`。file_ops 那一族返回的是
> `FileOpsSnapshot` / `FileOpsReport` / `bool`，落进 default 会顶成
> `type 'Future<FileManagerSnapshot>' is not a subtype of type 'Future<bool>'` ——
> 报错点指向 `dispose`，真凶却是桩。所以**每次往卡片里加一个新命名空间的桥调用，必须
> 同步给桩加 case**；桩里已加一道兜底，未列出的 `crateApiFileOps*` 会直接
> `UnimplementedError` 报出名字，而不是变成类型不符。

逐条补充（**每条都要负例**）：

| 对象 | 必须有的判据 |
|---|---|
| 多选 | 跨 generation **rebase 后降级为路径集**（区间必须被丢掉）；全选态下 `ranges` 的含义与未全选时相反 |
| 复制 | 撞名 `EEXIST` 且**两边都未被改动**；覆盖不留回执；`KeepBoth` 出 `名字 (2)` |
| 移动 / 改名 | 改名跨目录报 `EXDEV`；移动后源消失、目标内容一致 |
| 删除 | 「回收站 vs 永久删除」**不是同一件事**：前者留回执、后者不往回收站写东西 |
| 撤销 | 目标在中途被改过时报 `ESTALE`**且目标未被破坏** |
| 批量 | 一条失败后其余标 `cancelled`，**后面的条目原样还在**；取消旗子在开头就能挡住整批 |
| 平台 | 真回收站后端要断言「原路径真的消失」，并自己收尾（不留东西在用户回收站里） |
| **菜单** | 十个动作**一个都不能少**；多选时「重命名 / 打开 / 新建」置灰但**必须在场**（隐藏等于让人以为没这功能）；危险组永远在最后 |
| **确认** | 需要二次确认的动作**恰好一个**；`destructive` 为真时 `dangerous` 必须为真 |
| **手势** | 四个按键组合一个不落；「什么都不按」时**只有一种**可以解析成「打开」；Ctrl+Shift 同时按时连选优先 |
| **右键收敛** | 集合内右键不收敛（否则整批只剩一项）、集合外右键必收敛 |
| **卡片回归** | 挂载卡片 + `pumpAndSettle` 正常收敛；`dispose` 时 `file_manager_close` 与 `file_ops_close` **成对**发出（只关前者会留下一份没人再用的选中态与一个还挂着的取消旗子） |
| **桥接桩** | 桩必须覆盖 file_ops 全部桥函数（分别回 `FileOpsSnapshot` / `FileOpsReport` / `bool`）；未覆盖的要 `UnimplementedError` **报出函数名**，不许退化成类型不符的怪错误 |
