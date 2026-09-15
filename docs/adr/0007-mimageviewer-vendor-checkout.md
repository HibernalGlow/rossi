# mImageViewer 源码以 `vendor/` 内的独立 git 检出复用

> **⚠️ 对象回到 mImageViewer（ADR-0011，2026-09-16）。** ADR-0010 曾把 v0.1 阶段的检出对象换成
> `vendor/comicRD/`（且因为 `comicrd_core` 本来就是干净 crate，不需要先建 fork），该决定已撤回。
> 本 ADR 按原文生效：检出对象是 **`vendor/mimageviewer/`**，clone 自 `HibernalGlow/mimageviewer` fork
> （其 `upstream` 指向 `MikageSawatari/mimageviewer`），**需要先建这个 fork**，且 v0.1 阶段就要 clone。

Rossi 需要「方便本地开发」与「能持续吃掉上游更新」同时成立。我们决定：
**mImageViewer 的源码以独立 git 检出放在 rossi 仓库的 `vendor/mimageviewer/`**
（clone 自 `HibernalGlow/mimageviewer` fork，该 fork 的 `upstream` 指向 `MikageSawatari/mimageviewer`），
父仓库以 **gitlink 记录它的 commit**（即 submodule 语义，`.gitmodules` 记录 fork URL）；
Cargo 侧由**适配层用 `path` 依赖**指向该检出，而不是 `git` 依赖。

效果：源码在树内 → 改一行立刻生效，不需要 `[patch.crates-io]` 指回本机目录；
rev 由父仓库记录 → 仍然等价于「独立仓库 + 锁 rev」；同步上游只需在 `vendor/mimageviewer/`
里 `git merge upstream/main`，父仓库只改一个 gitlink。

## Considered Options

- **只有 fork 仓库，Cargo 用 `git` 依赖锁 rev**：rossi 树内零 mImageViewer 代码，最干净。
  但本地要改它的代码时必须另开一个检出、再用 `[patch.crates-io]` 指回本机 —— 对 ADR-0001 里
  「要往里加功能」（超分换核心、后续视频）这件事是持续摩擦。
- **纯 vendor：整包当成 rossi 的文件提交**：摆脱独立 git，但每次同步上游都会变成跨仓库大 diff，
  与 ADR-0002 的「可同步」相悖，且等于放弃上游 merge 能力。
- **进程级/整包依赖**：已在 ADR-0005 排除。

本方案在形态上就是 git submodule；区别在于我们同时把「本地开发要改源码」当作一等场景，
所以 Cargo 的连法是 `path` 而非 `git`。

## Consequences

- **新机 clone 必须 `--recursive`**（或跑 bootstrap 脚本）。失败症状有误导性：cargo 会报
  「找不到 `vendor/mimageviewer/.../Cargo.toml`」，看起来像路径写错，实际是子模块没拉下来。
- `vendor/mimageviewer/` **不得**成为 rossi workspace 的 member —— 它是另一个 workspace 的根，
  挂进来会把 ffmpeg / pdfium / ort / tantivy 与三个被 `[patch.crates-io]` 替换的 egui 一起拉进构建。
- **spike 阶段必须一并验证的 Cargo 语义（第二个是本次新增）**：
  1. `src/` 下多少模块 `use egui` —— 决定适配层的真实厚度（ADR-0005 已要求）；
  2. path 依赖跨 workspace 的归属行为，以及**它的 `[patch.crates-io]` 不会传递到 rossi**。
     后者其实是好事：适配 crate 若真的够薄（不依赖任何 egui），patch 问题自动消失；
     若不薄，会撞上「同名 crate 有两个来源」的构建错误 —— 这个错误本身就是「不够薄」的证据。
- 父仓库从此多一个 gitlink。`git status` 显示 `vendor/mimageviewer (new commits)` 是**预期信号**，
  不是脏工作区。
- 每次同步上游后，rossi 侧要重新验证的只有**适配层接口**是否还对得上，不是全部源码。
