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
| radial（轮盘） | ✅ 可解析 | ❌ | 含菜单编辑器，v0.2+ |
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
