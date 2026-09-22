# parts 目录索引

本目录的 part 全部属于同一个库（part of `../mpv_property_probe_test.dart`）。

| 文件 | 行数 | 内容 |
|---|---|---|
| `mpv_probe_live_helpers_part.dart` | 82 | `_loadableLibmpv`、`_openAndAwait`— |
| `mpv_probe_name_table_part.dart` | 73 | `_bundledMpv`、`_cStrings`、`_mpvNamesInUse`— |
| `mpv_probe_sample_fixtures_part.dart` | 293 | `_writeWav`、`_sin`、`_le`、`_four`、`_frame`、`_s16Block` 等 7 项 |
| `video_playback_test_doubles_part.dart` | 181 | `_NullHost`、`_FakeTransport`、`_until`— |

## 各文件管什么

- `mpv_probe_live_helpers_part.dart`
  - `_loadableLibmpv` — 参数原样转发给 `NativeLibrary`，所以传参是这条路上唯一稳的口子。
  - `_openAndAwait` — 超时给到 50 s > 内层的两次 20 s：内层那道重试要是失效了，这条就该红。
- `mpv_probe_name_table_part.dart`
  - `_bundledMpv` — 出厂引擎的二进制：只在构建过 macOS 产物时存在。
  - `_cStrings` — 不用 `strings`：那是外部工具，测试要能在任何开发机上自己跑。
  - `_mpvNamesInUse` — **通过**的测试比失真成一个失败的测试糟得多。
- `mpv_probe_sample_fixtures_part.dart`
  - `_writeWav` — 2 秒 220 Hz 正弦，前半响后半轻（与 Rust 侧那个测试同一份形状）。
  - `_sin` — 只用到一次，避免为了一个 sin 引 dart:math 之外的东西。
  - `_le` *(顶层符号)*
  - `_four` *(顶层符号)*
  - `_frame` — 一帧未压缩 RGB24，行倒序（正高度 DIB 的约定）。
  - `_s16Block` — 一帧的 PCM s16le 音频块（单声道，40 ms）。
  - `_writeAvi` — 这些**要有两条轨才看得见**的路径也能活体验证 —— 纯 WAV 探不到它们。
- `video_playback_test_doubles_part.dart`
  - `_NullHost` *(class)*
  - `_FakeTransport` *(class)*
  - `_until` *(顶层符号)*

## 搬家约定

- 新文件一律用 `tool/ast_split/bin/ast_split.dart` 的 `extract` / `extract-members`
  按 AST 区间整块搬，不要手改函数体；搬完跑 `audit`，再跑 `flutter analyze`。
- 上游已有的文件只允许搬本仓自己的行，判据是
  `git diff --numstat upstream/main -- <文件>` 的 `−` 不得变大。
- 上游代码不得搬动：`extract-members --upstream-file <上游版本>` 会拒绝
  上游已存在的同名成员。

<!-- 本索引由 tool/ast_split/gen_parts_readme.py 生成，改动代码后重跑即可。 -->
