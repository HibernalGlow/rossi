import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zephyr/util/get_path.dart';

/// OCR 模型的落位与就绪判断。
///
/// 权重**不随包**（ADR-0018 §决定 5：体积装不下、且部分权重条款是灰色的），首下到
/// `getFilePath()/manga_ocr/` —— 与 `super_resolution/` **同级但独立**：那边是「整目录删」的
/// 清理语义（`real_sr_super_resolution.dart:71`），共用目录会连带废掉另一条引擎。
///
/// 字体是另一回事：文楷是 OFL、随包（见 ADR-0018 §决定 5），不在这里管。
class OcrModels {
  OcrModels._();

  static const detFile = 'ch_PP-OCRv4_det_infer.onnx';
  static const encoderFile = 'encoder_model.onnx';
  static const decoderFile = 'decoder_model.onnx';
  static const vocabFile = 'vocab.txt';
  static const inpaintFile = 'lama-manga-dynamic.onnx';

  static const _hfOcr = 'https://huggingface.co/mayocream/manga-ocr-onnx/resolve/main';
  static const detUrl =
      'https://huggingface.co/breezedeus/cnstd-ppocr-ch_PP-OCRv4_det/resolve/main/$detFile';
  static const encoderUrl = '$_hfOcr/$encoderFile';
  static const decoderUrl = '$_hfOcr/$decoderFile';
  static const vocabUrl = '$_hfOcr/$vocabFile';
  static const inpaintUrl =
      'https://huggingface.co/ogkalu/lama-manga-onnx-dynamic/resolve/main/$inpaintFile';

  /// 体积下限，用来挡「HTML 错误页 / Git-LFS 指针被存成了模型」。
  /// 数值取实测体积的下限（`REFERENCE_RESEARCH.md` §8.6.1），不是精确校验。
  static const _minBytes = <String, int>{
    detFile: 4 * 1000 * 1000,
    encoderFile: 300 * 1000 * 1000,
    decoderFile: 100 * 1000 * 1000,
    vocabFile: 20 * 1000,
    inpaintFile: 180 * 1000 * 1000,
  };

  static Future<Directory> directory() async =>
      Directory(p.join(await getFilePath(), 'manga_ocr'));

  static Future<String> pathOf(String file) async =>
      p.join((await directory()).path, file);

  /// 识别链路（检测 + 识别 + 词表）是否齐备。缺哪一个都跑不了 `ocr_analyze_page`。
  static Future<bool> recognizeReady() async {
    for (final f in [detFile, encoderFile, decoderFile, vocabFile]) {
      if (!await _valid(f)) return false;
    }
    return true;
  }

  /// 擦字件是否齐备。**只有做成品页才需要它**；只做识别时可以缺。
  static Future<bool> inpaintReady() => _valid(inpaintFile);

  /// 已就绪的文件清单 + 缺失体积，给设置页显示（「下载了 460 MB / 共 660 MB」这种）。
  static Future<(List<String> ready, List<String> missing)> status() async {
    final ready = <String>[];
    final missing = <String>[];
    for (final f in [detFile, encoderFile, decoderFile, vocabFile, inpaintFile]) {
      (await _valid(f) ? ready : missing).add(f);
    }
    return (ready, missing);
  }

  /// 权重版本标签：用**文件长度**当版本代理 —— 换权重几乎必然改长度，而对 460 MB
  /// 每页都算一次哈希不可接受。它进成品页缓存指纹（`TranslatedPageCache.describe`），
  /// 所以「换了模型但页面还是旧的」这种静默错不会发生。缺文件的项记 0，便于一眼看出没下全。
  static Future<String> versionTag() async {
    const short = {
      detFile: 'det',
      encoderFile: 'enc',
      decoderFile: 'dec',
      vocabFile: 'voc',
      inpaintFile: 'lama',
    };
    final parts = <String>[];
    for (final f in short.keys) {
      final file = File(await pathOf(f));
      final len = await file.exists() ? await file.length() : 0;
      parts.add('${short[f]}$len');
    }
    return parts.join('-');
  }

  static Future<bool> _valid(String file) async {
    final f = File(await pathOf(file));
    if (!await f.exists()) return false;
    final min = _minBytes[file] ?? 1024;
    return await f.length() >= min;
  }
}
