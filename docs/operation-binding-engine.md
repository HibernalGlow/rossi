# 操作绑定引擎落地设计（ADR-0015）

本文是 ADR-0015 的**落地设计**：引擎住 `rossi_local_core`（纯 Rust），FRB 薄入口在
`rust/src/api/operation_binding.rs`，UI 只做「采集事件 → 问核心 → 执行动作」。
形状照文件管理器（`local_core/src/file_manager.rs` + `src/api/file_manager.rs`）。

> 词汇以 `CONTEXT.md` §操作绑定 为准（动作 / 绑定 / 输入描述 / 上下文 / 冲突 / 绑定包）。
> 目标形态照 neoview（`Xiranite/packages/nodes/neoview/src/domain/input/`），
> 数据模型与策略照 mImageViewer（`vendor/mimageviewer/src/keymap.rs`）。

## 1. 分层与边界

```text
┌─ UI 外壳（Flutter，将来可换 Tauri / egui / WASM / CLI）─────────────────────────────┐
│  ① 采集 + 归一化：HardwareKeyboard / PointerSignal / GestureDetector → InputEvent    │
│  ② 声明活跃 context：当前在阅读器 / 面板 / 对话框 / 编辑器…（推给核心）              │
│  ③ 执行体：ActionId → reader_action_controller（翻页 / 缩放 / 全屏 / 唤菜单）        │
│  ④ 设置页：从核心取注册表生成选项；键位录制器产出核心的 Chord                        │
└──────────────────────────────────────────────────────────────────────────────────────┘
                ▲ 快照 / 动作 (immutable DTO)          │ InputEvent + contexts
                │                                       ▼
┌─ FRB 薄入口  rust/src/api/operation_binding.rs ─────────────────────────────────────┐
│  会话 id + 不可变快照 + 动作转发（照 file_manager.rs）。Dart 侧不复制任何绑定逻辑。   │
└──────────────────────────────────────────────────────────────────────────────────────┘
                │
                ▼
┌─ 引擎  rossi_local_core::operation_binding（纯 Rust，不依赖 Flutter/egui/wgpu）──────┐
│  model（descriptor / binding / context / chord）  registry（动作表）                 │
│  resolve（事件 → 动作 id，纯函数）                conflict（冲突，阻止保存）         │
│  bundle（format + format_version + sanitize）     store（JSON 持久化，导出=复制）    │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

**边界一句话**：核心拥有「绑定是什么、能不能存、这个输入该触发哪个动作」；
外壳拥有「事件从哪来、界面怎么画、动作具体怎么做」。

## 2. 核心数据模型（Rust 类型草案）

目录模块 `rust/local_core/src/operation_binding/`：`model.rs` / `registry.rs` / `resolve.rs` /
`conflict.rs` / `bundle.rs` / `mod.rs`。

### 2.1 输入描述（9 类，schema 一次做全）

```rust
pub enum Descriptor {
    Keyboard { code: KeySlot, trigger: KeyTrigger, duration_ms: Option<u32>,
               ctrl: bool, alt: bool, shift: bool, meta: bool },
    Mouse    { button: u8, action: MouseAction, duration_ms: Option<u32>, move_tolerance_px: Option<u32> },
    MouseGesture { button: u8, directions: Vec<GestureDir>, trigger: GestureTrigger, .. },
    Wheel    { direction: WheelDir, ctrl: bool, alt: bool, shift: bool, meta: bool },
    Touch    { gesture: TouchGesture, fingers: u8, duration_ms: Option<u32>, .. },
    Gamepad  { button: u16 },
    Area     { area: ViewArea, button: u8, action: MouseAction, .. },
    Radial   { menu_id: String, item_id: String },
    Command  { command: SystemCommand },   // 固定绑定，用户只配置其 followUpActions
}
```

### 2.2 键模型（照 mImageViewer）

```rust
pub enum KeySlot { A, B, /* … A–Z、Num0–9、Numpad*、F1–F24、方向、Home/End/PageUp/Down、 */
                   Space, Enter, Esc, Tab, Backspace, Delete, OpenBracket, /* …标点… */ JisCaret, JisAt }
pub enum ModKind { Ctrl, Shift, Alt, RightCtrl, RightShift, RightAlt }   // 区分左右
pub enum Chord { Key { ctrl: bool, shift: bool, alt: bool, key: KeySlot },
                 Modifier(ModKind) }
