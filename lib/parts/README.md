# lib/parts 维护笔记

`lib/main.dart` 按职责拆出的 part 索引。

## 快速索引

- `main_boot_fallback_part.dart`
  - 启动兜底 UI 与启动日志：`_writeBootLog`（启动失败原因落盘 `/tmp/breeze_boot.log`）与
    `_runBootFailureApp`（启动失败时显示可读错误页而不是黑屏）。

## 常用定位方式

- 应用启动黑屏 / 启动异常没弹界面：看 `main_boot_fallback_part.dart` 与 `main.dart` 里调用它们的 catch 分支。
- 启动后日志内容：`/tmp/breeze_boot.log`。
