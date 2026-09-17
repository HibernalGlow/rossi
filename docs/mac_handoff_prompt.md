# Rossi 交接 prompt（Windows → Mac，2026-09-17）

把下面整段作为第一条消息发给新会话即可。

---

我在开发 **HibernalGlow/rossi**（fork 自 `deretame/Breeze`，MPL-2.0）：本地漫画阅读器，v0.1 = 散图/CBZ/CBR → 归档直读 → 解码 → GPU 上屏 → 超分 + 操作绑定。纪律：与上游可同步、不对齐、不 PR；**先不推远端**；分支名扁平；判据 A–E 只在 Release 成立、只看帧时间不看平均 FPS、用真实内容不用低熵图。**Windows 是第一验收平台**，macOS 的 Gate A-M 未验、不阻塞 Phase 1–2。权威文档在仓内：`CONTEXT.md`、`docs/adr/0001–0011`、`ROADMAP`、`v0.1_acceptance.md`、`docs/texture-bridge-integration.md`、`docs/windows-build/`、`.workbuddy/memory/ENV-AND-BUILD.md`（踩坑先读它）。

## 我刚做完的事（Windows 机器上，未提交）

上一批「接预取」已提交为 `20477cca`（Release present 中位 479→16 ms、38/40 命中）。之后这批改动**还在工作树里没提交**：

1. **异步 show（核心改动，修「冷页照冻 400–500 ms」）**：`windows/runner/gpu_present_bridge.{h,cpp}`。原实现里冷页 `show` 在**平台线程**（兼 Win32 消息泵）上同步持锁解码 400–500 ms，窗口冻死。改法：桥起自己的工作线程跑 `PerformShow`，平台线程只做参数校验+投递+立刻返回；应答用 `FlutterEngine::PostPlatformThreadTask` 投回平台线程（文档明说可任意线程调用）；`MarkExternalTextureFrameAvailable` 也是任意线程合法。锁拆成两把：`mutex_`（presenter 访问+计数）与 `snapshot_mutex_`（只护当前句柄/尺寸/代际小快照），加锁顺序恒 `mutex_` → `snapshot_mutex_`，`SurfaceCallback` 稳态只拿快照锁。show 单槽不排队：`show_in_flight_` 时回 `busy` 错误。开关：`ROSSI_GPU_SHOW_ASYNC=0` 关异步；`ROSSI_GPU_SHOW_TRACE=<ASCII 路径>` 落盘跟踪。`MethodResult` 用 `shared_ptr` 过 `std::function`（要求可拷贝）。
2. **量具增强**：`lib/gpu/page_turn_probe.dart` 加 `ROSSI_PAGE_TURN_STRIDE`（stride 大于预取半径 ±2 即每轮冷页）、自报 `show_async`/`show_busy_rejected` 两列；`.workbuddy/tools/run_page_turn_probe.py` 加 `--stride`/`--no-async-show`、改成按产物判完成（`.frames.csv` 连续两次大小不变即完成，强杀赖着不走的进程）；新建 `.workbuddy/tools/compare_probe_runs.py`（对比 present 中位/p95、帧跨度、判据 C、show 跑在哪条线程）。

**冷页基线（async=OFF 对照组 cold_off_a/b，stride=10、20 轮真内容）**：present 中位 **501 ms**、命中 0/20、帧跨度 p95 **524 ms**/最大 563 ms、9 帧 >100 ms、判据 C p95=18.26 ❌ —— 这就是「窗口冻半数」的实证。async=ON 的复测还没拿到。

## 当前卡着一个 bug（交接重点）

**async=ON 在 `turns=20` 下量具只写表头（303 B，零轮）**，而 `turns=3` 短跑**有时**能跑通 3 轮（第一次带 trace 的短跑成功、第二次同参数零轮）——**是竞态**。

