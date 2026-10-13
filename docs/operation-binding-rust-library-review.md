# Rust 操作绑定库复用评估

核对日期：2026-10-13。范围是下列固定发布版本的 Cargo 清单、源码和官方文档，
不把仓库主分支、计划功能或关闭渲染功能等同于已经提供框架无关核心。

## 结论

Rossi 继续使用独立 `operation_binding_core`。本轮不增加外部输入库作为生产依赖，
也不实现 NAPI-RS。各库适合借鉴不同部分，尚没有一套能直接替代现有键鼠、触屏区域、
可配置上下文、冲突诊断和配置迁移链路。

| 库 / 核对版本 | 能否直接接入 | 可借鉴之处 | 采用判定 |
| --- | --- | --- | --- |
| keybinds 0.2.0 | 可以作为独立键盘子库；默认无框架特性 | KeyInput / KeySeq、序列超时与 reset、可选事件适配 | 暂不引入，等实际需要多段快捷键时再评估 |
| bevy_action_map 0.1.2 | 依赖 Bevy app/ECS/input 等 0.20.0 组件；核心求值函数不是独立公共 API | 稳定 Action ID、上下文优先级、重绑定覆盖层、输入消费与诊断 | 参考设计 |
| leafwing-input-manager 0.21.0 | 依赖 Bevy 0.19，关闭默认功能仍保留 Bevy | InputMap、ActionState、ClashStrategy、输入快照测试 | 参考冲突处理与测试方法 |
| bevy_enhanced_input 0.26.0 | 依赖 Bevy 0.19.0，默认特性开关不解除 ECS 集成 | Trigger / Modifier 分工、动作状态、Context 与消费行为 | 参考触发器与状态生命周期 |
| input-actions 0.1.1 | 框架依赖较轻，但官方明确标注未达生产可用 | ActionSet / Layout 的模型 | 不作生产基础 |

`keybinds` 的 MIT、三套 Bevy 库的 MIT OR Apache-2.0 授权允许按相应许可复用。
本轮没有复制上游实现；是否引入取决于功能和运行模型，不是许可证阻碍。

## keybinds 的实际实验

在仓库外创建最小 Cargo 宿主，固定 `keybinds = "=0.2.0"`，仅启用 `serde`：

- `Ctrl+s` 单步组合键命中。
- `Ctrl+x Ctrl+s` 两段序列命中。
- 序列中途调用 `reset()`，后续按键不延续上一上下文的序列。
- 先注册 `g`、再注册 `g g` 时，两次 `g` 都命中短绑定，长绑定不触发。
- `serde_json::to_string(&bindings)` 成功，随后 `from_str::<Keybinds<String>>()` 失败。

发布包源码解释了后两项：`src/keybind.rs::dispatch` 命中完整绑定时立即清空 `ongoing`；
`src/serde.rs` 的 Keybinds visitor 实现 `visit_map`，入口却调用 `deserialize_str`。
实际错误为 `invalid type: map, expected key bindings object as pairs of key sequences and actions`。
这限定于本次核对的 0.2.0 发布包，不推断未来版本仍有同一问题。

此外，`dispatch()` 的 `None` 同时表示「序列未完成」与「没有匹配」；如果要决定是否
阻止文本框输入，宿主还需要自己明确序列前缀的消费策略。上下文变化也必须重置序列状态。
这些都与 Rossi 当前无状态的单次描述符匹配不同。

若未来确实需要 `Ctrl+K Ctrl+S`，可以让 keybinds 专门产生键盘序列描述符，再由现有核心
统一处理上下文、区域以外的匹配维度、冲突和动作；不要同时维护两套 Context 优先级。
当前 Rossi 使用 `KeyK`、`ArrowRight` 等稳定 key code，而 keybinds 有自己的 Key/Mods
词汇，也需要显式映射，不能直接用它的配置替换现有文档。

实验位置：`/tmp/rossi-input-library-evaluation/keybinds_probe`。
运行命令：

```sh
cargo run --manifest-path /tmp/rossi-input-library-evaluation/keybinds_probe/Cargo.toml
```

## bevy_action_map 的关键区别

它没有强行依赖整个 Bevy 渲染引擎，而是拆用 `bevy_app`、`bevy_ecs`、`bevy_input`、
`bevy_math`、`bevy_time`、`bevy_platform` 等组件。这比「必须引入完整游戏引擎」轻，
但仍要求 Bevy 的调度、资源和实体状态。关闭 `bevy_reflect`、`state` 或默认特性不会
把它变成接受 JSON 输入、返回动作 ID 的纯解析库。

`eval/context_systems.rs::evaluate_context` 等求值入口是 `pub(crate)`，输入读取与
上下文系统直接使用 Bevy 类型。要单独拿出这些实现，需要移植并维护，不等于直接导入。
`touch` Cargo feature 存在，但 README 明确写为预留且尚未实现，不能据此承诺触屏支持。

最适合 Rossi 参考的是「稳定 ID 持久化、默认绑定与用户覆盖分开、优先级与消费分开」：
这能帮助以后升级默认表，而不会覆盖用户删除或禁用的条目。复杂 Conditions、Modifiers
和逐帧 ActionState 先保留在需求清单，不在这次区域/触屏迁移中全部加入。

## 对当前实现的影响

- 公共核心只依赖 serde、serde_json、anyhow，动作、上下文与区域使用宿主提供的 ID。
- 上下文优先级与区域精度由同一个 Rust 解析器决定，诊断复用相同判定。
- 默认值升级和 Reader 行为留在 Rossi 适配层；协议迁移保留扩展字段并报告转换结果。
- Flutter 控件消费、双击/长按时间判定与事件采集留在 Flutter，核心不接管手势竞技。
- 已有非 Flutter Rust 测试宿主验证复用边界。将来按实际需求增加薄适配器，无需现在加入 Node 或 Bevy。

## 一手资料

- [keybinds 0.2.0 官方 API](https://docs.rs/keybinds/0.2.0/keybinds/)
- [keybinds 0.2.0 匹配实现](https://docs.rs/crate/keybinds/0.2.0/source/src/keybind.rs)
- [keybinds 0.2.0 Serde 实现](https://docs.rs/crate/keybinds/0.2.0/source/src/serde.rs)
- [keybinds 0.2.0 发布清单](https://docs.rs/crate/keybinds/0.2.0/source/Cargo.toml)
- [bevy_action_map 0.1.2 README](https://docs.rs/crate/bevy_action_map/0.1.2/source/README.md)
- [bevy_action_map 0.1.2 发布清单](https://docs.rs/crate/bevy_action_map/0.1.2/source/Cargo.toml)
- [bevy_action_map 0.1.2 Context 求值源码](https://docs.rs/crate/bevy_action_map/0.1.2/source/src/eval/context_systems.rs)
- [Leafwing 0.21.0 官方 API](https://docs.rs/leafwing-input-manager/0.21.0/leafwing_input_manager/)
- [Leafwing 0.21.0 发布清单](https://docs.rs/crate/leafwing-input-manager/0.21.0/source/Cargo.toml)
- [bevy_enhanced_input 0.26.0 官方 API](https://docs.rs/bevy_enhanced_input/0.26.0/bevy_enhanced_input/)
- [bevy_enhanced_input 0.26.0 发布清单](https://docs.rs/crate/bevy_enhanced_input/0.26.0/source/Cargo.toml)
- [input-actions 0.1.1 官方 API 与生产警告](https://docs.rs/input-actions/0.1.1/input_actions/)
