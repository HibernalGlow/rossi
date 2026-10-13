# Operation Binding Core

框架无关的 Rust 操作绑定核心。仅依赖 `serde`、`serde_json`、`anyhow`，不依赖
Flutter、FRB、Node、Bevy、文件浏览、图像或媒体处理。

核心负责输入描述、可配置上下文、确定性匹配、冲突检测、诊断与 JSON 迁移。
宿主负责真实事件采集、控件命中和消费、区域几何、动作目录与动作执行。
Rossi 的 Reader、九宫格、默认表和阅读方向留在 `rossi_local_core::operation_binding`。

## 接入

```toml
[dependencies]
operation_binding_core = { path = "path/to/operation_binding_core" }
```

```rust
use operation_binding_core::{InputBindingsConfig, InputDescriptor, resolve,
    resolve::conflicts_with_contexts, migration};

# fn example(raw: &str, input_json: &str) -> anyhow::Result<()> {
let migrated = migration::migrate_json(raw)?;
let config: InputBindingsConfig = serde_json::from_value(migrated.document)?;
config.validate()?;
anyhow::ensure!(conflicts_with_contexts(&config.bindings, &config.contexts).is_empty(),
    "Conflicting bindings");
let event: InputDescriptor = serde_json::from_str(input_json)?;
if let Some(binding) = resolve(&config.bindings, &event, &config.contexts, &["canvas".into()]) {
    // 宿主按序执行 binding.actions()。
    println!("{}", binding.action);
}
# Ok(()) }
```

[Rust 测试宿主](examples/json_host.rs) 脱离 Flutter，读取同一 JSON 文档并输出迁移报告、
匹配动作与候选未命中的原因。从 Rossi 仓库根目录运行：

```sh
cargo run --manifest-path rust/Cargo.toml -p operation_binding_core --example json_host
cargo test --manifest-path rust/Cargo.toml -p operation_binding_core
```

可传入文档路径、输入 JSON 和活跃上下文 ID。示例使用 `canvas`、`selection`、
`rename`、`tool-palette`，不含 Reader 词汇。

## v2 协议

[JSON Schema](schema.v2.json) 描述结构；上下文引用、环、ID 唯一性和冲突需要 Rust 校验。
导出的自描述文档应包含 `contexts`；迁移也接受不带注册表的文档，由宿主补齐。
`InputBindingsConfig::validate()` 要求每条绑定引用已声明上下文。

```json
{
  "format": "operation-bindings",
  "format_version": 2,
  "contexts": [{"id": "canvas", "priority": 100}],
  "bindings": [{
    "id": "palette-tap", "action": "canvas.select-tool", "context": "canvas",
    "enabled": true,
    "input": {"device": "touch", "gesture": "tap", "fingers": 1, "area": "tool-palette"}
  }]
}
```

输入使用类型化联合体：keyboard、mouse、mouse-gesture、wheel、touch、gamepad、radial、command。
鼠标和触屏可附带可选 `area`；省略表示不限区域。区域与上下文、动作都是宿主 ID。
核心不从坐标或操作系统猜来源，也不将触屏回退到鼠标。

匹配契约：

1. 宿主先处理控件消费；只把待处理事件交给核心。
2. 子上下文激活父上下文；`global` 默认参与，活跃 `isolatesGlobal` 上下文阻止全局绑定。
3. 跳过禁用、未激活、隔离和输入不符的候选。
4. 先比较上下文 `priority`，同优先级时指定区域优先于通用区域。
5. 同优先级、同精度且输入重叠的绑定由冲突检测拒绝；已存在的冲突按注册顺序取第一项。

`diagnose()` 与 `resolve()` 使用同一套排名逻辑，报告输入、实际活跃上下文、选中绑定与动作，
以及 disabled / unknown-context / inactive-context / isolated-global / input-mismatch /
lower-priority / less-specific / tied / matched 原因。

## 迁移与扩展字段

未版本化数组和 `{bindings: [...]}` 视为 v1；v1 `area` 转为 `mouse` + `area`。
旧区域主键单击另复制一条 `touch` + `tap` + `area`，ID 冲突使用确定后缀。
不为旧鼠标右键、长按或双击虚构触屏动作。禁用、追加动作、时序和未知字段保留。
更高版本、损坏文档或无效参数返回错误。迁移幂等，报告转换和新增的绑定 ID。

迁移操作 `serde_json::Value`，不会丢弃扩展字段。类型化结构用于匹配，会忽略未知字段；
需要无损保存的宿主应保留迁移后的原文档，只替换被编辑字段，不能用类型化结构往返覆盖扩展。
`durationMs`、`moveTolerancePx` 等事件采集参数由宿主解释，不参与描述符相等判断。
持久化和迁移原文备份由宿主在成功校验后一次保存。

## 后续适配

当前提供 Rust API 与 Rossi 的 FRB 入口。后续有实际需求时，可新增独立 NAPI-RS、C ABI 或
WASM 包；它们只转换参数并调用本 crate，不把运行时依赖加进核心，不复制匹配规则。
本轮没有实现或发布这些适配器。
