# 操作绑定：目标形态取 neoview，实现参照 mImageViewer，v0.1 只跑输入子集

v0.1 新增一项范围：**操作绑定体系**（可自定义的键位 / 鼠标 / 滚轮 / 触屏到「动作」的映射）。
目标形态以 neoview 为准（高自定义），实现方式参照 mImageViewer 的 `keymap`（它已实现一部分）。

## 事实：现状是硬编码的，两个参考各实现了一半

**Rossi 现有输入设施（4 个文件）**：

| 文件 | 内容 | 问题 |
|---|---|---|
| `lib/page/comic_read/method/key.dart` | `handleGlobalKeyEvent`，硬编码 `isNext` / `isPrev` 两组键 | 键位写死在代码里，改手感必须改代码、重新编译 |
| `lib/page/comic_read/controller/reader_input_controller.dart` | `_onKeyEvent` 里写死 `F11`；滚轮翻页写死；Ctrl 缩放写死 | 同上，且动作与识别逻辑耦合 |
| `lib/widgets/desktop/intent.dart` | 定义了 5 个 `Intent` | **定义了但没接到 `Shortcuts` / `Actions`**，等于预留未用 |
| `lib/page/comic_read/controller/reader_action_controller.dart` | 动作的实际执行体 | 这是唯一结构正确的部分：动作层已存在 |

**neoview 的模型**（`packages/nodes/neoview/src/domain/input/`）：

- `ReaderInputDescriptor` 是 **9 元联合**：`keyboard` / `mouse` / `mouse-gesture` / `wheel` / `touch` /
  `gamepad` / `area`（画面九宫格）/ `radial`（轮盘）/ `command`。
- `ReaderInputBinding { id, action, followUpActions[]（最多 7 个）, context, enabled, ignoreRepeat, input }`
  —— **一个绑定可以触发一串动作**。
- **7 个 context 带明确优先级**：`global:0 < reader:100 < video:150 < panel:200 < shell:250 < editor:300 < modal:400`，
  且 `global` 在 `shell/editor/modal` 下被**隔离**（不生效）。
- **冲突检测 `readerInputConflicts` 阻止保存**（同 context + 同输入键即冲突，标红且不自动保存）。
- 持久化在 Xiranite 主配置的 TOML `[nodes.neoview.bindings]`。
- 另有轮盘菜单编辑器（最多 16 菜单 / 3 层）与手势运行时（`@use-gesture/react`）。

**mImageViewer 的实现**（`src/keymap.rs`，>1500 行；另 `operation_customize_share.rs` 约 500 行 + 测试）：

- **键盘优先**。一个绑定是 `Chord { ctrl: bool, shift: bool, alt: bool, key: KeyName }`，
  或纯修饰键 `Chord::Modifier(ModKind)`。
- `ChordList` = `[Option<Chord>; 3]` —— **每个动作最多 3 条绑定**（有 `digit_pair` 这类「主键 + 小键盘」辅助构造）。
- **12 个 `KeyContext`**：`Global / Grid / FsCommon / Rating / FsImage / FsVideo / Erase / Conceal / Crop / SnsSplit / Text / LocalAdjust`。
- `KeyTrigger` = `Press / ModifierHold / KeyHold`；`BindingPolicy` = `FullChord / SingleModifier / SinglePlainKey / Reserved / NotBindable`。
- `ModKind` **区分左右**：`Ctrl / Shift / Alt / RightCtrl / RightShift / RightAlt` —— neoview 没有这个粒度。
- `KeySlot` 是**物理键全量枚举**（A–Z、0–9、小键盘、F1–F24、方向键、标点、JIS 专用键），
  并有 `to_egui` / `from_egui` / `to_vk` / `from_win32` 四套映射。
- 鼠标不走 `keymap.rs`，走 `ring_shortcut.rs`；手柄走 `gamepad.rs`。**这三者是分开的**。
- `OperationCustomizeBundle`（JSON）：`format = "mimageviewer.operation-customize"`、`format_version = 1`，
  导出 **5 组**（`keymap` / `ring_shortcuts` / `menu_layout` / `context_menu_layout` / `gamepad_enabled`），
  导入有 sanitize、版本不符时**警告但仍尽力导入**、以及一个刻意的默认值陷阱处理
  （`gamepad_enabled` 用 `default_gamepad_enabled() -> true`，否则导入旧包会把用户没碰过的手柄关掉），
  另有 diff 计算（`key_changes` / `ring_change_count` / `menu_change_count`）。

→ **结论：neoview 是超集，mImageViewer 是键盘子集的成熟实现。** 「继承 neoview 的高自定义程度」在这两个事实下是可执行的。

## Decision

