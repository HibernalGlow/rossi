# 操作绑定引擎落在本地核心：UI 与功能面复刻 neoview，数据模型与策略照 mImageViewer，外壳可替换

ADR-0009 定了「**模型形状**取 neoview、**实现**参照 mImageViewer」，但没有定**引擎住在哪一层**。
本 ADR 补上这一层：**引擎住 `rossi_local_core`（纯 Rust），不在 Dart/Flutter 层**。
这样将来换 UI 框架（Flutter → Tauri / egui / WASM / CLI）时，绑定表、冲突检测、动作解析、
导入导出**原样可用**，不需要重写一遍。

## 事实：仓库已有一个完全同形的先例

文件管理器（FM）**就是**这个形状，且其头注释把意图写死了：

- `rust/local_core/src/file_manager.rs` —— 「**可迁移的文件管理器状态机**……不依赖 Flutter、egui 或
  任何具体 UI。Rossi 的泳道卡片、桌面边栏以及后续的 Tauri / WASM 外壳都应该只负责把这里的快照
  画出来并转发动作。**上限属于核心状态，而不是 Dart 的布局常量**」（`MAX_FILE_MANAGER_TABS` 等在核心里）。
- `rust/src/api/file_manager.rs` —— 「**这里是 Flutter 之外的唯一状态入口**……Flutter/桌面边栏只收到
  不可变快照并转发用户动作，**因此未来换成 Tauri、egui 或 CLI 时不需要复制一套业务状态机**」。

操作绑定照 FM 的同一条模板办，**不是新发明一种架构**。差别只有一处：绑定引擎多一个
「**输入事件解析器**」（FM 没有），而它同样是纯函数 —— 输入是「归一化输入事件 + 活跃 context 集合」，
输出是「该触发哪个动作 id」，不持有任何 UI 状态。

## 现状：输入设施全在 Dart 层，且是硬编码

| 文件 | 内容 | 问题（对「可换外壳」而言） |
|---|---|---|
| `lib/page/comic_read/method/key.dart` | `handleGlobalKeyEvent`，`isNext` / `isPrev` 两组键写死 | 引擎若留在这里，换外壳等于引擎报废 |
| `lib/page/comic_read/controller/reader_input_controller.dart` | `_onKeyEvent` 写死 `F11`；滚轮/滚轮缩放写死 | 同上，且识别与动作耦合 |
| `lib/widgets/desktop/intent.dart` | 5 个 `Intent`（`EscapeIntent` / `ReaderScrollUp·Down·PrevPage·NextPageIntent`） | **定义了但没接到 `Shortcuts` / `Actions`** —— 预留未用 |
| `lib/page/comic_read/controller/reader_action_controller.dart` | 动作的**实际执行体** | 结构本来就对：它是动作层，**应当留在外壳**（见 Decision 5） |

`docs/v0.1_acceptance.md` §1 判据 E 现在写「E1–E4 用 `flutter test` 覆盖（纯 Dart）」，隐含前提正是
「引擎在 Dart」。本 ADR 改变了这个前提，判据 E 的**测试宿主**随之调整（见 Consequences）。

## Decision

1. **引擎落在 `rossi_local_core`**，新模块（建议目录模块 `src/operation_binding/`：`model` / `registry` /
   `resolve` / `conflict` / `bundle`）。**不依赖 Flutter、egui、wgpu** —— 与 local_core 现有边界一致
   （`lib.rs` 头注释「不做上屏、不认识 wgpu / Flutter」）。

2. **功能面照 neoview 复刻**（这是「UI 与功能复刻 neoview」的落点，全部进 schema）：
   9 类 `descriptor` 联合（`keyboard` / `mouse` / `mouse-gesture` / `wheel` / `touch` / `gamepad` /
   `area`（画面九宫格）/ `radial`（轮盘）/ `command`）；7 个 `context` 带**数值优先级**且 `global` 在
   `shell` / `editor` / `modal` 下**被隔离**；`binding = action + followUpActions + context + enabled +
   ignoreRepeat`；**冲突阻止保存**；绑定包（`format` + `format_version`）。
   **注意区分目标形态与 v0.1 运行时**：目标是 neoview 的全量；v0.1 运行时仍只跑 5 类
   （`keyboard` / `mouse` / `wheel` / `touch` / `area`），手柄 / 轨迹手势 / 轮盘 / 动作序列**只可解析、
   不可编辑**（ADR-0009 §7、判据 E 的「明确不算判据」）。要提前开这些是**改 ADR-0008 与判据 E**，
   不随本次自动放行。

3. **数据模型与策略照 mImageViewer**（这是「后端实现用 mimage 的」的落点，全在 Rust 侧）：
   `KeySlot` **物理键全量枚举** + `ModKind` **区分左右**（`Ctrl` / `Shift` / `Alt` / `RightCtrl` /
   `RightShift` / `RightAlt`）；`Chord { ctrl, shift, alt, key } | Modifier(ModKind)`；
   `ChordList = [Option<Chord>; 3]`（**每动作最多 3 条** + `digit_pair` 这类小键盘配对）；
   `KeyTrigger`（`Press` / `ModifierHold` / `KeyHold`）+ `BindingPolicy`（`FullChord` / `SingleModifier` /
   `SinglePlainKey` / `Reserved` / `NotBindable`）作为键盘录制器的约束；
   绑定包**导入 sanitize + 版本不符仅警告不清仓** + 新字段的**默认值陷阱**处理
   （`gamepad_enabled` 用 `default_*() -> true`，导入旧包不得关掉用户没碰过的通道）。

