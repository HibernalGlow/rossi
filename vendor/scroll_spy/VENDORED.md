# vendor/scroll_spy —— vendored 副本（MIT）

- **来源**：<https://github.com/omar-hanafy/scroll_spy>（pub.dev `scroll_spy`）
- **版本**：`1.0.5`（MIT License © Omar Hanafy，见同目录 `LICENSE`）
- **接入方式**：主 `pubspec.yaml` 使用 `path: vendor/scroll_spy` 依赖。
- **原因**：
  1. 上游 `scroll_spy` 2.x 要求 Flutter `>=3.47.7` / Dart `>=3.13.5`，而本仓锁定 Flutter `3.47.4` / `3.47.6`（Dart `^3.12.0`）。
  2. 为长设置页的「阅读位置 / 目录（Table of Contents）」场景提供零第三方运行时依赖的焦点区检测（`ScrollSpyRegion`）、选择策略（`ScrollSpyPolicy`）、滞后防闪烁稳定器（`ScrollSpyStability`）以及点击目录锚点跳转期间的锁定机制（`lockPrimary`）。
