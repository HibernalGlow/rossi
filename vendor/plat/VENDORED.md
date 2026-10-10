# vendor/plat —— vendored 副本（MIT）

- **来源**：<https://github.com/bitshifthq/plat>（pub.dev `plat`）
- **版本**：`0.1.1`（pubspec `^0.1.1`，MIT License © Bitshift LLC，见同目录 `LICENSE`）
- **接入方式**：主 `pubspec.yaml` 用 `path: vendor/plat` 依赖；上游发新版时先看本文件
  「本地改动」一节能否摘除，再整体替换。
- **拷贝范围**：上游整包去掉 `example/`、`test/`、`lefthook.yml`（后三者与运行无关，
  test 由主仓 `test/discover/` 的判据覆盖使用场景）。

## 本地改动（相对上游 0.1.1）

| 文件 | 改动 | 原因 |
|---|---|---|
| `lib/src/ui/tabs/view.dart` | `_DraggableTabState.build`：`!widget.view.acceptsDrops` 时不再给 chip 包 `Draggable`（`// ROSSI VENDORED:` 注释处） | `acceptsDrops: false` 的组没有任何落点会接受拖拽（`_canAccept` 直接 false、`DropOverlay` 也不建），拖拽识别器纯属抢手势：触摸上 ImmediateMultiDrag 超 18px 就起手，会吃掉长按菜单（发现页「长按关闭、稍微一动就变拖拽」）。拖拽在此形态下 100% 无效果，摘除零行为损失，还省一层 per-chip `LayoutBuilder`。 |
| `lib/src/ui/tabs/view.dart` | `_DraggableTab` 改包 `_RossiTabDraggable`（`Draggable` 子类，覆写 `createRecognizer`）：**鼠标/触控板立即起拖，触摸按满 `kLongPressTimeout` 才起拖且不因移动放弃**（`_RossiTabMultiDragGestureRecognizer` + 两个 `MultiDragPointerState` 子类） | 触摸 ImmediateMultiDrag 与宿主长按菜单打架（用户：想长按关闭、稍微一歪就变拖拽）。与菜单的分工是确定性的：按住不动到点 = 菜单赢（先入竞技场先计时）；移动 + 按满时限 = 拖拽；时限内抬起 = 什么都不是。鼠标保持上游手感。 |

上游升级时先核对这两处能否摘除/重放。
