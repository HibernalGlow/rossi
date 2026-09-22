# 千行文件拆分 · 实机验收清单

基线提交：`35a6be81`（开工时 HEAD）。对线请用 `VERIFY_REF=35a6be81`，
期间 main 上又有新提交（如 `399eaeac`），换基线会误判。

本清单只覆盖**静态门禁证明不了的运行时行为**。静态侧已证明的是：
每个拆分都是「整块原文按序搬运」——`tool/ast_split/verify_moves.py` 的
行守恒 + 顺序守恒，加上 `flutter analyze` 的 `lib/` 0 error 与 `cargo check` 不劣于基线。

## 已跑过的自动化门禁（实测数字，2026-09-22）

| 门禁 | 结果 | 说明 |
|---|---|---|
| `flutter analyze` | **267 issues = 与开工基线逐字相同**；`lib/` 0 error | 非 poc 的 error 仅基线那 6 个（`test/reader/page_split_test.dart`） |
| 纯搬家证明 | **11 个 refactor 提交全部 `未承接=0 / 新增=0 / 顺序OK`** | `python3 tool/ast_split/verify_commits.py`，每个提交对自己的父提交验，不受并发提交影响 |
| `cargo test -p rossi_local_core` | **439 passed / 0 failed** | Rust 侧全部拆分在这个门禁上；`cargo check -p rossi_local_core` 0 error |
| `cargo check -p rossi_gpu_present` | exit 0 | `gpu_present` 不在 `default-members` 里，**必须点名**才编到 |
| `flutter test`（workspace/video/discover/reader/comic_read） | **558 通过 / 10 失败** | 失败全部在 `test/discover/**` |
| 失败归因 | 不在本次改动集内 | 本次实际触及 84 个文件，`discover`/`search_bar`/`router` **一个都没有**；断言是 `RouterScope operation requested with a context that does not include a RouterScope`，抛自 `lib/page/search/widget/search_bar.dart:61`，属你在飞的 discover 分屏改动（`aedeab75`/`6b0c7c53`/`a49a038c`） |
| 工具自测 | `SELFTEST PASS` | 6 组，含「篡改必须 FAIL」「重排必须 FAIL」「危险搬家必须被拦」—— 拦的五类里现在有**静态成员**（第 4 条）与 `@protected`（第 3 条） |

下面 28 条则**只能由你在真机/真窗口上验** —— 静态门禁全绿也不代表它们对。

## 三类需要额外留意的点（第 2 条已查清，不再是风险）


1. `extension` 是**静态派发**：把 State/Cubit 的方法搬进 extension 后，若某处经由
   动态调用（`dynamic`、方法 tear-off 传给回调、反射式分发）拿到它，行为可能不同。
2. `part` 拆分对 freezed/ObjectBox **生成物布局**的影响 —— **已查清，不是风险**：
   读 `~/.pub-cache/.../freezed-4.0.1/lib/src/parse_generator.dart` 得到确定答案：
   它遍历 `oldLibrary.element.fragments`（库的**全部** part）取声明，
   输出走 `AnalyzerBuffer.part(oldLibrary.element)`（**整个库一份**）。
   也就是说 `@freezed` 类声明在 `lib/config/global/parts/*_part.dart` 里，
   生成代码照样落回 `global_setting.freezed.dart`，下次 codegen 不会把它重排到新文件。
   因此本次**没有**重跑 build_runner，生成物保持 0 改动（已核）。
3. Rust 侧 `mod` 拆分改了**可见性**（加了 `pub(crate)`/`pub(super)`），编译过但语义上
   被别处误用的可能性由编译器保证，跨模块的 `Drop`/顺序敏感初始化不受影响这一点不受保证。

## 实测出来的 extension 四条硬限制（都真撞过）

把「类的方法搬进 `extension ... on TheClass`」不是无损操作。以下四条都在本仓库里
真实触发过，工具的护栏已按此逐条加严：

1. **跨库 `show` 引入会吃掉 extension 成员。**
   `import 'x.dart' show TheClass;` 只带入类名，extension 不在名单里 →
   调用点直接 `The method 'foo' isn't defined for the type 'TheClass'`。
   实例：`ReaderSeamlessCubit` 搬成员后，`comic_read.dart` 报 6 个这类 error。