pub struct ChordList { chords: [Option<Chord>; 3], len: usize }           // 每动作最多 3 条
pub enum KeyTrigger   { Press, ModifierHold, KeyHold }
pub enum BindingPolicy{ FullChord, SingleModifier, SinglePlainKey, Reserved, NotBindable }
```

**核心只定义 platform-neutral 的 `KeySlot`**；`LogicalKeyboardKey ⇄ KeySlot` 的适配器住外壳（Dart），
将来 egui 外壳写它自己那份。`BindingPolicy` 供键位录制器约束「这个触发方式允许录什么」。

### 2.3 绑定与上下文

```rust
pub struct Binding {
    pub id: String,
    pub action: ActionId,                 // 稳定契约，见 §3
    pub follow_up_actions: Vec<ActionId>, // ≤ 8（neoview 上限）
    pub context: Context,
    pub enabled: bool,
    pub ignore_repeat: bool,
    pub input: Descriptor,
}
pub enum Context { Global, Reader, Video, Panel, Shell, Editor, Modal }   // 7 个
impl Context {
    pub fn priority(self) -> u16 { /* 0 / 100 / 150 / 200 / 250 / 300 / 400 */ }
    pub fn isolates_global(self) -> bool { matches!(self, Shell | Editor | Modal) }
}
```

### 2.4 归一化输入事件（外壳 → 核心）

```rust
pub struct InputEvent {
    pub device: Device,
    pub slot: Option<KeySlot>, pub button: Option<u8>,
    pub direction: Option<Dir>, pub area: Option<ViewArea>,
    pub gesture: Option<TouchGesture>, pub fingers: Option<u8>,
    pub phase: EventPhase,                 // Down / Up / Repeat / Hold
    pub ctrl: bool, pub alt: bool, pub shift: bool, pub meta: bool,
    pub right_ctrl: bool, pub right_shift: bool, pub right_alt: bool,  // 左右修饰键
    pub at: Instant,                       // 供 hold / durationMs 判定
}
```

`ViewArea`（九宫格）与它的**落点→格**映射是**纯函数**（neoview `readerViewAreaAtPoint`），
因此归核心；外壳只上报「落点坐标 + 盒子尺寸」。

## 3. 动作注册表（核心，稳定 id）

`CONTEXT.md` 要求「动作必须由注册表统一声明（id + 显示名 + 分类 + 所属上下文 + 触发方式）」。
注册表在核心，外壳经 FRB 读取以生成设置页选项：

```rust
pub struct ActionDef { pub id: ActionId, pub label: String,
                       pub category: Category, pub contexts: Vec<Context>, pub trigger: Option<KeyTrigger> }
pub enum Category { Navigation, Zoom, View, Radial, File, Video, Upscale, Slideshow, ViewerToggle, Session }
```

id 命名照 neoview（`reader.next-page` / `reader.zoom-in` / `reader.fullscreen` / `file.delete-current` …）。
**v0.1 注册表只需覆盖「运行时 5 类 + 已在用的动作」**；其余动作可在 schema 里留 id 但不接线。

## 4. 解析算法（框架无关，纯函数）

```rust
pub fn resolve(bindings: &[Binding], event: &InputEvent,
               active: &[Context]) -> Option<Resolved>;   // Resolved { action, follow_ups }

pub struct Resolved { pub action: ActionId, pub follow_ups: Vec<ActionId> }
```

规则（**优先级 + 隔离 + descriptor 相等**，算法照 neoview 的 `matchingReaderInputBinding`）：

1. 跳过 `enabled == false` 的绑定。
2. `context == Global` 且 `active` 中含 `Shell | Editor | Modal` → **隔离，跳过**。
3. 否则 `context` 必须在 `active` 里。
4. `descriptor` 与 `event` 相等（键模型用 mImageViewer 的：`KeySlot` + 左右修饰键 + trigger）。
5. 在命中的候选里取 **`priority()` 最大**者；`ignore_repeat` 为真时忽略 `Repeat` 相位。

## 5. 冲突检测（阻止保存）

```rust
pub fn conflicts(bindings: &[Binding]) -> Vec<Conflict>;   // Conflict { key, binding_ids }
```

同 `context` + 同 descriptor 键（`context:descriptor_key`）即为冲突。
**任何写操作（upsert / import）在落盘前先跑一次；有冲突则拒绝并回传冲突双方**（判据 E3：不能只警告）。

## 6. 绑定包（format + format_version）

```jsonc
{ "format": "rossi.operation-binding", "format_version": 1,
  "bindings": [ /* … */ ] }
