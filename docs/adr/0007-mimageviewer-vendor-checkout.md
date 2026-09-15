# mImageViewer 源码以 `vendor/` 内的独立 git 检出复用

> **⚠️ 对象回到 mImageViewer（ADR-0011，2026-09-16）。** ADR-0010 曾把 v0.1 阶段的检出对象换成
> `vendor/comicRD/`（且因为 `comicrd_core` 本来就是干净 crate，不需要先建 fork），该决定已撤回。
> 本 ADR 按原文生效，且**已落地（2026-09-16）**：检出对象是 **`vendor/mimageviewer/`**。
>
> **源头是原版上游，不是个人 fork**（同日第二次更正）：最初检出的是
> `HibernalGlow/neoxide`（那是 `MikageSawatari/mimageviewer` 的 fork，只多出 2 个中文 i18n 提交，
> 且与上游 diverged：领先 2、落后 34）。**该 fork 不会被维护，所以它不该当源头** ——
> 让它躺在中间只会制造「以为在跟上游、其实停在某个私人分支」的静默漂移（正是 ADR-0002 要避免的）。
> 现在的形态：`.gitmodules` 直接指向 `https://github.com/MikageSawatari/mimageviewer.git`，
> 父仓库 gitlink = **`1fd6f863`**（上游 `main` 当时的提交），子模块工作树与上游零漂移。
> 丢掉的只是那 2 个 i18n 提交 —— 它们是 UI 字符串层，而 ADR-0005 已经把 UI 层排除在复用范围外。
> 详见 `docs/phase0-vendor-spike.md` §0。

Rossi 需要「方便本地开发」与「能持续吃掉上游更新」同时成立。我们决定：
**mImageViewer 的源码以独立 git 检出放在 rossi 仓库的 `vendor/mimageviewer/`**
（**直接 clone 自原版上游** `MikageSawatari/mimageviewer`，不经过个人 fork，理由见上方横幅），
父仓库以 **gitlink 记录它的 commit**（即 submodule 语义，`.gitmodules` 记录上游 URL）；
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
- **它用 git-lfs 存根目录 `models/` 下 9 个模型（合计 335 MB）。**
  当前检出**保留指针文件**（v0.1 用不到模型，Gate B 才用）。`git lfs pull` 可取回（约 335 MB 带宽）。
  注意两个「另一处的 ONNX」不要混：`src/ai/model_manager.rs` 的 `include_bytes!` 指向
  **`vendor/models/`**，那个目录被 `.gitignore` 排除、**由 `build.rs` 构建期生成**——
  所以「干净检出上直接编译它的主 crate」本来就不成立。
- **spike 阶段必须一并验证的 Cargo 语义（已全部完成，2026-09-16）**：
  1. `src/` 下多少模块 `use egui` —— 467 个 `.rs` 里 **183 个碰 egui，其中 92 个名字不像 UI**；
     但 11 个复用种子里 8 个干净，**剪 9 个直接脏依赖**即可自洽（`docs/phase0-vendor-spike.md` §1）。
  2. path 依赖跨 workspace 的归属行为，以及**它的 `[patch.crates-io]` 不会传递到 rossi**。
     **已实测**（证据在 `poc/cargo-patch-scope/`）：确实不传递，而且症状是**静默**的 ——
     父 workspace 会解析到 crates.io 上的最新满足版本（实测 `cfg-if = "1"` 拿到 **1.0.4**，
     比外部本地副本的 1.0.0 还新），**不报错**。
     → **原表述「若不薄，会撞上『同名 crate 有两个来源』的构建错误」已实测证伪**：
     同名同版本来自两个来源时 Cargo 允许共存（实测案例 3 / 4），不会给任何提示。
     → 修法有两条：**（a）**rossi 自己的 workspace 根（`rust/Cargo.toml`）写一份同样的
     `[patch.crates-io]` 指向 `vendor/mimageviewer/vendor/egui`（实测生效，
     代价是这份 patch 表要跟着上游同步维护）；**（b）**适配层**不依赖任何被 patch 的 crate**
     —— 那 patch 传不传递就与我们无关。**（b）才是「薄」的意义所在。**
- 父仓库从此多一个 gitlink。`git status` 显示 `vendor/mimageviewer (new commits)` 是**预期信号**，
  不是脏工作区。
- 每次同步上游后，rossi 侧要重新验证的只有**适配层接口**是否还对得上，不是全部源码。
- **运维坑（2026-09-16 实际踩到）**：`git submodule add` 若在 checkout 阶段被 LFS 打断，
  会留下一个**索引为空**的子模块（`git -C vendor/mimageviewer ls-files` 返回 0，
  2235 个文件全被报成 `D`），但 `.gitmodules` 与 gitlink 都没写。
  修复顺序：先 `GIT_LFS_SKIP_SMUDGE=1 git -C vendor/mimageviewer reset --hard HEAD` 重建工作树，
  再手写 `.gitmodules` 并 `git add` 该路径（gitlink 的 mode 必须是 `160000`），
  **最后还要 `git submodule init`** —— `submodule add` 被中断时不会往 `.git/config` 写登记，
  漏了这步 `git submodule status` 会以 `-` 开头（表示「未初始化」），看起来像子模块坏了。
