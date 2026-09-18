import 'dart:io';

import 'package:path/path.dart' as p;

/// mImageViewer 的 ONNX 模型清单。倍率由模型本身决定，所有超分模型均为原生 4x。
enum MImageOnnxModel {
  realCugan4x('realcugan_4x', '漫画（Real-CUGAN 4x）', 'realcugan_4x_conservative.onnx'),
  anime6b('realesrgan_anime6b', '插画/动画（Real-ESRGAN Anime 6B 4x）', 'realesrgan_x4plus_anime_6b.onnx'),
  realesrgan('realesrgan_x4plus', '照片/CG（Real-ESRGAN 4x）', 'realesrgan_x4plus.onnx'),
  general('realesr_general_v3', '高速通用（Real-ESR General 4x）', 'realesr_general_x4v3.onnx'),
  siax('nmkd_siax_4x', '照片质感（NMKD Siax 4x）', '4x_NMKD-Siax_200k.onnx');

  const MImageOnnxModel(this.id, this.label, this.fileName);
  final String id;
  final String label;
  final String fileName;
  int get scale => 4;
  bool get supportsDenoise => this == MImageOnnxModel.realCugan4x;
}

abstract final class MImageOnnxModelConfig {
  static const baseUrl = 'https://github.com/MikageSawatari/mimageviewer/raw/HEAD/models';
  static MImageOnnxModel get defaultModel => MImageOnnxModel.realCugan4x;
  static MImageOnnxModel? byId(String? id) {
    for (final model in MImageOnnxModel.values) { if (model.id == id) return model; }
    return null;
  }
  static Future<String> path(Directory root, MImageOnnxModel model) async {
    final file = File(p.join(root.path, model.fileName));
    if (!file.existsSync() || await file.length() < 1024) {
      throw StateError('缺少 mImage ONNX 模型 ${model.fileName}，请在设置中下载');
    }
    return file.path;
  }
}