4. **FRB 薄入口 = `rust/src/api/operation_binding.rs`**，照 `file_manager.rs` 的形状：
   会话 id + **不可变快照** + **动作转发**。导出/导入、冲突、解析全部经这里，Dart 侧**不复制**任何绑定逻辑。

5. **「换外壳也能用」的接缝 = 解析器，不是执行体**。核心拥有
   `resolve(input_event, active_contexts) -> Option<ResolvedAction>`（纯函数，含优先级 + 隔离 + descriptor 相等，
   算法照 neoview 的 `matchingReaderInputBinding`，键模型用 mImageViewer 的）。
   UI 只做三件事：**① 采集事件并归一化**（Flutter 侧 `HardwareKeyboard` / `PointerSignal` / `GestureDetector`
   → `InputEvent`）；**② 告诉核心当前活跃 context 集合**；**③ 把解析出的 `action id` 映射到自己的执行体**
   （Flutter 侧就是 `reader_action_controller.dart`，`intent.dart` 的 `Intent` 可作其本地载体）。
   **解析是框架无关的；执行必然框架绑定** —— 靠**稳定的 action id 契约**，换框架时执行体是**机械重写**，
   而注册表 / 绑定表 / 冲突 / 序列化 / 解析**零改动**。

6. **`KeySlot ⇄ 平台键码` 的映射归外壳**：核心只定义 platform-neutral 的 `KeySlot` 与解析/显示名；
   Flutter 适配器（`LogicalKeyboardKey ⇄ KeySlot`）住 Dart；将来 egui 外壳写它自己那份。核心不引 UI 类型。

7. **持久化由核心拥有**：绑定表存 JSON（同 `format` / `format_version` schema，导出 = 复制该文件），
   读写在核心里，**改绑定不重新编译**即生效（判据 E2 由此成为结构性事实）。

## Considered Options

- **引擎留在 Dart（现状隐含的默认）**：最省事，且 FM 之前的输入设施已在那里。但换 UI 框架时引擎随 Dart 一起报废，
  与「后端实现、可换框架」**直接冲突**；且 E2「非硬编码」只能在 Dart 侧验证，无法证明契约是语言中立的。
- **引擎放 Rust 但另开一条 C++/FFI 专用桥**（见 `docs/frb_and_cpp_bridge_design.md`）：不必要。
  FRB 已是仓内既成的桥，`file_manager.rs` 已验证该形状能承载「会话 + 快照 + 动作」，没有理由再加一层。
- **把动作执行也搬进核心**：**不行**。动作触碰 UI 状态（翻页 / 缩放 / 全屏 / 唤出菜单），强行下沉会把
  UI 状态机拖进 local_core，既违反 local_core 现有边界，也**降低**可替换性（核心反而更难被非 UI 场景复用）。

## Consequences

- **契约语言中立**：`action id` 成为跨层、跨外壳的唯一契约（CONTEXT.md「动作必须由注册表统一声明」由核心强制）。
  E1（id 稳定）与 E2（默认绑定非硬编码）从「靠约定」变成**结构性事实** —— Dart 侧不再有 `isNext` / `isPrev`
  这类键位判断，`key.dart` 与 `reader_input_controller.dart` 的键位识别全部改为「采事件 → 问核心 → 执行」。
- **判据 E 的测试宿主下沉（需同步 `v0.1_acceptance.md` §1）**：
  - E1 / E2 / E3 / E4 从「`flutter test` 纯 Dart」改为 **`cargo test`（`rossi_local_core`）**，
    外加**一条 FRB 往返集成测试**（证明同一份绑定经桥后在 Dart 侧语义不变）。
  - E5 不变（仍与判据 C 同一次测量），链路明确为 **采集 → 核心解析 → 执行**，「经绑定引擎派发」由此可断言。
  - **本次不改 `v0.1_acceptance.md`**（它未被本 ADR 之外的工作触碰，避免与并发写入方冲突）；
    该文件的 §1 判据 E「纯 Dart」一句列为**待办同步项**（一行改动 + 追溯说明）。
- **动作执行体仍在 UI 层**：换外壳时**动作处理器要重写**（机械、可枚举），这是本决策的**已知代价**；
  换来的是引擎其余全部（注册表 / 绑定表 / 优先级 / 冲突 / 序列化 / 解析）零改动。
- **v0.1 实现面从 Dart 侧移到 Rust 侧**：绑定引擎的工作量进入 local_core，`local_core` 的测试与
  变异验证（本仓既有做法）也随之覆盖它。这是「早做比晚做便宜」的第二次体现（第一次见 ADR-0008 的范围扩张）。
- **设置页的「操作绑定」卡片**从核心取**注册表**（动作 id + 显示名 + 分类）来生成选项，
  键位录制器（`KeySlot` 「按下即录入」）在 UI 侧，但产出的 `Chord` 是核心类型 —— 选项清单因此也是框架无关的。
- **风险（未验证）**：`KeySlot` 全键枚举（含 JIS 专用键）在 Flutter `LogicalKeyboardKey` 上的**覆盖完整性**
  未逐键核对；`mouse-gesture`（轨迹序列）与 `radial` 的运行时在 v0.2 若要做，需独立可行性探针
  （与 Gate A 的做法一致：先探针再动手）。
