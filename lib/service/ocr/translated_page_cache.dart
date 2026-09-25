import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/service/ocr/ocr_models.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/ocr_service.dart';

/// 成品页缓存的 key 口径（ADR-0018 §决定 3）。
///
/// 目录名是**可读标签 + 短哈希**：`<语言>_<模型>_<8位哈希>`，而完整输入清单写在同目录的
/// `manifest.json` 里 —— 只放哈希会让人查不出「为什么这页失效了」，只放可读名字又会撞名。
///
/// **哈希必须覆盖每一项影响产物的输入**：目标语言、端点、模型名、术语表内容、
/// 各权重的版本、字体版本、排版参数版本。少一项就会出「换了模型页面还是旧的」这种静默错。
class TranslatedPageCache {
  TranslatedPageCache._();

  static const _minPngBytes = 1024;
  static const _pngSignature = <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];
  static const _iendTail = <int>[
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ];

  /// 排版参数版本：改字号策略 / 边距 / 换行规则就 +1，让旧产物失效。
  static const layoutVersion = 1;

  /// 字体版本：换字体或换字重都要改（与 `pubspec.yaml` 里的 family 对应）。
  static const fontVersion = 'wenkai-lite-1.522';

  /// `fingerprint`：完整输入清单（要写进 manifest.json 的）；
  /// `label`：目录名里那段可读标签。
  static Future<({String fingerprint, String label})> describe({
    required OcrTranslationConfig config,
    String? modelTag,
  }) async {
    final tag = modelTag ?? await OcrModels.versionTag();
    final entries = <String, String>{
      'targetLanguage': config.targetLanguage,
      'endpointHost': Uri.parse(config.baseUrl).host,
      'model': config.model,
      'glossarySha1': sha1
          .convert(utf8.encode(config.glossary))
          .toString()
          .substring(0, 8),
      'models': tag,
      'font': fontVersion,
      'layout': '$layoutVersion',
    };
    final fingerprint = entries.entries
        .map((e) => '${e.key}=${e.value}')
        .join('|');
    final hash = sha1
        .convert(utf8.encode(fingerprint))
        .toString()
        .substring(0, 8);
    String safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    final label = '${safe(config.targetLanguage)}_${safe(config.model)}_$hash';
    return (fingerprint: fingerprint, label: label);
  }

  static Future<Directory> directory(String label) async =>
      Directory(p.join((await OcrService.outputRoot()).path, label));

  /// 某页的成品文件。`pageIndex` 用 0 基下标，与 Reader 的页序一致。
  static Future<File> pageFile({
    required String label,
    required int pageIndex,
  }) async => File(p.join((await directory(label)).path, 'p$pageIndex.png'));

  /// 这张成品页**能不能用**。
  ///
  /// 不是 `exists()`：ADR-0018 §决定 3 要求「产物缺失或损坏时静默回落到原图」，
  /// 而 `exists()` 把「存在」当成了「可用」—— 半张 PNG（目录被清过、磁盘满过）
  /// 会被当成可用交下去，最后表现为呈现器拒绝注入并报错给用户。
  /// 判据挑能廉价看出损坏的两端：PNG 签名 + 结尾的 `IEND` 块（截断的尾巴一定缺），
  /// 再加一个体积下限。不做整图解码 —— 命中缓存这条路本来就该是零成本。
  static Future<bool> isUsable({
    required String label,
    required int pageIndex,
  }) async {
    final f = await pageFile(label: label, pageIndex: pageIndex);
    if (!await f.exists()) return false;
    if (await f.length() < _minPngBytes) return false;
    final raf = await f.open();
    try {
      final head = Uint8List(8);
      await raf.readInto(head, 0, 8);
      for (var i = 0; i < 8; i++) {
        if (head[i] != _pngSignature[i]) return false;
      }
      final tail = Uint8List(8);
      await raf.setPosition(await f.length() - 8);
      await raf.readInto(tail, 0, 8);
      // 结尾 8 字节是确定的：IEND 长度 00000000 + 类型 + CRC 0xAE426082。
      for (var i = 0; i < 8; i++) {
        if (tail[i] != _iendTail[i]) return false;
      }
      return true;
    } finally {
      await raf.close();
    }
  }

  /// 原子写：先写 `.tmp_<pid>` 再改名 —— 半张 PNG 比没有更糟（Reader 会当它可用）。
  static Future<void> write({
    required String label,
    required int pageIndex,
    required Uint8List pngBytes,
    String? fingerprint,
  }) async {
    final dir = await directory(label);
    await dir.create(recursive: true);
    final target = await pageFile(label: label, pageIndex: pageIndex);
    final tmp = File('${target.path}.tmp_$pid');
    await tmp.writeAsBytes(pngBytes, flush: true);
    await tmp.rename(target.path);
    if (fingerprint != null) {
      final manifest = File(p.join(dir.path, 'manifest.json'));
      final existing = await manifest.exists()
          ? jsonDecode(await manifest.readAsString()) as Map<String, dynamic>
          : <String, dynamic>{};
      existing['fingerprint'] = fingerprint;
      existing['writtenAt'] = DateTime.now().toIso8601String();
      await manifest.writeAsString(
        const JsonEncoder.withIndent('  ').convert(existing),
      );
    }
  }

  /// 已生成的成品页数：设置页用它显示「已生成 N 张」，也决定「清空」要不要亮着。
  static Future<int> pageCount() async {
    final root = await OcrService.outputRoot();
    if (!await root.exists()) return 0;
    var count = 0;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File && e.path.endsWith('.png')) count++;
    }
    return count;
  }

  /// 清掉所有成品页（换模型 / 换字体后用户手点「重来」时用）。
  static Future<void> clearAll() async {
    final root = await OcrService.outputRoot();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
