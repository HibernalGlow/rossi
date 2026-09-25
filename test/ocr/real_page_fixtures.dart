/// 真权重 / 真页测试夹具的**唯一**查找口径。
///
/// 为什么要抽出来：这几条路径原本在两个真实数据测试里各抄了一份，而它们决定的是
/// 「这条验证到底跑没跑」。同一个仓里已经吃过一次亏 —— 查找逻辑分叉之后，
/// 一边跑的是真权重，另一边静默 skip，看上去都是绿的。
///
/// 查找顺序（前者命中即用）：
/// 1. 环境变量 `ROSSI_OCR_MODELS_DIR` / `ROSSI_OCR_TEST_PAGES_DIR`（CI 或临时换目录）；
/// 2. `<仓根>/.local/ocr-test-data/`（**持久区**，已 gitignore，不入库）；
/// 3. `/tmp/inpaint-lab`、`/tmp/detect-lab`（本机早期探测留下的那份）。
///
/// 第 2 优先于第 3 是刻意的：`$TMPDIR` 会被 macOS 的 dirhelper 每天 03:35 扫一次，
/// 夹具被扫走之后这些测试会从「跑」静默变成「skip」，而文档里写着它们跑过。
library;

import 'dart:io';

import 'package:zephyr/service/ocr/ocr_models.dart';

/// 权重文件名 → 上游文件名。键是 `OcrModels.*File`，值是本地要找到的名字。
const Map<String, String> realModelFiles = {
  OcrModels.detFile: 'ch_PP-OCRv4_det_infer.onnx',
  OcrModels.encoderFile: 'encoder_model.onnx',
  OcrModels.decoderFile: 'decoder_model.onnx',
  OcrModels.vocabFile: 'vocab.txt',
  OcrModels.inpaintFile: 'lama-manga-dynamic.onnx',
};

/// 候选权重目录，按优先级。
List<Directory> realModelDirs() {
  final env = Platform.environment['ROSSI_OCR_MODELS_DIR'];
  return [
    if (env != null && env.isNotEmpty) Directory(env),
    Directory('$_fixtureRoot/models'),
    Directory('/tmp/inpaint-lab/models'),
    Directory('/tmp/detect-lab/models'),
  ];
}

/// 候选真页目录，按优先级。
List<Directory> realPagesDirs() {
  final env = Platform.environment['ROSSI_OCR_TEST_PAGES_DIR'];
  return [
    if (env != null && env.isNotEmpty) Directory(env),
    Directory('$_fixtureRoot/pages'),
    Directory('/tmp/detect-lab/pages'),
  ];
}

/// 找到的真页，按文件名排序；一个都没有时返回空表（调用方负责把「没有」说清楚）。
List<String> realPages() {
  for (final dir in realPagesDirs()) {
    if (!dir.existsSync()) continue;
    final pages =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.jpg') || f.path.endsWith('.png'))
            .map((f) => f.path)
            .toList()
          ..sort();
    if (pages.isNotEmpty) return pages;
  }
  return const [];
}

/// 把找到的权重**符号链接**进 `getFilePath()/manga_ocr/`，返回缺哪些。
///
/// 用符号链接而不是拷贝：识别件 343 MB、擦字件 206 MB，拷一份只为跑测试没必要。
/// 链接进生产路径是有意的 —— 这样 `OcrModels` 的就绪检查、路径解析、体积下限
/// 走的都是用户那一条码路，测试才不会验一个生产上不存在的环境。
Future<List<String>> linkRealWeights() async {
  final missing = <String>[];
  for (final entry in realModelFiles.entries) {
    final found = realModelDirs()
        .map((d) => File('${d.path}/${entry.value}'))
        .firstWhere((f) => f.existsSync(), orElse: () => File(''));
    if (found.path.isEmpty) {
      missing.add(entry.value);
      continue;
    }
    _linkInto(await OcrModels.pathOf(entry.key), found.path);
  }
  return missing;
}

/// `flutter test` 的工作目录就是仓根（见 AGENTS.md 的跑测方式）。
String get _fixtureRoot => '${Directory.current.path}/.local/ocr-test-data';

void _linkInto(String linkPath, String targetPath) {
  if (!File(targetPath).existsSync()) return;
  final f = File(linkPath);
  Directory(f.parent.path).createSync(recursive: true);
  final link = Link(f.path);
  if (link.existsSync()) {
    link.deleteSync();
  } else if (f.existsSync()) {
    f.deleteSync();
  }
  link.createSync(targetPath);
}
