import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/service/ocr/ocr_model_downloader.dart';
import 'package:zephyr/service/ocr/ocr_models.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/service/ocr/ocr_service.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_builder.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

/// OCR 成品页的**应用内冒烟页**：选一张页 → 跑完整链路 → 看耗时、块数与画出来的图。
///
/// 为什么要它：整条链路要过权重下载、端点配置、Rust 过桥、翻译请求、字体注册、回填排版
/// 六道关，任何一道错了，在阅读器的表现都只是「按了没反应」。
/// 这一页把六道关摊开成一行行可读的状态与耗时，不必先进书、再翻页、再找那一格。
///
/// 刻意不放进 `kDebugMode`（与本地来源、GPU 上屏那两条同口径）：
/// 要判的是「发出去的构建对不对」，只有 Release 跑出来的才算数。
class OcrSmokeDebugPage extends StatefulWidget {
  const OcrSmokeDebugPage({super.key});

  @override
  State<OcrSmokeDebugPage> createState() => _OcrSmokeDebugPageState();
}

class _OcrSmokeDebugPageState extends State<OcrSmokeDebugPage> {
  List<String> _missing = const [];
  String _ep = OcrSettings.defaultEp;
  bool _weightsLoading = true;
  bool _downloading = false;
  double _progress = 0;

  String? _imagePath;
  String? _stage;
  String? _error;
  TranslatedPage? _result;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final (_, missing) = await OcrModels.status();
    final ep = await OcrSettings.loadEp();
    if (!mounted) return;
    setState(() {
      _missing = missing;
      _ep = ep;
      _weightsLoading = false;
    });
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    try {
      await RustLib.init();
      await OcrModelDownloader.ensure(
        onProgress: (received, total, file) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = received / total);
        },
      );
    } catch (e) {
      if (mounted) setState(() => _error = '权重下载失败：$e');
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
        await _refresh();
      }
    }
  }

  Future<void> _pick() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: '图片', extensions: ['jpg', 'jpeg', 'png', 'webp']),
      ],
    );
    if (file == null || !mounted) return;
    setState(() {
      _imagePath = file.path;
      _result = null;
      _error = null;
      _stage = null;
    });
  }

  Future<void> _run() async {
    final image = _imagePath;
    if (image == null) return;
    final config = await OcrSettings.loadConfig();
    if (config == null) {
      setState(() => _error = '还没配好翻译端点：去「设置 → 漫画翻译（成品页）」填接口地址与模型名');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _result = null;
      _stage = '准备中';
    });
    try {
      final out = await TranslatedPageBuilder().build(
        imagePath: image,
        pageIndex: 0,
        config: config,
        force: true,
        onStage: (stage) {
          if (mounted) setState(() => _stage = stage.label());
        },
      );
      if (mounted) setState(() => _result = out);
    } on OcrModelsMissing catch (e) {
      if (mounted) setState(() => _error = '$e');
    } on OcrTranslationException catch (e) {
      if (mounted) setState(() => _error = '翻译那一跳：${e.message}');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('OCR 成品页冒烟'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: Text(
              _weightsLoading
                  ? '权重状态查询中…'
                  : _missing.isEmpty
                  ? '权重已就绪（5 个文件）'
                  : '缺 ${_missing.length} 个：${_missing.join('、')}',
            ),
            subtitle: _downloading
                ? LinearProgressIndicator(value: _progress)
                : null,
            trailing: TextButton(
              onPressed: _downloading ? null : _download,
              child: Text(_downloading ? '下载中' : '下载权重'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.memory_outlined),
            // 明说是「请求值」：三段实际用哪条 EP 由 Rust 侧按段 resolve，
            // 这个值**没有**过桥回来（要等 OcrPageResult 带上 per-stage 才算得上报实际值），
            // 现在写成「推理后端：auto」会让人以为看见的就是跑起来的那条。
            title: Text('推理后端（请求值）：$_ep；各段实际用哪条由 Rust 按段决定'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: Text(_imagePath == null ? '还没选页' : _imagePath!),
            trailing: TextButton(onPressed: _pick, child: const Text('选一张页')),
          ),
          ListTile(
            leading: const Icon(Icons.play_arrow_outlined),
            title: Text(_running ? (_stage ?? '跑着') : '跑一遍完整链路'),
            subtitle: const Text('检测 → 识别 → 聚块 → 擦字 → 翻译 → 回填（force，不读缓存）'),
            trailing: FilledButton(
              onPressed: _running || _imagePath == null ? null : _run,
              child: const Text('开跑'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (result != null) ...[
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(
                '${result.elapsed.inMilliseconds} ms · ${result.blockCount} 块'
                '${result.truncatedCount > 0 ? ' · ${result.truncatedCount} 块被截断（可疑）' : ''}'
                '${result.fromCache ? ' · 命中缓存' : ''}',
              ),
              subtitle: Text(result.path),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Image.file(File(result.path)),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

extension on TranslatedPageStage {
  String label() => switch (this) {
    TranslatedPageStage.cacheHit => '查缓存',
    TranslatedPageStage.analyzing => '检测 / 识别 / 擦字',
    TranslatedPageStage.translating => '翻译请求',
    TranslatedPageStage.typesetting => '回填排版',
  };
}