2. **extension 里不能裸用宿主的静态成员** —— 这是编译错误
   （`Static members from the extended type ... must be qualified by the name of the defining type`）。
   实例：`GpuPresentController` 的 `_ensureEnhancedForIndex` 等引用了私有静态字段，
   搬走即报 3 个 error。
3. **`@protected` 成员在 extension 里调用违反约定**
   （`invalid_use_of_protected_member`：`setState`、`notifyListeners` 等）。
   这条**运行时行为不变**（仍是 `this` 上的实例调用），但必须显式处理：
   只允许在**调用那一行**加 `// ignore:`，不要用文件级 `ignore_for_file` 整片盖。
   现存 11 个 part 用了文件级 ignore，属于待收口的技术债，见文末。
4. **成员自己是 `static` 的，压根进不了 extension** —— extension 不能声明静态成员，
   所以「被谁引用」都无关，搬过去就是编译错误。这条是 2 的加强版，也是本次
   两处 Dart 停手的**真正原因**（工具逐条给出拒绝理由，非主观判断）：
   - `lib/page/setting/real_sr/service/real_sr_super_resolution.dart`（1204 行）：
     超分后端那一簇（`upscale` / `_upscaleCli` / `_upscaleAndroidCli` / `_upscaleMImageOnnx` /
     `_prepareAndroidCli` / `_androidModelFilesFor` / `_missingModelFiles` / `_copyDirectoryContents` /
     `_detectUpscalableExtension`）全是 `static`，9/9 被拒。
   - `lib/reader/gpu_present_controller.dart`（1476 → 1072 后停在这里）：
     剩下两大块 `present`（202 行，公有宿主类 + 公有成员，另撞第 1 条）与
     `_ensureEnhancedForIndex`（197 行，引用宿主静态 `isPlatformSupported` / `_maxUpscaleAttempts`）。
   唯一能继续搬的形态是把 static 改成**库内顶层私有函数**，但那要求同时改写所有调用点
   （`RealSrSuperResolution._upscaleCli(...)` → `_upscaleCli(...)`），已不是「整块原文搬家」，
   纯搬家证明会失效 —— 因此本次没做。

推论：**私有宿主类**（`_FileManagerCardState`、`_ComicInfoState` 等）搬成员是安全的 ——
库外既 `show` 不到它，也无法覆写或调用它的成员。
**公有宿主类**只有私有成员可搬（工具默认拒绝公有成员，除非 `--allow-public-host`）。

## 又一条边界：1:1 vendored 移植文件不可拆（实测得出）

`script/sync_vendored_modules.py` 的契约是「一个上游文件 ↔ 一个本地文件」。
把 `folder_tree.rs` / `folder_pane.rs` 的行搬进子模块后，报告出现
`[!!] pin 版归一化后与本地仍有代码差异 —— 存在未记录的偏离`，
且偏离性质是**顺序**（内容本身逐字对得上），补 `upstream_normalize` 也表达不了。
⇒ 这类文件与「上游的不动」同理：**不拆**。已把这两处拆分回退（HEAD 里它们本就没有子目录）。
回退后 `--diff` 报告 `[!!] = 0`。

拆这类文件的唯一正途是先改同步脚本的比对单元（接受多文件拼接 + 顺序无关），
那是对他们工具语义的改动，需要单独批准，本次没做。

⚠️ 回退时踩到一次自己的坑：`page_load_scheduler.rs` 的拆分**已经被提交**
（`45b91d97`，根文件 630 行 + `tests/cases.rs`），按「vendored 就都回退」一把删目录
导致 `error[E0583]: file not found for module cases`。教训：**回退前先看
`git ls-tree HEAD -- <目录>`**，已提交的不属于本次。修回后 439 测试重新全过。

## 明确不做 / 延后的项（含原因）

- **B 类那 4 个文件永远到不了 1000 行以下**，这不是没做完，是「上游的不动」的算术后果：
  `sync_service.dart` 上游自己 1491 行、`reader_seamless_cubit.dart` 1323、
  `comic_info.dart` 1237、`real_sr_super_resolution.dart` 1004 —— 一行上游都不搬的话，
  下限就是这些数。对它们的判据因此只有两条，且都已核：
  ① 对上游的 **−** 与拆前逐字相等（`−` 就是「改了上游自己的行」的行数）；
  ② 本仓自己加的行按可搬性搬走（`comic_info` 1355→1321、`sync_service` 1890→1581、
  `global_setting` 1331→891、`main.dart` 1066→968、`collect_comic` 1093→961），
  搬不动的逐项写在上文「extension 四条硬限制」里。
