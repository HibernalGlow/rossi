import 'package:zephyr/main.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';

/// 跑一次「超分 + WebP 转换」，失败**不往上抛**，让调用方交出已经落盘的原图。
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
    await RealSrSuperResolution.upscaleAndConvertToWebp(path, bookKey: bookKey);
  } catch (e, s) {
    logger.w('超分失败，改用未超分的原图: $path', error: e, stackTrace: s);
  }
}
