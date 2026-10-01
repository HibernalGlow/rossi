import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zephyr/service/ocr/ocr_models.dart';
import 'package:zephyr/src/rust/api/ocr.dart';
import 'package:zephyr/util/get_path.dart';

/// 模型没就绪时抛这个 —— 调用方据此弹「去下载」而不是把一个看不懂的 Rust 错误直接抛给用户。
class OcrModelsMissing implements Exception {
  OcrModelsMissing(this.missing, {this.needsInpaint = false});

  final List<String> missing;
  final bool needsInpaint;

  @override
  String toString() =>
      'OCR 模型未就绪：缺少 ${missing.join('、')}'
      '${needsInpaint ? '（成品页还需要擦字件）' : ''}';
}

/// OCR 链路的 Dart 侧门面：解析模型路径 → 过桥调 Rust → 把结果交回上层。
///
/// 它**不做翻译**（那是 `WindHttp` 到 OpenAI-compatible / Ollama 的事）、也不画字
/// （译文绘制复用 Flutter 的 CJK 整形）—— 见 ADR-0018 §决定 3 与 §决定 7。
class OcrService {
  OcrService._();

  static final OcrService instance = OcrService._();

  /// 每页产物缓存目录（成品页写在 `manga_translated/<key>/`，**key 的计算在缓存那一层**，
  /// 这里只提供根目录）。
  static Future<Directory> outputRoot() async =>
      Directory(p.join(await getFilePath(), 'manga_translated'));

  /// 这一进程里**是否真的过桥建过会话**。Rust 侧的会话缓存是跨页复用的（`ocr_sessions`），
  /// 三个会话常驻约 670 MB，所以退出阅读器时必须交还；但没建过就没有可交的东西 ——
  /// 少这一句会让「从没翻过译文页」的每次退出都白过一次桥，也让不带原生库的
  /// 状态机单测直接崩在 `RustLib.instance` 未初始化上。
  bool _sessionsHeld = false;

  /// 交还 Rust 侧的三个模型会话（约 670 MB）。**只在真的建过会话时过桥**。
  ///
  /// 谁来调：`LocalReadSession.dispose()`。换章不调 —— 人还在阅读、下一张多半还要译，
  /// 那一页省下的 2 s 是应得的。代价是退出后第一次建页要重新加载权重。
  void releaseSessions() {
    if (!_sessionsHeld) return;
    _sessionsHeld = false;
    ocrReleaseSessions();
  }

  /// 分析一页：检测 → 识别 → 聚块（→ 可选擦字）。
  ///
  /// [ep] 默认 `auto` = 交给 Rust 侧按「平台 + 哪一段」选（Windows 上识别与擦字走 DirectML、
  /// 检测走 CPU；其余走 CPU）。ADR-0018 §决定 3.1 的实测：CoreML 对这几个模型全都更慢，
  /// 而 DirectML 只赢在识别与擦字上 —— 单一 EP 在哪个平台都不是最优解。
  /// [erasedOutput] 给了就把擦干净的底图写在那里（做成品页时给）。
  Future<OcrPageResult> analyzePage({
    required String imagePath,
    bool inpaint = false,
    String? erasedOutput,
    String ep = 'auto',
    int? maxNewTokens,
  }) async {
    final missing = <String>[];
    if (!await OcrModels.recognizeReady()) {
      missing.addAll(await _missingRecognize());
    }
    if (inpaint && !await OcrModels.inpaintReady()) {
      missing.add(OcrModels.inpaintFile);
    }
    if (missing.isNotEmpty) {
      throw OcrModelsMissing(missing, needsInpaint: inpaint);
    }
    if (inpaint && erasedOutput == null) {
      throw ArgumentError('inpaint: true 时必须给 erasedOutput');
    }

    _sessionsHeld = true;
    return ocrAnalyzePage(
      imagePath: imagePath,
      models: OcrModelPaths(
        det: await OcrModels.pathOf(OcrModels.detFile),
        encoder: await OcrModels.pathOf(OcrModels.encoderFile),
        decoder: await OcrModels.pathOf(OcrModels.decoderFile),
        vocab: await OcrModels.pathOf(OcrModels.vocabFile),
      ),
      ep: ep,
      inpaintModel: inpaint
          ? await OcrModels.pathOf(OcrModels.inpaintFile)
          : null,
      erasedOutput: erasedOutput,
      maxNewTokens: maxNewTokens,
    );
  }

  Future<List<String>> _missingRecognize() async {
    final (_, missing) = await OcrModels.status();
    return missing
        .where((f) => f != OcrModels.inpaintFile)
        .toList(growable: false);
  }
}
