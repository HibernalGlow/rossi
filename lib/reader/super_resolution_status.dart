/// 「当前页超分到哪一步了」这份状态，以及它在顶栏上怎么显示。
///
/// # 为什么要单独一个文件
///
/// 顶栏那枚芯片要回答三个问题：**这一页现在什么状态**、**超分后是多少分辨率**、
/// **开关是开是关**。前两个都是**推断**，而推断最容易写成「看代码像是对的」——
/// 于是这里把它拆成两半：
///
/// - **打点**：流水线每真的走到一步就写一个字（`GpuPresentController` 负责）。
///   没走到就不写，绝不靠「我调过那个方法」推断；
/// - **归一化**：开关、平台、原图旁路这些**界面态**压在打点之上（[resolveSuperResolutionStatus]）。
///
/// 第二半是纯函数，可以直接写判据。第一半只做「把真事写下来」这一件事，
/// 不掺任何显示逻辑 —— 否则界面改一次文案就要动流水线，而流水线是判据 A–E 的
/// 关键路径，动它风险太高。
///
/// # 一个刻意的区分：`ready` 与 `applied`
///
/// 「超分图生成了」与「画面上真的是超分图」是两件事，中间隔着注入与上屏两道闸
/// （见 `GpuPresentController._applyEnhancedToPresenter` 的注释）。共用一个词，
/// 就会回到那条老路上：日志说成功、画面还是原图。所以界面上也分开说。
library;

import 'dart:ui' show Size;

/// 当前页超分流水线所处的阶段。
///
/// 分两组，**不要混用**：
///
/// - **界面态**（[unsupported] / [disabled] / [originalPreview]）：由开关、平台、
///   旁路算出来，流水线不打这两个点；
/// - **流水线打点**（[queued] 起）：只有真的走到那一步才会被写下来。
///
/// [idle] 是「没有任何记录」的兜底 —— 超分开着、刚翻到这一页、还没排上。
enum SuperResolutionPagePhase {
  /// 本平台没有 GPU 共享纹理这条路，超分替换无从谈起。
  unsupported,

  /// 超分开关关着。
  disabled,

  /// 开着，但正处在「对比原图」旁路（画面上是原图，超分图还在）。
  originalPreview,

  /// 已排进队列，还没轮到。
  queued,

  /// 正在推理。
  running,

  /// 超分图已在盘上 / 已注入呈现器，但这一帧还没被确认用上。
  ready,

  /// 呈现器确认当前画面取自超分图。
  applied,

  /// 分辨率已达阈值（或格式不支持），这一页不需要超分。
  skipped,

  /// 这一页超分没成功（未产出产物、或注入后仍显示原图、或推理抛错）。
  failed,

  /// 还没有关于这一页的任何记录。
  idle,
}

/// 「第几页、到哪一步、原图多大、超分后多大」的一组快照。
class SuperResolutionPageStatus {
  const SuperResolutionPageStatus({
    required this.index,
    required this.phase,
    this.sourceSize,
    this.enhancedSize,
  });

  /// 页下标（0 起）。`-1` = 还没有当前页。
  final int index;

  final SuperResolutionPagePhase phase;

  /// 送进超分的那张图的像素尺寸（= 原图尺寸）。没量到就是 `null`。
  ///
  /// 刻意允许 `null` 而不是编一个：归档里的页拿不到磁盘路径时量不了，
  /// 而「不知道」显示成「0×0」是在撒谎。
  final Size? sourceSize;

  /// 超分产物的像素尺寸。还没产出就是 `null`。
  final Size? enhancedSize;

  /// 显示给用户的页码（1 起）。下标未知时返回 `null`。
  int? get pageNumber => index < 0 ? null : index + 1;

  @override
  String toString() =>
      'SuperResolutionPageStatus(index: $index, phase: $phase, '
      'source: $sourceSize, enhanced: $enhancedSize)';
}

