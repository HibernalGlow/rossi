# parts 目录索引

本目录的 part 全部属于同一个库（part of `../video_control_overlay.dart`）。

| 文件 | 行数 | 内容 |
|---|---|---|
| `video_overlay_panels_part.dart` | 391 | `_RatePanel`、`_VolumePanel`、`_SubtitlePanel`、`_ColorDot`、`_FilterPanel`、`_LabeledSlider`— |
| `video_overlay_scrub_part.dart` | 410 | `_PositionBuilder`、`_PositionBuilderState`、`_ScrubBar`、`_ScrubBarState`、`_ProgressBar`、`_WaveformPainter` 等 8 项 |

## 各文件管什么

- `video_overlay_panels_part.dart`
  - `_RatePanel` *(class)*
  - `_VolumePanel` *(class)*
  - `_SubtitlePanel` *(class)*
  - `_ColorDot` *(class)*
  - `_FilterPanel` *(class)*
  - `_LabeledSlider` *(class)*
- `video_overlay_scrub_part.dart`
  - `_PositionBuilder` — 只在可见时订阅，避免隐藏的 MD3 Slider 动画继续占用 UI 帧。
  - `_PositionBuilderState` *(class)*
  - `_ScrubBar` — 拖动条：进度 + 已缓冲 + 章节刻度 + A–B 区间 + 悬停帧预览。
  - `_ScrubBarState` *(class)*
  - `_ProgressBar` — 使用 MD3 Slider 提供拖动、键盘操作和进度语义，波形与章节仅作底纹。
  - `_WaveformPainter` — 那种「响度柱」，折线在小尺寸上会糊成一团。
  - `_FramePreviewBubble` *(class)*
  - `_PreviewBusyChip` — 「定位中」角标：解帧没回来 / 回来的不是这一格。

## 搬家约定

- 新文件一律用 `tool/ast_split/bin/ast_split.dart` 的 `extract` / `extract-members`
  按 AST 区间整块搬，不要手改函数体；搬完跑 `audit`，再跑 `flutter analyze`。
- 上游已有的文件只允许搬本仓自己的行，判据是
  `git diff --numstat upstream/main -- <文件>` 的 `−` 不得变大。
- 上游代码不得搬动：`extract-members --upstream-file <上游版本>` 会拒绝
  上游已存在的同名成员。

<!-- 本索引由 tool/ast_split/gen_parts_readme.py 生成，改动代码后重跑即可。 -->