1. **模型形状取 neoview，技术栈不取**。采用 `descriptor 联合 + context 优先级 + 冲突阻止保存 + 可导出包` 这套形状；
   不引入它的 `react-hotkeys-hook` / `@use-gesture/react`（Flutter 侧不存在对应物，那不是「拼装」而是重写 web 事件模型）。

2. **数据模型一次做全，运行时按子集实现**。descriptor 的 schema 从第一天就覆盖 9 类设备，
   但 v0.1 的运行时只实现 **5 类**：`keyboard` / `mouse` / `wheel` / `touch` / `area`。
   理由：**schema 是迁移成本最高的部分**——用户一旦存了配置，改 schema 就要写迁移；
   而运行时处理器可以逐个补，不需要动已存的数据。这条是本次决策里最省钱的一条。

3. **context 优先级照抄 neoview 的形状**（数值可调，层级不可少）。这是「高自定义」真正成立的前提：
   没有优先级与隔离，绑定越多越互相打架，用户会退回到「默认别动」。

4. **冲突检测阻止保存**，只警告不阻止等于把问题推给用户。

5. **持久化与分享用 JSON + `format` 标识 + `format_version`**，形态照 mImageViewer 的 bundle。
   理由：它有实证（含版本兼容与默认值陷阱的处理），且**「高自定义」如果没有导出/导入就不可迁移、不可恢复**——
   换机、重装、多设备都会变成手工重配。

6. **替换现有硬编码**：`key.dart` 与 `reader_input_controller.dart` 里的键位判断全部改为注册表驱动；
   `reader_action_controller.dart` 保持为动作执行层（它的结构本来就对）；
   `intent.dart` 的 `Intent` 可作为动作的一种实现载体，但要真正接线。

7. **v0.1 明确不做**：手柄运行时、轮盘菜单、鼠标轨迹手势、动作序列（`followUpActions`）、多套配置 profile。
   它们全部进 schema 的**预留位**（可解析、不可编辑），不进 v0.1 的运行时与设置 UI。

## Considered Options

- **照 neoview 做全量 9 类设备**：形态上「继承」得最彻底，但 `mouse-gesture`（轨迹序列识别）与 `radial`（轮盘）
  在 Flutter 侧**没有现成原语**，属于新造；而 v0.1 的判据一条都不涉及它们。
- **只做键盘（照 mImageViewer）**：最省，但会丢掉桌面阅读真正高频的两项——**滚轮翻页**与**画面区域点击翻页**，
  而这两项目前已经硬编码在 `reader_input_controller.dart` 里，等于把已有能力改差。
- **不做绑定体系，保持硬编码**：这是「最小工作量」的字面最优解。但现有硬编码路径**无法被自动测试驱动**——
  v0.1 判据 C 要求「自动连续翻页 100 次并采 `FrameTiming`」，而动作派发与 UI 事件耦合时，
  只能靠模拟按键去测，测出来的是「模拟按键 + 渲染」而不是「翻页 + 渲染」。绑定引擎把动作派发解耦出来，
  判据 C 才能测到它想测的东西。

## Consequences

- **这是对 ADR-0008 冻结线的一次扩张**：「本地漫画 → 归档直读 → 解码 → GPU 上屏 → 超分」之外，
  v0.1 现在多了一整条横切能力。理由只有两条，都必须成立：用户直接要求；
  且它是判据 C 的实现前提（见上一条）。**除这两条之外，冻结线不变**——在线源 / OCR / 上色 / 视频仍然不进。
  > **后续更正（2026-09-25）**：这句之后，**视频页（ADR-0016）与 OCR 翻译（ADR-0018）已各自走同一条流程解冻**；
  > 仍在冻结线外的是在线源 / 上色 / Anime4K。本 ADR 关于操作绑定的决定不受影响。
- **「动作 id」成为跨层契约**。Reader 的行为必须以稳定 id 暴露，不能再散落在 controller 的私有方法里；
  这与 `CONTEXT.md` 里 Reader 的职责定义一致，但对实现是硬约束。
- 设置页新增「操作绑定」卡片，需要一个键盘录制器（`KeySlot` 的「按下即录入」交互）。
- 判据 C 的自动翻页改为**经绑定引擎派发动作**，而不是调用 controller 方法——
  这样「翻页路径」与用户实际路径一致，测的才是真实链路。
- 未验证风险：neoview 的 `mouse-gesture` 与 `radial` 在 Flutter 的实现成本未评估，
  若 v0.2 要做，需要一次独立的可行性调研（与 Gate A 的做法一致：先探针再动手）。
- 依赖 `mImageViewer` 的 `keymap.rs` 仅在**数据模型与策略**层面（`KeySlot` 枚举、`BindingPolicy`、
  左右修饰键、`ChordList` 上限），不引入其 `egui` / Win32 事件层——它那层与 Flutter 的
  `HardwareKeyboard` / `Focus` 事件模型不通用。
