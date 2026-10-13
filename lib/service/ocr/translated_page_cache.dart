import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/service/ocr/ocr_models.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/ocr_service.dart';
import 'package:zephyr/service/ocr/translated_page_layer.dart';

/// 成品页缓存的 key 口径（ADR-0018 §决定 3）。
///
/// 目录名是**可读标签 + 短哈希**：`<语言>_<模型>_<8位哈希>`，而完整输入清单写在同目录的
/// `manifest.json` 里 —— 只放哈希会让人查不出「为什么这页失效了」，只放可读名字又会撞名。
///
/// **哈希必须覆盖每一项影响产物的输入**：翻译引擎、目标语言、端点、模型名、术语表内容、
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

  /// 老版本「降级档（擦字 + 原文回填）」的目录名。这条档已经没了 —— 翻译那一跳失败时
  /// 整页按失败处理、画面留原图 —— 但**用户盘上那张还在**，所以计数得继续避开它：
  /// 把没翻译的页报成「已生成 N 张」正是这个缓存最不该撒的谎。
  /// `clearAll` 删的是整个根目录，那些孤儿文件自然跟着走。
  static const _legacyDegradedDirName = 'manga_translated_degraded';

  /// 字体版本：换字体或换字重都要改（与 `pubspec.yaml` 里的 family 对应）。
  static const fontVersion = 'wenkai-lite-1.522';

  /// `fingerprint`：完整输入清单（要写进 manifest.json 的）；
  /// `label`：目录名里那段可读标签。
  ///
  /// **每一项都必须是「换了它，译文就会不一样」的东西，而且不多不少**：
  /// 少了 → 切了引擎/改了术语表却继续端出旧译文，且没人知道自己在看旧的（本 ADR 一路在防的静默陈旧）；
  /// 多了 → 无关改动把整本书的成品页白白作废。
  ///
  /// 所以 `engine` 必须在里面；而 `glossarySha1` **只在端点那一档才算** ——
  /// 端侧那条路没有术语表接口，让它去失效一份「本来就没用术语表」的产物就是多算。
  ///
  /// 唯一例外是 `scope`（[OcrTranslationConfig.cacheScope]）：它不改变译文内容，
  /// 改变的是「这张产物属于哪一本书的哪一章」。没有它，这份表就退化成
  /// 「按页号查表」，不同书的同号页会互相命中 —— 那是比静默陈旧更糟的一种错：
  /// 端出来的画面压根是另一本书。
  static Future<({String fingerprint, String label})> describe({
    required OcrTranslationConfig config,
    String? modelTag,
  }) async {
    final tag = modelTag ?? await OcrModels.versionTag();
    // 「有没有端点」与「术语表是否生效」是**两个问题**，别合成一个布尔：
    // 端点与混元都有 baseUrl/model，但只有混元用原生术语块；将来加「Apple + 输出端替换」
    // 那一档时这两项又会分叉。各写各的，才不用在加第四档时猜哪个条件该跟着变。
    final hasEndpoint = config.engine.requiresEndpoint;
    // 端侧那一档没有 model，目录名要有个人能看懂的东西，别留一个空段。
    final modelLabel = config.model.isEmpty ? config.engine.id : config.model;
    // 源身份：**给了才进指纹，没给时这一项整个不存在**。
    // 写成条件项而不是 `'scope': config.cacheScope ?? '-'`，是为了让没接这条链的
    // 调用方（本地档、冒烟页、既有测试）算出来的指纹与目录名跟改造前逐字节相同 ——
    // 否则这一改动会把用户盘上所有成品页一次性判死，而它们并没有错。
    // 理由与 `glossarySha1` 只在端点档才算同型：多算一项等于白白作废。
    final scope = config.cacheScope;
    final entries = <String, String>{
      'engine': config.engine.id,
      'targetLanguage': config.targetLanguage,
      'endpointHost': hasEndpoint ? Uri.parse(config.baseUrl).host : '-',
      'model': modelLabel,
      'glossarySha1': config.engine.glossaryApplies
          ? sha1
                .convert(utf8.encode(config.glossary))
                .toString()
                .substring(0, 8)
          : '-',
      'models': tag,
      'font': fontVersion,
      'layout': '$layoutVersion',
      if (scope != null && scope.isNotEmpty) 'scope': scope,
    };
    final fingerprint = entries.entries
        .map((e) => '${e.key}=${e.value}')
        .join('|');
    final hash = sha1
        .convert(utf8.encode(fingerprint))
        .toString()
        .substring(0, 8);
    String safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    final label = '${safe(config.targetLanguage)}_${safe(modelLabel)}_$hash';
    return (fingerprint: fingerprint, label: label);
  }

  static Future<Directory> directory(String label) async =>
      Directory(p.join((await OcrService.outputRoot()).path, label));

  /// 某页的成品文件。`pageIndex` 用 0 基下标，与 Reader 的页序一致。
  static Future<File> pageFile({
    required String label,
    required int pageIndex,
  }) async => File(p.join((await directory(label)).path, 'p$pageIndex.png'));

  /// 某页的**图层**文件（ADR-0018 §决定 4 解冻出来的那份可重复合成描述）。
  ///
  /// 与成品页同目录、同页号、同一个指纹档，只换扩展名：这两份东西**必须是同一批
  /// 配置的产物**，分目录就会让「PNG 是新档、JSON 是旧档」这种错配有可能发生。
  /// 叠层模式按它重新合成，于是换超分档 / 改译文 / 换显示模式都不必重跑 OCR。
  static Future<File> layerFile({
    required String label,
    required int pageIndex,
  }) async => File(p.join((await directory(label)).path, 'p$pageIndex.json'));

  /// 某页的**擦字底图** —— 叠层的像素前提。
  ///
  /// 为什么非要它，而不是直接拿原图当底：渲染台实测「译文叠在没擦字的原图上」
  /// 字压字率 0.085，叠在擦字底上是 0.000。缺它就等于把中文画在日文上，
  /// 所以 [resolvePageDisplaySource] 在它缺席时**不许**选叠层那一格。
  ///
  /// 为什么落进缓存目录而不是留在临时目录：底图只在 `scratch` 里活到函数结束的话，
  /// 叠层每次上屏都要重跑擦字（实测整页最贵的一段 4–6 s），而且本机 dirhelper
  /// 每天 03:35 扫 tmp —— 本仓在权重落盘与老降级页上吃过同一口同型的亏。
  static Future<File> baseFile({
    required String label,
    required int pageIndex,
  }) async =>
      File(p.join((await directory(label)).path, 'p$pageIndex.base.png'));

  /// 把刚擦好的底图收进缓存目录（沿用成品页那套原子写：半张 PNG 比没有更糟）。
  static Future<void> writeBase({
    required String label,
    required int pageIndex,
    required File erasedFile,
  }) async {
    final dir = await directory(label);
    await dir.create(recursive: true);
    await _writeAtomically(
      await baseFile(label: label, pageIndex: pageIndex),
      await erasedFile.readAsBytes(),
    );
  }

  /// 这一页的叠层两件产物齐不齐（图层 JSON + 擦字底图）。
  ///
  /// 一次问完而不是分两次：裁决要的是**一格**布尔，分开问会让「只有一半」这个状态
  /// 在每个调用点各自解释一遍 —— 而「只有一半」正好画出半截译文。
  static Future<bool> overlayReady({
    required String label,
    required int pageIndex,
  }) async => overlayDisplayable(label: label, pageIndex: pageIndex);

  /// 叠层能不能直接显示：图层在盘上，并且**底要么不需要擦（每框都有填色）、要么擦字底图在**。
  ///
  /// 为什么不是简单看两个文件在不在：填色够用的那一页根本不会有 `p<N>.base.png`
  /// （擦字整个跳过了），按「必须有底图文件」判就会把最省时间的那条路判成不可用，
  /// 于是每次上屏都重跑一遍 OCR —— 那正好是这一档要避免的事。
  static Future<bool> overlayDisplayable({
    required String label,
    required int pageIndex,
  }) async {
    final layer = await _decodeLayer(label: label, pageIndex: pageIndex);
    if (layer == null || layer.boxes.isEmpty) return false;
    if (layer.boxes.every((b) => b.fill != null)) return true;
    return (await baseFile(label: label, pageIndex: pageIndex)).exists();
  }

  /// 这一页的叠层底是不是**必须**是擦字底图（而不是画面上本来那张）。
  ///
  /// 命中缓存那一路也要问它：不然第一次建好时替这一页占了轨、翻回来命中缓存就不占，
  /// 同一页两种画面，用户会看到中文底下又露出日文 —— 占不占轨必须是这一页的**属性**，
  /// 不能是「这次走了哪条分支」的副产品。
  static Future<bool> overlayNeedsErasedBase({
    required String label,
    required int pageIndex,
  }) async {
    final layer = await _decodeLayer(label: label, pageIndex: pageIndex);
    // 图层问不到就按「要擦」处理：宁可多占一次轨（超分为这一页让路），
    // 也不要端出一张字压字的页。
    if (layer == null || layer.boxes.isEmpty) return true;
    return !layer.boxes.every((b) => b.fill != null);
  }

  static Future<TranslatedPageLayer?> _decodeLayer({
    required String label,
    required int pageIndex,
  }) async {
    final file = await layerFile(label: label, pageIndex: pageIndex);
    if (!file.existsSync()) return null;
    return TranslatedPageLayer.tryDecode(await file.readAsString());
  }

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
    await _writeAtomically(target, pngBytes);
    if (fingerprint != null) await _recordFingerprint(dir, fingerprint);
  }

  /// 写某一页的**图层 JSON**（叠层与烘焙共用那份可重复合成描述）。
  ///
  /// 为什么要有这一层，而不是让调用方自己 `layerFile(...).writeAsString(...)`：
  /// 叠层「全页都采到平色」那一条路**不会**先创建缓存目录（既没写 PNG 也没写底图），
  /// 裸 `writeAsString` 当场撞在 `PathNotFoundException` 上 —— 而那条路正是干净的白气泡
  /// 页每一本第一页必走的路（2026-10-04 单测抓到的就是这个）。目录、原子写、清单
  /// 这三件事在这里一次做对，两个调用点就不会各漏一件。
  static Future<void> writeLayer({
    required String label,
    required int pageIndex,
    required String json,
    String? fingerprint,
  }) async {
    final dir = await directory(label);
    await dir.create(recursive: true);
    await _writeAtomically(
      await layerFile(label: label, pageIndex: pageIndex),
      Uint8List.fromList(utf8.encode(json)),
    );
    if (fingerprint != null) await _recordFingerprint(dir, fingerprint);
  }

  static Future<void> _recordFingerprint(
    Directory dir,
    String fingerprint,
  ) async {
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

  static Future<void> _writeAtomically(File target, Uint8List bytes) async {
    final tmp = File('${target.path}.tmp_$pid');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }

  /// 已生成的成品页数：设置页用它显示「已生成 N 张」，也决定「清空」要不要亮着。
  static Future<int> pageCount() async {
    final root = await OcrService.outputRoot();
    if (!await root.exists()) return 0;
    final legacyDir = p.join(root.path, _legacyDegradedDirName);
    var count = 0;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      // 老版本降级档留下的那张没翻译，报进「已生成」就是谎报产物。
      // 擦字底图也不算产物：它是叠层的中间像素，一页的成品只该被数一次。
      if (e is! File || !e.path.endsWith('.png')) continue;
      if (e.path.endsWith('.base.png')) continue;
      if (p.isWithin(legacyDir, e.path)) continue;
      count++;
    }
    return count;
  }

  /// 清掉所有成品页（换模型 / 换字体后用户手点「重来」时用）。
  static Future<void> clearAll() async {
    final root = await OcrService.outputRoot();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
