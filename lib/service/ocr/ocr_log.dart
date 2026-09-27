import 'package:path/path.dart' as p;
import 'package:zephyr/service/diagnostics/app_log.dart';
import 'package:zephyr/service/ocr/ocr_models.dart';

/// 漫画翻译（成品页）链路的诊断日志。机制在 [AppLog]（与超分共用），
/// 这里只留「叫什么、写到哪」。
///
/// 为什么需要它：整页链路要过六道关（权重 → 端点 → 过桥推理 → 翻译请求 → 回填排版 →
/// 落盘注入），任何一道错了，界面上都只是芯片那一句「译文失败」。
/// 用户 2026-09-27 的原话是「有问题翻译没有日志，我也不知道情况如何」。
///
/// 落点刻意选在**权重目录**（`manga_ocr/ocr.log`）而不是成品页缓存目录：
/// 「清空成品页缓存」会把 `manga_translated/` 整个删掉，而那正是最需要回头翻日志的时刻。
/// 也不能落系统临时目录 —— 这台机器的 dirhelper 每天 03:35 清 tmp
/// （见 `docs/ocr-completed-page-acceptance.md` 的「落盘纪律」）。
abstract final class OcrLog {
  static final AppLog log = AppLog(
    name: '漫画翻译',
    filePath: () async => p.join((await OcrModels.directory()).path, 'ocr.log'),
  );

  static void add(String message, {Object? error, StackTrace? stackTrace}) =>
      log.add(message, error: error, stackTrace: stackTrace);

  static Future<void> flush() => log.flush();

  /// 页号在日志里一律按**人看的 1 基**写 —— 界面显示「第 5 页」而日志写「第 4 页」，
  /// 对不上的那一次一定会被当成「日志没记这一页」。
  static String page(int index) => '第 ${index + 1} 页';
}