/// 把「界面态 + 流水线打点」归一成唯一一个可显示的状态。
///
/// 优先级**从上到下**，顺序就是它的意义：
///
/// 1. [SuperResolutionPagePhase.unsupported]：平台没有这条路，别的都无从谈起；
/// 2. [SuperResolutionPagePhase.disabled]：开关关着 —— 即使盘上有超分产物也不显示
///    「已超分」，因为**现在画面上的就是原图**，说已超分是假的；
/// 3. [SuperResolutionPagePhase.originalPreview]：旁路开着，画面上同样是原图；
/// 4. [recorded]：流水线自己打的点（排队 / 推理 / 已生成 / 已超分 / 跳过 / 失败）；
/// 5. [SuperResolutionPagePhase.idle]：没有记录。
///
/// [recorded] 里**不该出现**第 1–3 项 —— 出现也按记录值显示，但那是记账写错了，
/// 不在这个函数兜底（兜了就会把「流水线写错」变成「界面上看不出来」）。
SuperResolutionPageStatus resolveSuperResolutionStatus({
  required int index,
  required bool platformSupported,
  required bool upscaleEnabled,
  required bool originalPreview,
  required SuperResolutionPagePhase? recorded,
  Size? sourceSize,
  Size? enhancedSize,
}) {
  final SuperResolutionPagePhase phase;
  if (!platformSupported) {
    phase = SuperResolutionPagePhase.unsupported;
  } else if (!upscaleEnabled) {
    phase = SuperResolutionPagePhase.disabled;
  } else if (originalPreview) {
    phase = SuperResolutionPagePhase.originalPreview;
  } else {
    phase = recorded ?? SuperResolutionPagePhase.idle;
  }
  return SuperResolutionPageStatus(
    index: index,
    phase: phase,
    sourceSize: sourceSize,
    enhancedSize: enhancedSize,
  );
}

/// 阶段短标签（顶栏芯片上那一两个字）。
String superResolutionPhaseLabel(SuperResolutionPagePhase phase) =>
    switch (phase) {
      SuperResolutionPagePhase.unsupported => '不支持',
      SuperResolutionPagePhase.disabled => '超分关',
      SuperResolutionPagePhase.originalPreview => '原图对比',
      SuperResolutionPagePhase.queued => '排队中',
      SuperResolutionPagePhase.running => '超分中',
      SuperResolutionPagePhase.ready => '已生成',
      SuperResolutionPagePhase.applied => '已超分',
      SuperResolutionPagePhase.skipped => '无需超分',
      SuperResolutionPagePhase.failed => '超分失败',
      SuperResolutionPagePhase.idle => '待超分',
    };

/// 阶段是不是「正在进行中」—— 界面上用它决定要不要转小圈。
bool superResolutionPhaseIsBusy(SuperResolutionPagePhase phase) =>
    phase == SuperResolutionPagePhase.running ||
    phase == SuperResolutionPagePhase.queued;

/// 阶段是不是「这一页已经有超分产物」（不论画面上是不是它）。
///
/// [SuperResolutionPagePhase.applied] 与 [SuperResolutionPagePhase.ready] 的区别
/// 只在上屏；原图对比时产物同样在，只是被旁路挡住。芯片用这个判断要不要走强调色 ——
/// 「有产物」才配得上强调色，否则一眼看不出开关开了没有。
bool superResolutionPhaseHasEnhancedResult(SuperResolutionPagePhase phase) =>
    phase == SuperResolutionPagePhase.applied ||
    phase == SuperResolutionPagePhase.ready ||
    phase == SuperResolutionPagePhase.originalPreview;

/// `2400×3600`；尺寸未知返回 `null`。
///
/// 分隔符用 `×`（U+00D7）而不是字母 x：分辨率是「乘」的关系，
/// 而且在等宽不了的中文字体里 `×` 不会跟 `x` 混淆。
String? formatImageSize(Size? size) =>
    size == null ? null : '${size.width.round()}×${size.height.round()}';