- `rust/gpu_present/src/presenter.rs`（2138 → 881 + 7 个子模块）**已拿到 Windows target 真判据**：
  直接 `cargo check -p rossi_gpu_present --target aarch64-pc-windows-msvc` 会死在
  `dav1d-sys` 的 build script（本机不能为 Windows 交叉构建原生 C 依赖，
  而 `gpu_present` 经 `rossi_local_core` 传递依赖它，`-p` 躲不开）。
  绕法是在**仓库外**建临时 crate，只放 `cfg(windows)` 那几个模块 + 真实 `wgpu`/`windows` 依赖，
  再给 `rossi_local_core` 写一个只含被用到的 5 个符号的 shim，然后
  **对拆分前后各跑一次比对 error 集**：实测 `SPLIT_TALLY=0` 与 `BASE_TALLY=0`
  （warning 46 vs 47，差的是死代码统计粒度）。判据成立靠的是 A/B 同脚手架，不靠 shim 完备。
  跑法要把 pinned 工具链的 bin 前置：
  `export PATH="$HOME/.rustup/toolchains/1.96.1-aarch64-apple-darwin/bin:$PATH"`
  （Homebrew 的 cargo/rustc 看不见 target；`+stable` 语法也不被识别），
  且必须用 `aarch64-pc-windows-msvc`（`x86_64-pc-windows-msvc` 没装 rust-std）。
  仍然**没做**链接与运行验证 —— 只有类型检查。
- `windows/runner/gpu_present_bridge.cpp`（1091 行）**延后，且有具体危险**：
  文件里 `namespace { … }`（第 10–159 行）内含**共享可变状态**
  `std::mutex g_release_target_mutex;`（第 47 行），第 302 / 402 / 555 行三处
  `std::lock_guard` 都锁它。匿名命名空间是**内部链接**，所以把它提到头文件再拆两个 TU，
  会变成**每个 TU 各有一份 mutex** —— 三处加锁从此互相不互斥，而**编译器完全不会报错**。
  要做必须先把它改成具名 `extern std::mutex`（改代码，不是搬家），且本机是 macOS，
  **没有 Windows 工具链可以验证**。建议在 win30902 上做。
- `test/workspace/file_manager_card_test.dart`（1064 行）**停在 1064**：AST 量出来
  `main()` 一个函数就占 **1041 行**，43 个 `testWidgets` 平铺、没有 `group()`，
  其余顶层辅助早已拆进 `test/workspace/parts/`。再降只能给 `main()` 加注册函数 wrapper
  （改结构，不是搬家）。
- `web/rossi_webgpu/rossi_gpu_present.js`（1353 行）**是 wasm-bindgen 生成物**
  （`__wbg_get_imports`、`wasm_bindgen__convert__closures_____invoke__h…`、
  `__wbindgen_enum_Gpu*` 一堆表），与 `_bg.wasm`、`.d.ts` 同批产出，被 `web/index.html` 直接 import。
  按 AGENTS.md「生成物不计入 1000 行约束」，**不拆**。
- 上游自身已超 1000 行的 B 类文件（`sync_service.dart` 上游 1491、`comic_info.dart` 上游 1237、
  `reader_seamless_cubit.dart` 上游 1323、`real_sr_super_resolution.dart` 上游 1004）：
  在「上游的不动」下**不可能**既 <1000 又不搬上游行，故保留 >1000，只把 rossi 自己的行抽走。

请逐条跑一遍，回复**条目号**即可（例如「3、7、12 有问题」）。


## A. 设置与持久化（`lib/config/global/parts/`）

1. 设置页逐屏进出，无异常；**升级后旧值仍在**（用拆分前建的配置启动）。
2. 提示条：位置九宫格逐档切，实际弹出位置跟着变；开关提示（switch toast）开→关→开，
   往返都生效。