已确认的证据链：
- 三行 turns 数据的 rust 计时完全相同（462.7/458.8/0.9/3.0）、`native_page`/`present_seq` 恒 0，桥 trace 只有一条 `handler-accept idx=0` → **第 0 轮 `present` 的 future 再也没回来** → 控制器 `_syncing` 永远为 true → 之后每轮在 `lib/reader/gpu_present_controller.dart` 早退，桥根本没收到第二次 show。不是 worker 死锁（trace 显示 perform/mark/post 都走完了）。
- 桥的落盘跟踪会**丢行**（`resolve-enter` 没出现，但同一次连 `worker-inflight-clear` 也丢了；`TraceTo` 是 fopen("a")+fclose 多线程裸写）→ 「没有 resolve-enter」**不足以下结论**，先修跟踪本身（单文件 + 互斥或 `O_APPEND` 原子追加）。
- 已查引擎源码：client wrapper 里 `EngineMethodResult` 的应答 lambda 注释明确 **"This lambda can be called on any thread"**（ReplyManager 自带 messenger 锁）；`PostPlatformThreadTask` → `FlutterDesktopEnginePostPlatformThreadTask` → 投给 engine 的 platform task runner，`TaskRunnerWindow` 靠 `PostMessage` 唤醒主循环。**理论上跨线程应答合法**，所以别再往「线程不合法」方向猜；嫌疑集中在：① 任务投得太早（引擎消息循环还没起来？首帧前 `PostPlatformThreadTask` 是否被吞）；② ReplyManager 回执 id 注册/匹配的竞态；③ 跟踪丢行掩盖了真实断点。

下一步建议（在能跑 Windows 的环境）：修好原子跟踪 → 跑 `turns=3` × 若干次抓一次失败样本 → 看 `resolve-enter` 是否真的没执行 → 若没执行，在 `PostPlatformThreadTask` 前后与引擎侧 `platform_task_runner` 的回调注册时序上加打印；同时给 `lib/gpu/gpu_present_bridge.dart` 的 `show()` 加 Dart 侧落盘跟踪（区分「任务没跑」vs「应答没回 Dart」）。量具侧也可顺手加固：`_autorunProbe` 目前盲等固定 dwell，应改为等 `presentCount` 真的 +1 或超时，且对 `busy` 拒单要有处理。

## 三个已知点（记录，别假装解决）

1. **关窗时预取正好在解码**没实测过 —— 产品走 Drop 的 stop+join，按构造安全，但需要**手动**做一次：打开 GPU 上屏页 → 立刻关窗。
2. 命中时「渲染提交」Release 比 Debug 慢一个量级（4–20 ms vs 1.0–2.6 ms），原因未查，不影响结论。
3. `docs/texture-bridge-integration.md` 待更新：§2.2（共用一把锁、show 在平台线程 → 两锁+工作线程）、§6.4 新增「冷页照冻」小节、§7 划掉对应待办。

## Mac 环境要做什么

1. 装环境：Xcode CLT、Flutter（稳定版）、Rust、`cargo install flutter_rust_bridge_codegen`（版本对齐仓内）；clone 必须 `git clone --recursive`（`vendor/mimageviewer/` 是独立 gitlink）。
2. 注意平台差异：`rust/gpu_present/`（cdylib + D3D12 共享纹理）与 `windows/runner/` 是 **Windows-only**，Mac 上不可用；本地核心 `rust/local_core/`（基线 57 passed）与 Flutter/Dart 层是跨平台的。解码链 dav1d/jxl-rs 是纯 Rust，Mac 直接能编；AV1/AVIF 的 Windows 特殊处理不适用。构建/测试命令先读 `docs/windows-build/README` 与 `ENV-AND-BUILD.md` 再类比 Mac。
3. 我之前留在 Windows 机器上的未提交改动（异步 show + 量具）需要先想办法同步过来：要么我在 Windows 侧提交后你拉取（记得**不推远端**纪律 → 可用本地 bundle / patch 文件带过去），要么把 diff 拷过来重放。
4. 顺手项（我之前被截断的请求）：在 Mac 上跑 `brew tap hibernalglow/tap` 和 `brew install --cask splayer-next`（macOS ≥ 12，arm64/x64 双架构）——如果这两个命令的目的就是 Mac 环境准备，直接执行即可。

第一件事：帮我评估「异步 show」这套改动怎么带到 Mac 继续调试（提交方式/同步方式），然后接着修上面那个零轮竞态 bug。