/// 顶栏宽度至少这么大，才在芯片上写分辨率。
///
/// 取值依据是**顶栏其他控件的固定宽度之和**（返回键 + 版式胶囊组 + 下载 +
/// 自动滚屏 + 展开 + 全屏 + 设置 ≈ 600 逻辑像素）再加标题区的最低生存空间：
/// 低于这个宽度还硬塞，Row 就会溢出（黄黑斜纹），那是比「看不到分辨率」更糟的结果。
/// 窄屏不是丢掉这个信息 —— 它仍然在 tooltip 里。
const double superResolutionSizeMinWidth = 760;

/// 再宽一点才写「原图 → 超分后」的双向写法（多占 ~60 逻辑像素）。
const double superResolutionDeltaMinWidth = 900;

/// 顶栏宽度至少这么大，才在芯片上写**状态文字**（否则只留图标 + 开关）。
///
/// 这条比 [superResolutionSizeMinWidth] 低一档，但同样是硬账：窄档主行要把
/// 返回 / 版式 / 下载 / 滚屏 / 设置 / 更多 都摆下，芯片再写三个字书名就没了。
/// 状态没丢 —— 它在图标上，也在 tooltip 里。
const double superResolutionLabelMinWidth = 620;

/// 芯片上要不要写状态文字。
bool superResolutionShowsLabel(double availableWidth) =>
    availableWidth >= superResolutionLabelMinWidth;

/// 芯片上那串分辨率文字。
///
/// - 够宽（≥ [superResolutionDeltaMinWidth]）且两边尺寸都知道：`1200×1800 → 2400×3600`；
/// - 够宽（≥ [superResolutionSizeMinWidth]）：只报**超分后**的尺寸，没有就报原图尺寸；
/// - 更窄：`null`（交给 tooltip）。
///
/// 「有超分后尺寸就报它、没有才报原图」这个次序是刻意的：用户问的是**超分后**，
/// 原图尺寸只是它的对照面。
String? superResolutionSizeText(
  SuperResolutionPageStatus status,
  double availableWidth,
) {
  if (availableWidth < superResolutionSizeMinWidth) return null;
  final String? source = formatImageSize(status.sourceSize);
  final String? enhanced = formatImageSize(status.enhancedSize);
  final bool both = source != null && enhanced != null;
  if (both && availableWidth >= superResolutionDeltaMinWidth) {
    return '$source → $enhanced';
  }
  return enhanced ?? source;
}

/// 芯片的悬停说明。它是**唯一**在窄屏上也带着分辨率的入口。
String superResolutionTooltip(SuperResolutionPageStatus status) {
  final String page = status.pageNumber == null
      ? '当前页'
      : '第 ${status.pageNumber} 页';
  final String? source = formatImageSize(status.sourceSize);
  final String? enhanced = formatImageSize(status.enhancedSize);
  final String sizeHint = switch ((source, enhanced)) {
    (final String s, final String e) => '（原图 $s → 超分 $e）',
    (null, final String e) => '（超分后 $e）',
    (final String s, null) => '（原图 $s）',
    _ => '',
  };
  return switch (status.phase) {
    SuperResolutionPagePhase.unsupported => '当前平台不支持 GPU 纹理超分',
    SuperResolutionPagePhase.disabled => 'AI 超分已关闭，点右侧开关开启；点这里也能开启',
    SuperResolutionPagePhase.originalPreview => '正在对比原图，点这里切回超分图$sizeHint',
    SuperResolutionPagePhase.queued => '$page 已排队，等待超分$sizeHint',
    SuperResolutionPagePhase.running => '$page 超分中…$sizeHint',
    SuperResolutionPagePhase.ready => '$page 超分图已生成，等待上屏$sizeHint',
    SuperResolutionPagePhase.applied => '$page 已使用超分图$sizeHint，点这里对比原图',
    SuperResolutionPagePhase.skipped => '$page 已达分辨率阈值，无需超分$sizeHint',
    SuperResolutionPagePhase.failed => '$page 超分失败，继续显示原图$sizeHint',
    SuperResolutionPagePhase.idle => '$page 还没开始超分$sizeHint',
  };
}
