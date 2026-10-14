import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zephyr/i18n/strings.g.dart';

/// mImageViewer 的 ONNX 模型清单。倍率由模型本身决定，所有超分模型均为原生 4x。
enum MImageOnnxModel {
  realCugan4x('realcugan_4x', 'realcugan_4x_conservative.onnx'),
  anime6b('realesrgan_anime6b', 'realesrgan_x4plus_anime_6b.onnx'),
  realesrgan('realesrgan_x4plus', 'realesrgan_x4plus.onnx'),
  general('realesr_general_v3', 'realesr_general_x4v3.onnx');

  const MImageOnnxModel(this.id, this.fileName);
  final String id;
  final String fileName;

  String get label => switch (this) {
    MImageOnnxModel.realCugan4x => t.realSr.modelComic,
    MImageOnnxModel.anime6b => t.realSr.modelAnime,
    MImageOnnxModel.realesrgan => t.realSr.modelPhoto,
    MImageOnnxModel.general => t.realSr.modelFast,
  };
  int get scale => 4;
  bool get supportsDenoise => this == MImageOnnxModel.realCugan4x;
}

abstract final class MImageOnnxModelConfig {
  static const baseUrl =
      'https://github.com/MikageSawatari/mimageviewer/raw/HEAD/models';
  static const denoiseModelId = 'denoise_realplksr';
  static const denoiseFileName = 'dejpg_realplksr_otf.onnx';
  static MImageOnnxModel get defaultModel => MImageOnnxModel.realCugan4x;
  static MImageOnnxModel? byId(String? id) {
    for (final model in MImageOnnxModel.values) {
      if (model.id == id) return model;
    }
    return null;
  }

  static Future<String> path(Directory root, MImageOnnxModel model) async {
    return pathForFile(root, model.fileName);
  }

  static Future<String> denoisePath(Directory root) =>
      pathForFile(root, denoiseFileName);

  static Future<String> pathForFile(Directory root, String fileName) async {
    final file = File(p.join(root.path, fileName));
    if (!file.existsSync() || await file.length() < 1024) {
      throw StateError(t.realSr.missingOnnxDownload(file: fileName));
    }
    return file.path;
  }
}