```

- **导出 = 复制持久化文件**（同一 schema，导出/导入往返一致 ⇒ 判据 E4）。
- **导入 sanitize**：非法 descriptor / 未知 action id 安全丢弃并记 warning。
- **版本不符只警告不清仓**（照 mImageViewer）；**更高版本不崩**（未知字段保留或安全忽略）。
- **默认值陷阱**：结构体新增字段（尤其「启用类」开关）用 `default_*() -> true`，
  以免导入旧包时把用户**没碰过**的通道关掉（mImageViewer 的 `gamepad_enabled` 教训）。

## 7. FRB 接口草案（`rust/src/api/operation_binding.rs`）

照 `file_manager.rs`：会话 id + 快照 + 动作。

```rust
pub fn create() -> u64;
pub fn dispose(session: u64);

pub struct BindingSnapshot { bindings: Vec<BindingDto>, actions: Vec<ActionDto>,
                             conflicts: Vec<ConflictDto>, active_contexts: Vec<ContextDto> }
pub fn snapshot(session: u64) -> BindingSnapshot;

pub fn set_active_contexts(session: u64, contexts: Vec<ContextDto>);
pub fn resolve_input(session: u64, event: InputEventDto) -> Option<ResolvedDto>;

pub fn upsert_binding(session: u64, binding: BindingDto) -> Result<(), Vec<ConflictDto>>;
pub fn remove_binding(session: u64, id: String);
pub fn reset_binding(session: u64, id: String);
pub fn reset_all(session: u64);