3. 喜欢画师：添加/删除/切换高亮/圆形模式，重启后保持。
4. 收藏 tag：新增带别名的 tag、删除、改别名去重；发现页与详情页里 tag **高亮**命中一致。
5. 漫画卡片外观（未读角标样式）切换后立即反映在书架。
6. 文件管理器设置、发现页设置、操作绑定设置三块分别改一项并重启验证保持。
7. 阅读背景 `adaptive` / `adaptiveEdge` 两档：只在本地漫画（GPU 上屏）取色生效，
   在线漫画回落 `auto` 底色。

## B. 阅读器（`comic_info`、`reader_seamless_cubit`）

8. 从详情页点「直接阅读」与从书架续读，两条路都能进且页码正确。
9. 详情页操作栏：左侧 rail 与底部条的自定义动作逐个点一遍有响应。
10. 半无缝章节拼接：翻到章节边界，过渡卡片/无缝加载正常；边界处回翻不卡死。
11. 阅读设置页的「视频」「超分」「阅读背景」「阅读体验」四段都能改且立即生效。

## C. 超分与 GPU 呈现

12. 超分开关往返：开→关→开，实际放大效果变化可见；阈值设置生效。
13. 条件卡（`upscale_conditions_card`）里每条启用条件改完保存后仍被遵守。
14. GPU 上屏路径：本地漫画翻页流畅、增强统计面板数字在变（不是恒零）。
15. 模型缺失时**不要静默退 CPU**：应有明确提示（这是既有口径，别被拆分改回退行为）。

## D. 视频

16. 视频控制浮层：播放/暂停/进度拖拽/音量，以及**悬停预览只解帧、点击才落点**。
17. 主播放器设置项改完立即生效，且浮层按钮不吞手势。

## E. 工作台与文件管理

18. 工作台布局设置页改布局并保存，重启后反映。
19. 文件管理卡片：面包屑跳、列/网格切换、搜索、标签页开合、右键菜单、缩略图加载、
    拖拽移动、设为首页/清除首页。
20. 紧凑轨与栏头右键菜单能开（与泳道「更多」同一份菜单）。
21. 侧向目录树/盘符刷新（`folder_tree`、`folder_pane`、`catalog`）：插拔U盘或改目录后能刷新。
22. 文件操作执行（新建/重命名/删除/移动）在归档与长路径上不报错。
23. 操作绑定的径向菜单（`radial.rs`）：自定义绑定改一处，另一处视图同步。

## F. 网络同步

24. WebDAV 与 S3 各跑一次全量同步，再跑一次增量：设置块（含工作台块）不丢不重复；
    冲突时按时间戳合并的结果正确。

## G. 插件与图源（FRB 侧）

25. 加载本地图源插件并浏览列表、进详情、翻页 —— 验证 `rust/src/api/file_manager.rs`
    拆分没有破坏 FRB 表面（`#[frb]` 函数集合应与拆分前完全一致）。

## H. 构建与平台

26. macOS 构建产物能起（Metal 呈现器 `mac_presenter.rs` 被拆）。
27. **Windows 与 Linux 需另行构建**：`rust/gpu_present/src/presenter.rs` 是 Windows
    专属路径，本机 macOS 上可能被 `cfg` 排除而**从未参与编译** —— 这一项必须由
    Windows 侧构建来验，不能拿本机的绿色当证据。
28. Rust 子模块的 `mod` 声明改动**没碰 FRB 表面**：`#[frb]` 函数计数与名字集合应与拆分前一致
    （已核：49 → 49、集合逐字相同），且 `rust/src/frb_generated.rs` 与 `lib/src/rust/**` 为 0 改动。
    `web/rossi_webgpu/*.js` 是 wasm-bindgen 生成物，本次**不拆**，只需确认 web 目标仍能构建。

## 明确不在本清单范围内

- A 类文件（上游原有、rossi 一行没动：`rust/src/qjs/mod.rs`、`host_runtime.rs`、
  `comic_sync_core.dart`、`object_box/model.dart`、`migration_v1_to_v2.dart`、
  rquickjs 的 JS polyfill 等）本次刻意不拆，动了只会给下次上游同步埋雷。
- `poc/` 与 `vendor/` 下的长文件。
- 生成物（`*.g.dart`、`*.freezed.dart`、`frb_generated*`、`router.gr.dart`）。
