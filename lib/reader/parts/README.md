# lib/reader parts 维护笔记

`gpu_present_controller.dart`（原 1476 行）按职责拆出的 part。宿主类
`GpuPresentController` 是**公有类**，所以这里的搬家受工具的两条护栏约束：

- 只搬了**私有成员**（18 个）。公有成员搬进 extension 会坏两件事：
  跨库 `import ... show GpuPresentController` 的调用点解析不到 extension 成员；
  子类（`test/reader/image_surface_test.dart` 里的 `_SizePresenter`）覆写过的成员会丢失多态。
- 6 个私有成员被工具**拒绝搬出**、仍留在主文件：
  `_ensureEnhancedForIndex`、`_awaitReadyLoop`、`_mutate`、`_logEnhancementBail` 等。
  原因是它们裸用了宿主的**静态成员**（`isPlatformSupported`、`_maxUpscaleAttempts`），
  而 extension 里必须写成 `GpuPresentController.静态名` —— 那是改代码，不是搬家。

## 快速索引

- `gpu_present_enhance_part.dart` — `extension GpcEnhancePart on GpuPresentController`
  - 增强结果的排队与调度：`_scheduleEnhancements*`、`_applyEnhancedToPresenter`、
    `_acceptsEnhancement`、`_recordEnhancedSize`、`_markPhase`、`_markSourceSize`、
    `_resetPageStatus`、`_presenterUsesEnhanced`。
  - 模型与开关：`_initUpscaleSetting`、`_refreshModel`、`_onModelChanged`、
    `_setUpscaleEnabled`、`_onPrefetchChanged`、`_srCacheDir`。
  - 原始帧预览与就绪等待：`_enqueueOriginalPreview`、`_redrawCurrentPage`、`_awaitReady`。
- `gpu_present_frame_part.dart` — 顶层 `GpuPresentedFrame`（呈现帧数据类）。

## 为什么主文件还剩 1071 行

差 71 行才到 1000。那 71 行恰好落在上面被拦下的 6 个静态成员引用方法里。
要继续压只能二选一：把静态成员引用改成限定形式（属于改代码，超出搬家范围），
或抽一个协作者类做委托（属于真重构，需要单独批准）。两者都不在本目录的默认做法里。
