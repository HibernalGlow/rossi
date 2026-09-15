# 与上游 Breeze 保持可同步，但不保持对齐

Rossi 是 `deretame/Breeze` 的 fork，但改动方向（Flutter UI 重建、Reader 换 RenderBackend、
本地核心换来源）与上游维护范围大面积重叠。我们决定：**保留从上游拉取改动的能力，但不为对齐付出代价**——
不承诺改动可上游化、不向上游提 PR、允许破坏性重构、允许重排目录与替换公共接口；
`upstream` remote 降级为「参考来源」，QuickJS 插件运行时的修复靠人工挑选而非直接 merge。

## Considered Options

- **软分叉**（定期 merge、改动尽量小侵入）：每次 merge 都是冲突战，且会限制目录重排与接口替换，
  与已经定下的 UI 重建和 RenderBackend 替换直接冲突。
- **硬分叉**（彻底不再同步）：放弃了上游对 QuickJS 插件运行时等共享代码的修复，而 Rossi 要沿用这套插件生态。
- **双轨**（核心改动争取上游化）：要同时维护两套接口纪律，对单人项目是纯负担。

## Consequences

- 公共接口、目录结构、上游代码都可以按 Rossi 的需要改，`docs/START_WORK.md` §10 的目录树因此可以重写。
- 上游修复无法直接 merge，需要按提交挑选——这是为自由度付的固定代价。
