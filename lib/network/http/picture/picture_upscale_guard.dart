import 'package:zephyr/main.dart';
import 'package:zephyr/page/setting/real_sr/service/online_image_processing.dart';

/// 另存一次降噪 / 超分结果，失败**不往上抛**，让调用方交出已经落盘的原图。
///
/// `getCachePicture` 原来四个超分点里只有缓存命中那两个包了 `try/catch`，新下载的两个
/// 没包：超分一抛（安卓那条链路是明确 `rethrow` 的 —— 见 `real_sr_super_resolution.dart`
/// 里「Android 超分/WebP 转换失败」那一支），图片字节明明已经下载并保存成功，整页还是判
/// 失败；而缓存命中那侧的 catch 又把**好端端的缓存文件删掉重下**，下一轮再撞同一个异常，
/// 于是这张图永远出不来。
///
/// 吞掉这里的异常是安全的：那两个 `try` 里唯一会抛的就是超分本身。文件在不在、空不空
/// 都在 `DownloadAssetStore.findExistingDownload()`（不合格返回 null）和
/// `findCanonicalCache()`（自己抛 `StateError`）里判完了，而它们的调用点都在 `try`
/// **外面** —— 也就是说那条「损坏 → 删掉重下」的恢复路径本来就够不到损坏。
Future<void> upscaleOrKeepOriginal(String path, {String? bookKey}) async {
  try {
    await OnlineImageProcessing.process(path, bookKey: bookKey);
  } catch (e, s) {
    logger.w('图像增强失败，继续显示原图: $path', error: e, stackTrace: s);
  }
}

/// 后台待办上限（排队 + 在跑的总数）。
///
/// 为什么可以有界：文件保持未超分是**可重入**的 —— 下次显示这张图还会再排一次，
/// 所以丢掉只是「这一轮不变清晰」，不会丢功能。不设界的话，快速刷一条漫（条漫
/// 一屏就挂好几页、ListView 还会预建）会把待办堆到几百页，池子永远在替没人看的
/// 页面干活。
///
/// 12 的口径：池子并发 2、一页实测 6–22 s ⇒ 12 条 ≈ 40–130 s 的后台量，
/// 够「跟着阅读位置走」，再多就已经是积压而不是预取了。
const int maxPendingUpscales = 12;

int _pendingUpscales = 0;

/// 后台另存一次降噪 / 超分结果，**不阻塞调用方**。
///
/// 阅读器的显示路径只能交已经落盘的原图：这台机器上一页超分实测 6–22 s，而打开
/// 一本书时当前页 + 预取会一起排队，等到超分完成才显示就是「图片加载不出来」。
/// 处理完成后 `EnhancedOnlinePage` 切换到独立缓存文件；原图仍用于 OCR 和对比。
///
/// 同一源版本与参数不会重复推理（去重在派生图片缓存的在飞表里）；
/// 失败不抛（[upscaleOrKeepOriginal] 已吞）。
Future<void> upscaleInBackground(String path, {String? bookKey}) async {
  if (_pendingUpscales >= maxPendingUpscales) {
    logger.d('超分后台待办已满（$maxPendingUpscales），本页本轮不排队: $path');
    return;
  }
  _pendingUpscales++;
  try {
    await upscaleOrKeepOriginal(path, bookKey: bookKey);
  } finally {
    _pendingUpscales--;
  }
}