pub fn export_bundle(session: u64) -> String;
pub fn import_bundle(session: u64, json: String) -> ImportResultDto;   // { applied: u32, warnings: Vec<String> }
```

Dart 侧对应一个**薄** `OperationBindingController`：持有 session、把 Flutter 事件转 `InputEventDto`、
把 `ResolvedDto.action` 派给 `reader_action_controller.dart`。**不含绑定逻辑**。

## 8. neoview 功能面映射（复刻什么 / 何时开）

| neoview 能力 | schema | v0.1 运行时 | 备注 |
|---|---|---|---|
| keyboard / mouse / wheel | ✅ | ✅ | v0.1 主线 |
| touch / area（九宫格） | ✅ | ✅ | 桌面阅读高频，非有不可 |
| command（系统固定绑定） | ✅ | ✅ | 用户只配 followUpActions |
| mouse-gesture（轨迹序列） | ✅ 可解析 | ❌ 不可编辑 | 需独立可行性探针（v0.2+） |
| gamepad | ✅ 可解析 | ❌ | 同上 |
| radial（轮盘） | ✅ 可解析 | ✅ **已接线**（2026-09-20，见 §12） | 含菜单编辑器 |
| followUpActions（动作序列 ≤ 8） | ✅ 可解析 | ❌ | v0.2+ |
| 多套 profile | ❌ 暂不进 schema | ❌ | 未定 |

**开 v0.1 之外的能力 = 改 ADR-0008 与判据 E，是一次独立决策**，不随 ADR-0015 自动放行。

## 9. 与判据 E 的对应（测试宿主随 ADR-0015 下沉）

| # | 判据 | 宿主（ADR-0015 后） |
|---|---|---|
| E1 | 动作 id 稳定契约 | `cargo test`：注册表 id 唯一；绑定只引用 id |
| E2 | 默认绑定非硬编码 | `cargo test`：改 JSON 配置（不编译）→ `resolve` 结果随之改变；Dart 侧无键位判断（静态检查） |
| E3 | 冲突阻止保存 | `cargo test`：同 context + 同键 → `upsert` 返回 `Err(conflicts)` |
| E4 | 导出/导入往返一致 | `cargo test`：`export → import` 集合相等；高版本包不崩 |
| — | 桥语义不变 | **一条 FRB 往返集成测试**（新增，证明 DTO 过桥后语义一致） |
| E5 | 翻页走真实路径 | 与判据 C 同一次测量；链路 = 采集 → 核心 `resolve` → 执行 |

## 10. 落地清单（文件级）

新增：
- `rust/local_core/src/operation_binding/{mod,model,registry,resolve,conflict,bundle}.rs`
- `rust/src/api/operation_binding.rs`（并在 `rust/src/api/mod.rs` 加 `pub mod operation_binding;`）
- `rust/local_core/tests/operation_binding_*.rs`（对齐判据 E1–E4）

改动（**待办，本次未动**）：
- `lib/page/comic_read/method/key.dart`、`.../reader_input_controller.dart` —— 去掉键位判断，改为「采事件 → 问核心 → 执行」（判据 E2）。
- `lib/widgets/desktop/intent.dart` —— `Intent` 接到 `Shortcuts` / `Actions`，作为 `ActionId → 执行体` 的载体。
- `lib/page/comic_read/controller/reader_action_controller.dart` —— 保持为执行体，改为按 **action id** 分派。
- `docs/v0.1_acceptance.md` §1 判据 E —— 「E1–E4 用 `flutter test`（纯 Dart）」一句改为 `cargo test` + FRB 往返（一行 + 追溯说明）。
- 设置页新增「操作绑定」卡片，选项从核心注册表生成。

> 备注：本仓有第二个写入方（`lib/workspace/**`、`rust/local_core/**` 等在被并发修改）。
> 上述「改动」与新增文件**只 add 自己的路径**，不要 `git add -A`。

## 11. 已落地（2026-09-19）：context 的 Dart adapter 与「阅读器按键优先」

第一块落地不是引擎，而是**修掉一个真问题**，顺手把 context 的适配层立起来。

**问题**：打开阅读设置面板后，左右键失效、翻不动页。两层原因 ——

1. `showModalBottomSheet`（`reader_settings_sheet.dart:26`）推入一条模态路由，
   把主焦点从阅读器子树拿走；而键处理挂在阅读器自己的 `Focus` 上
   （`reader_input_controller.dart`），于是收不到事件。
2. 按键随即落到 `WidgetsApp` 默认快捷键：`arrowLeft/Right/Up/Down` → `DirectionalFocusIntent`
   （`flutter/lib/src/widgets/app.dart:1277`），在面板控件间移焦点 —— 用户看到的就是
   「左右键被设置面板吃掉」。

**修法**（三处 + 一测试）：

| 文件 | 作用 |
|---|---|
| `lib/util/input/reader_input_context.dart`（新） | neoview 的 7 个 context + `priority` / `isolatesGlobal`，**数值逐条对齐** `READER_INPUT_CONTEXT_PRIORITY` / `READER_INPUT_GLOBAL_ISOLATION_CONTEXTS` |
| `lib/util/input/reader_input_bridge.dart`（新） | 登记阅读器的**同一个**按键处理器 + 保存「真实活跃 context 集合」；`dispatch` 只在 `reader` context 活跃时转交 |
| `reader_input_controller.dart` | `_onKeyEvent` 抽出公开入口 `handleKeyEvent`（逻辑仍只有这一处） |
| `comic_read.dart` | 挂载时 `attach`、卸载时 `detach`（留住同一个 tear-off） |
| `breeze_workspace_page.dart` | 工作台那条 `Focus` 加 `onKeyEvent`：**它是模态路由的祖先、默认快捷键的后代**，所以先于 `DirectionalFocusIntent` 被咨询 → 能压过它 |
| `test/util/reader_input_bridge_test.dart`（新） | 钉住门控语义 + 7 个 context 的数值/隔离与 neoview 一致 |

**Dart 只做 adapter**：`_activeContextsFor(state)` 把工作台的真实状态翻译成 context 集合
（阅读器泳道在场 / 尚无泳道激活 → `{reader}`；其它泳道激活 → `{panel}`，阅读器让位）。
优先级、隔离、冲突的**判定**在桥里，将来整体搬进核心。

**一个刻意的映射**：阅读器自己的设置面板**不记成 `modal`** —— 它是阅读器自己的 UI，
不引入与 `reader` 竞争的绑定，于是左右键仍由 `reader` context 解析。
这是 neoview 语义的直接推论：**高优先级 context 只有在自己也绑了同一输入时才赢**，
而「在场」不等于「抢」。真正的对话框若将来也绑了同一输入，才会按 `modal:400 > reader:100` 赢过它。

**唯一豁免**：焦点在可编辑控件里时不抢（方向键在输入框里是光标移动，而文本编辑快捷键
在焦点树上比工作台这条 `Focus` 更靠上）。

**未做**：断言「打开设置面板后按右键真的翻页」的 widget 级回归测试 —— 需要挂起工作台
与一条模态路由、并用假处理器登记进 `ReaderInputBridge`，属可做的下一步（纯 Dart 语义
已由上面的测试覆盖）。

## 12. 已落地（2026-09-20）：轮盘（radial menu）

轮盘条目使用统一动作绑定表；文档继续兼容 neoview 的菜单、分层、槽位与未知字段。
显示与鼠标选择使用 [flutter-pie-menu](https://github.com/rasitayaz/flutter-pie-menu)
（`pie_menu 3.8.3`），不再维护自绘扇区和第二套 UI 命中算法。

**核心**（`rust/local_core/src/operation_binding/radial.rs`）：

- 文档只有**形状与条目身份**：`RadialConfig { enabled, layerCount, activeMenuId, menus,
  radius, innerRadius, variant, startAngle, sweepAngle }`，`RadialMenuDefinition.layers`
  是「每层一组 `RadialMenuItem { id, label, slotIndex, action?, moveToMenuId?, disabled }`」。
  上限照 neoview：≤16 个轮盘、1..3 层、每层 ≤64 格（空格不落文档，`MIN_SLOT_COUNT = 8`）。
- 环带**不是** `(radius-inner)/layers`：第 1 环是 `内半径 → radius`，之后每层往外长
  `SUBMENU_RADIUS_STEP = 60`（`_getBand` 的算术）。
- `slot_layout` 提供条目身份、标签、启用状态和层序；旧 `slot_at` 几何 API 保留兼容，
  当前 Flutter 轮盘由 `pie_menu` 统一完成布局、悬停和指针选择。
- **一处刻意不照抄**：neoview 的 `_getSlotAtPoint` 把偏移用 `normalizeAngle` 折到
  `[-180,180)`，于是从起始角逆时针那一半算出负索引、被夹回第 0 格 —— 半个轮盘点不准。
  这里按 `[0,360)` 算，「超出扫过角不算命中」那一条语义保持不变。

**接缝**：条目「干什么」仍然是绑定表里的一条 `device: radial` 绑定，由
`operation_binding_resolve` 与键盘、点击同一个解析器回答。neoview 自己也是这个形状
（它把条目上遗留的 `action` 从编辑器里剥掉、物化成绑定行），所以：

- 轮盘不需要同样的判定第二遍，`followUpActions` 与冲突检测自动可用；
- 出厂预设里 12 个槽位 + 两条唤出绑定（右键按下、`Enter` → `radial.open-default`），
  全部由 `cargo test` 钉住「绑的动作必须在注册表里且 `implemented`」；
- 形状变了要剪枝：`radial_prune_bindings` 删掉指向已不存在条目的绑定。
  但**层数只影响显示**，调小层数不删用户数据。

**外壳**：`lib/widgets/radial/reader_ray_menu_adapter.dart` 把本仓的
`RadialMenuDefinition` 映射成 `packages/flutter_ray_menu` 的条目模型（id / 标签 / 槽号 /
启用），供阅读浮层与设置页交互预览共用。多层同心环一次全部显示，半径按可用空间缩放、
中心限制在画布内；左右键在格间移动、确认键按绑定表解析、`Esc` 取消，`moveToMenuId`
切换轮盘、空槽不进运行菜单。停用与空槽不进入运行菜单，设置页用可点击的槽位列表编辑。
`RayMenuGeometry` 是值语义（有 `==`）—— 宿主在 `build` 里现造一份也不会被当成
「形状变了」，否则每次重建都会清掉当前高亮。

**进行中的指针**：Flutter 对进行中的指针复用按下时的命中路径，所以「按下即开」的
浮层拿不到这根指针后续的 move/up/cancel。两条路都接着，且只确认一次：
阅读器（`ReaderRadialMenu.forwardPointer`）把唤出那次的 move/up/cancel 转交进浮层
（它本来就在那条命中路径上）；组件自己也用 `openingPointer` 注册全局路由，但那要在
浮层挂载之后才生效 —— 按下与抬起挨得极近时会漏。浮层对同一根指针只确认第一个抬起
（`RayMenuState._confirmed`），两条路都送到也不会把动作执行两遍。
手感照 neoview：按住拖动高亮跟随、**在某一格上松手就执行那一格**、松在中心空洞里 =
取消、按下就松（没动过）不执行也不关、**轮盘开着时再按一次右键 = 关掉（且不执行指针下
那一格）**。阅读器同时取消这次手势的其他绑定，避免松手再触发翻页。

**配置兼容**：保留旧 `variant` / `sweepAngle` 等字段用于往返导入导出；
`bubble` 之外当前外观固定为扇区，半径按可用空间缩放、中心限制在画布内；
屏幕阅读器模式提供动作列表。
编辑器自身提供透明 `Material`，可直接嵌入设置宿主，避免开关报 `No Material widget found`。

**验证**：`packages/flutter_ray_menu/test/ray_menu_pointer_test.dart` 覆盖指针链的
全部口径（拖动松手即执行 / 中心空洞取消 / 按下即松不关 / 再次点击执行 / 再次右键关掉 /
两条路都送只确认一次），三种来路各跑一遍且**不依赖原生库**（这个包能单独跑测试，
正是独立成包的理由）；`radial_menu_binding_test.dart` 覆盖右键拖放、顺手点击、取消、
再次右键退出、轮盘跳转及可改绑的键盘确认；`radial_binding_editor_test.dart`
覆盖无 Material 宿主、开关、槽位选择及交互预览。

## 13. 完整操作绑定编辑器（2026-09）

设置页按 Neo 的 `InputBindingsSettingsCard` / `BindingActionSequenceEditor`
补齐动作中心编辑：桌面使用独立滚动的动作列表与绑定详情，窄窗口使用 MD3
「动作列表 / 绑定详情」页签。默认进入翻页分类；用图标胶囊切换翻页、画面、视频、
界面、轮盘或全部动作，视频再分播放、声音、画面与字幕。分组仅属于展示层，不改核心
category。每个动作带语义图标，最多展示两枚紧凑输入标签，其余收为 +N；悬停或辅助
功能读取完整输入、上下文与停用状态。搜索跨分类查动作或按键，筛选菜单支持已绑定和
上下文筛选。页签切换保留滚动位置，恢复默认后返回动作列表。
视觉遵循 Material Design 3：SearchBar、圆角 ChoiceChip、DropdownMenu 与色调表面层级，
继续使用应用当前主题的 ColorScheme。

绑定默认显示单行摘要，一次仅展开一条，新增条目自动展开；复制到上下文收进菜单。
每条绑定可以展开、启停、删除、修改上下文、忽略重复输入，并设置最多七个后续动作
（连同主动作共八步，支持调整顺序）。复制到其他上下文会生成独立 id，并完整保留
输入、开关和动作序列。键盘、鼠标、鼠标轨迹、滚轮、触控和九宫格都有专用表单；
键盘 / 鼠标 / 轨迹 / 滚轮 / 触控可在隔离的录制区域采集。轮盘与系统命令的输入标识
继续由对应入口管理，避免编辑器制造失去目标的槽位。

修改经过 220 ms 防抖后自动校验和保存；同上下文输入冲突会显示在具体绑定上，
工作副本保留，运行时继续使用最后一份合法配置。解除冲突后自动保存。
编辑器保持稳定的 Widget 标识，添加绑定导致冲突提示出现或消失时，不重建编辑器，
保留选中的动作、详情页签、输入焦点和滚动位置。
导入也走同一条校验路径。离开时仍有未保存草稿，会先尝试保存，再提供放弃草稿确认。

运行时通过 `operation_binding_resolve_binding` 获取核心选中的完整行，执行主动作及
后续动作，并处理 `ignoreRepeat`。长按定时器读取该行的 `durationMs` 和
`moveTolerancePx`；指针取消和阅读器销毁会取消定时器。九宫格坐标由核心的
`reader_view_area_at_point` 计算，经 FRB 暴露，Dart 不重写几何规则。
鼠标、触控的采集与动作派发均使用同一解析器；轮盘选项也执行完整动作序列。

滚轮的上下文取命中的阅读区（`reader`，当前页为视频时加 `video`），不沿用键盘桥
上次留下的 `panel` 上下文，也不改写键盘焦点。绑定表启用时未匹配的滚轮交回原生
滚动 / 缩放，不再回退到旧翻页规则；停用或删除绑定后不会继续偷偷翻页。
`test/comic_read/reader_wheel_binding_test.dart` 用真实阅读器与滚动控件覆盖面板切换、
上下滚轮、条漫、Ctrl 修饰键、停用和未绑定事件。
`test/comic_read/reader_wheel_direction_test.dart` 再把方向这一维钉住：PageView 按
`isReverseRowReadMode` 反转（左开时下一页真的在左边），出厂滚轮行在右开 / 左开、
有无动画四种组合下都必须是「下滚前进、上滚退回」，而旧口径的空间行仍随方向翻转。

平台边界：手柄可编辑按钮编号、导入导出，但当前 Flutter 外壳尚无手柄事件接入，
表单会直接说明。动作是否已有执行体仍以核心注册表的 `implemented` 为准。
上下文表示应用当前真实的输入环境，不会仅因为创建了绑定就激活对应面板或视频。

验证入口：`test/operation_binding/` 覆盖表单、自动保存 / 冲突、录制组合键、窄屏布局、
指针手势 / 长按 / 取消、动作序列。核心的 `operation_binding` 测试覆盖上下文隔离、
九宫格、冲突、导入参数和八步上限。

## 14. Neo 默认配置

默认配置来自 Xiranite 的 `ReaderInputBindings.ts` 中
`DEFAULT_READER_INPUT_BINDINGS`，九宫格、滚轮、键盘、鼠标共 35 条原样保留
id、上下文与空白区域，数据存于核心 `operation_binding/neo_defaults.json`。
轮盘槽位继续匹配 Rossi 的默认轮盘文档。首次初始化和「恢复默认」统一使用
`operation_binding_factory_preset`，不再拼接旧键盘和左右手三分区表。

**一处有意的偏离**：滚轮那两行的动作换成了语义族（下滚=下一页、上滚=上一页，
id 仍是上游的 `legacy-reader-page-*-global-2/3`）。这四类输入里只有滚轮没有左右这根轴，
把它解释成「向左/向右翻页」是外壳替用户猜的 —— 一换挡，同一只手的手势在左开/右开下
分别是前进和退回。空间族照旧绑在 A/D、方向键与九宫格上，那些输入本身就有左右。
升级走 `operation_binding_upgrade_defaults`：自定义表里**只有还留着旧口径（空间动作）的
出厂滚轮行**会被换掉，用户改绑过的滚轮行与其余各行原样保留。

| 输入 | 默认动作 |
| --- | --- |
| A / 左方向键、左中格 | 向左翻页 |
| D / 右方向键、右中 / 左下 / 右下格 | 向右翻页 |
| 滚轮下滚 / 上滚 | 下一页 / 上一页（不随左右开翻转） |
| W / 上方向键、上中格 | 上一本书 |
| S / 下方向键、下中格 | 下一本书 |
| = / - / 0 | 放大 / 缩小 / 重置视图 |
| F11 / L / R | 全屏 / 切换书库 / 切换阅读方向 |
| 鼠标右键按下 / Enter | 打开轮盘；轮盘打开后 Enter 确认 |
| Space | 确认轮盘选项 |

左上、右上、正中格在阅读器默认不绑定；视频上下文为中排三格设置
后退、播放暂停、前进。视频快捷键也保留 Neo 的上下文定义。
区域单击等待 Flutter 手势竞争结果，视频自身的点击控件不会与外层区域重复触发。
轮盘打开时主动获取键盘焦点，关闭后恢复阅读器焦点，确认键按绑定表解析。
空白格不再回退到旧三分区逻辑。旧版翻页键（如 PageDown、Home、小键盘）不额外
加入 Neo 默认表，仍可通过编辑器自行绑定。

默认表中的「上一本书 / 下一本书」已经接入本地 Reader：打开时保存穿透游标与目录
排序，切换时沿 Neo 的分支遍历继续寻找书籍，完成后替换当前阅读目标。单张图片仍
视为页而不会跨书切换；到达边界时给出提示。「切换书库」仍是待接入动作。

启动时仅自动升级完整、未改动的旧默认输入表。改键、禁用、删行、追加动作、
额外字段或主动清空都视为自定义，不覆盖；轮盘行原始 JSON、轮盘文档及运行时
总开关独立保留。升级可重复执行而不反复写入。自定义表通过设置页「恢复默认」
确认后切换到 Neo 默认配置。
