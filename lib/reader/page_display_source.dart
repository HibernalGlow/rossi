/// 一页的**显示来源** —— 叠层、超分、译文三件事争夺同一块像素时的唯一答案。
///
/// # 为什么要这么一张表
///
/// 查过代码：这条链上原本**没有**集中的裁决，四套账各自记（本地归属表
/// `GpuPresentController.translationOwnedPages`、在线覆盖表
/// `OnlineTranslatedPageTrack._overrides`、超分的 `_pagePhases`、翻译控制器的
/// `_phase`），互相之间只打了一个洞（译文占轨 → 超分让路）。所以「这一页用户
/// 实际看到什么」在代码里没有一处能问出来 —— 芯片各说各的，超分芯片甚至不知道
/// 译文占着这一页（`resolveSuperResolutionStatus` 的入参里没有译文这一维）。
///
/// 这张表只做一件事：把已经散在各处的事实收进来，出一个**赢家**。它不持有任何
/// 状态，所以可以逐格断言；谁该读它、什么时候读，是各调用点自己的事。
///
/// # 为什么「叠层」不是「译文」的同义词
///
/// 译文有两种上屏方式，它们与超分的关系**正相反**，混成一个概念就会写出错的优先级：
///
/// - [bakedPage]：擦字 + 画字烤成一张 PNG，注进增强图轨。它**占用了那一页唯一的像素**，
///   所以与超分互斥，且必须让超分让路（现状）。
/// - [overlayOnBase]：译文作为覆盖层画在底图上，不烤进像素。
///   设计上它**可以不占轨**（底 = 画面本来那张，超分照常），但今天占：
///   底必须是擦干净的字底，而「每框都采得出平色」在 8 页真页上是 0/121 框、0/8 页
///   （尺子在 `test/ocr/bubble_fill_real_page_probe_test.dart`），
///   于是每一页都得替自己占一次轨。等气泡级的框到位，这一格才谈得上与超分共存。
///
/// 但叠层有个硬前提，是渲染台量出来的（`test/ocr/translated_page_layer_overlay_bench_test.dart`）：
/// 把译文直接叠在**没擦字的原图**上，字压字率 0.085；叠在**擦字底图**上是 0.000。
/// 所以 [overlayOnBase] 的底只有两种来路：**每框都采到平色**（填色自己盖住原文，
/// 于是连擦字都不用跑），或者**擦字底图已经落盘**（`p<N>.base.png`）。
/// 两者都没有时这一格不许被选中 —— 宁可留在 [bakedPage]，
/// 也不端出一张日文与中文叠在一起的页。这是判据，不是待办。
///
/// 底由构建器报给控制器（`TranslatedPage.overlayNeedsBase`）。今天恒为 true：
/// 底只能是擦字底图，不占轨就没人把它换上屏，中文会压在日文下面（代价：这一页的超分让路）。
/// 「每框都能填色就不必擦、因此不必占轨」那一支还在代码里，但要等气泡级的框才可能触发。
enum PageDisplaySource {
  /// 原图。什么都没发生，或者所有后处理都失败了。
  original,

  /// 超分产物 —— 这一页的像素来自 `rossi_sr_cache` 里那张放大图。
  superResolved,

  /// 烘焙成品页（擦字 + 译文回填的一张 PNG），占用增强图轨。
  bakedPage,

  /// 译文覆盖层盖在一张可用的底上：这一层不烤进像素。
  /// 底换哪一张、要不要替这一页占增强图轨，由 `TranslatedPage.overlayNeedsBase` 说话
  /// （今天恒为「要擦字底图 ⇒ 占轨」，因为「每框都有填色」在真页上是 0/121 框）。
  overlayOnBase,

  /// 「对比原图」旁路开着：别的都算了，画面上就是原图。
  blockedByOriginalPreview,
}

/// 一页在某一时刻的全部事实。每一项都是**别处已经记着的东西**，这里只做汇总，
/// 所以字段全是可以直接问出来的，没有新增状态。
typedef PageDisplayFacts = ({
  /// 这一页是否被烘焙成品页占用（本地归属表 / 在线覆盖表里有它）。
  bool hasBakedPage,

  /// 这一页有没有可用的图层 JSON（叠层的数据前提）。
  bool hasTranslationLayer,

  /// 这一页有没有可用的**叠层底**。
  ///
  /// 两种都算有：① 每一框都采到了平色 ⇒ 填色自己盖住原文，**不需要**擦字底图，
  /// 于是这一页根本不会有 `p<N>.base.png`（判成「没有底」就会把最省时间的那条路
  /// 判成不可用，每次上屏重跑一遍 OCR）；② 有框采不出平色 ⇒ 必须有擦字底图在盘上。
  /// 这正是 `TranslatedPageCache.overlayDisplayable` 那一条判据的另一半，
  /// 两边口径必须一致。
  ///
  /// 与 [hasTranslationLayer] 分开而不是合并：图层是数据、底是像素，
  /// 「图层在但底不可用」与「底在但图层解坏了」是两种不同的回落。
  bool hasOverlayBase,

  /// 这一页有没有超分产物（在盘上或已注入）。
  bool hasSuperResolution,

  /// 用户选的译文上屏方式。
  TranslatedPageDisplayChoice translationChoice,

  /// 「对比原图」旁路。它按设计屏蔽整条增强图轨。
  bool bypassesEnhancedTrack,

  /// 超分功能本身开着吗。
  bool upscaleEnabled,
});

/// 用户对译文上屏方式的选择。**默认 [baked]** 是判据不是保守：叠层这一档还没过真机
/// 那一关（验收 §9c 九条，其中第 1 条已按 0/121 的量数改了口径），而烘焙档已经真机走过一轮。
/// §9c 跑完之后这一行就该重新判一次 —— 判据要跟着证据走，别把默认值当立场守着。
enum TranslatedPageDisplayChoice { baked, overlay }

/// 谁赢。纯函数，所以每一格都能被测试钉住。
///
/// 优先级次序是**先问画面事实，再问用户偏好**：
/// 1. 旁路 > 一切 —— 它屏蔽的是最终那一帧，任何「其实已经算好了」都不能当证据
///    （这条是本仓在 `blockedByOriginalPreview` 那一格里栽过的同一个坑：
///    把「被挡住」说成「已显示」就是谎报画面）。
/// 2. 译文 > 超分 —— 用户按「译」是要读译文；叠层可用的时候用叠层（它不占轨，
///    于是超分照样生效，两条需求一起满足），不可用就退回烘焙。
/// 3. 超分 > 原图。
PageDisplaySource resolvePageDisplaySource(PageDisplayFacts f) {
  if (f.bypassesEnhancedTrack)
    return PageDisplaySource.blockedByOriginalPreview;

  final wantsOverlay =
      f.translationChoice == TranslatedPageDisplayChoice.overlay;
  if (f.hasBakedPage) return PageDisplaySource.bakedPage;
  if (wantsOverlay && f.hasTranslationLayer && f.hasOverlayBase) {
    return PageDisplaySource.overlayOnBase;
  }
  if (f.upscaleEnabled && f.hasSuperResolution) {
    return PageDisplaySource.superResolved;
  }
  return PageDisplaySource.original;
}
