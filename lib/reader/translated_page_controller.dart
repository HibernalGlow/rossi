import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:zephyr/reader/gpu_present_controller.dart';
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/service/ocr/ocr_models.dart';
import 'package:zephyr/service/ocr/ocr_service.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';
import 'package:zephyr/service/ocr/ocr_translator.dart';
import 'package:zephyr/service/ocr/translated_page_builder.dart';

enum TranslatedPagePhase {
  /// 这一页显示的是原图。
  off,

  /// 正在跑「检测 → 识别 → 擦字 → 翻译 → 回填」，整页要十几秒。
  building,

  /// 成品页已经注入呈现器，并且**核对过**画面真的来自它。
  showing,

  /// 失败。原因在 [TranslatedPageController.lastError]，界面直接显示，不静默回退。
  failed,
}

/// 呈现器那一侧需要的三件事。抽成接口只为了能在没有 GPU 的测试里跑状态机。
abstract interface class TranslatedPagePresenter {
  Future<bool> setEnhancedImage(int index, String imagePath);

  Future<bool> reshowAfterInjection(int index);

  /// `null` = 呈现器答不上来（不是「没换上」，是「不知道」）。
  Future<bool?> presenterUsesEnhanced(int index);

  /// 被译文占用的页号；超分调度读它给译文让路（增强图轨一页只有一份）。
  /// 被译文占用的页 → 成品页路径。超分调度读它给译文让路，并在翻回来时用它
  /// 把同一张成品页重新注回去（增强图轨会被呈现器按保留集淘汰）。
  Map<int, String> get translationOwnedPages;

  static TranslatedPagePresenter of(GpuPresentController controller) =>
      _GpuPresenter(controller);
}

class _GpuPresenter implements TranslatedPagePresenter {
  _GpuPresenter(this._c);
  final GpuPresentController _c;

  @override
  Future<bool> setEnhancedImage(int index, String imagePath) =>
      _c.setEnhancedImage(index, imagePath);

  @override
  Future<bool> reshowAfterInjection(int index) =>
      _c.reshowAfterInjection(index);

  @override
  Future<bool?> presenterUsesEnhanced(int index) =>
      _c.presenterUsesEnhanced(index);

  @override
  Map<int, String> get translationOwnedPages => _c.translationOwnedPages;
}

/// 当前这一页要不要显示成「成品页」（译文回填后的那张）。
///
/// # 为什么走呈现器的增强图轨
/// 阅读器的页面在桌面端由 native 上屏，Flutter 侧再画一层 `Image.file`
/// 会绕开旋转、双页、页宽适配那一整套变换（画出来的是「另一张没转的图」）。
/// 增强图轨本来就是「第 N 页换成另一个文件显示」的入口，AI 超分走的就是它。
///
/// # 与超分共用一条轨的代价
/// 增强图轨一页只有一份，所以**译文与超分互斥**：这一页被译文占用时，
/// 超分调度会跳过它（见 `gpu_present_enhance_part.dart` 的闸）。
/// 关掉译文时把**原图**当增强图注回去 —— 呈现器没有「清除增强图」这个入口，
/// 而用户要的就是回到原图，注一张原图效果等价。
class TranslatedPageController extends ChangeNotifier {
  TranslatedPageController({TranslatedPageBuilder? builder})
    : _builder = builder ?? TranslatedPageBuilder();

  static TranslatedPageController instance = TranslatedPageController();

  /// 换一台**带假构建器**的控制器给测试，并返回之前那台（调用方负责换回去）。
  ///
  /// 为什么需要它：`LocalReadSession` 那两行装配（`setSource` / `dispose` 里的
  /// `TranslatedPageController.instance.reset()`）走的就是这个单例，而单例默认的构建器
  /// 要原生库与 660 MB 权重 —— 不换掉它，「退出阅读真的取消了在飞推理」这句话在桌面测试里
  /// 根本没法被执行，只能写成「靠真机验」。
  @visibleForTesting
  static TranslatedPageController useForTest(
    TranslatedPageController controller,
  ) {
    final previous = instance;
    instance = controller;
    return previous;
  }

  final TranslatedPageBuilder _builder;

  TranslatedPagePhase _phase = TranslatedPagePhase.off;
  int _index = -1;
  String _lastError = '';
  TranslatedPagePresenter? _presenter;

  /// 「第几本书」的计数。换书 / 换章时 +1，用来让**在飞的构建**认出自己已经过期：
  /// 一页要十几秒，这期间用户完全可能翻到另一本书 —— 不认出的话，
  /// 旧书第 5 页的成品页会被注到新书第 5 页上（同一序号，完全不同的内容）。
  int _generation = 0;
  final Map<int, String> _inputScratch = <int, String>{};

  /// 哪些页显示的是降级产物（原文回填）。**不进缓存，所以这份只能记在会话里** ——
  /// 芯片要能区分「译文页」与「只是擦了字又画回原文」。
  final Set<int> _degradedPages = <int>{};
  Directory? _scratch;

  TranslatedPagePhase get phase => _phase;
  int get index => _index;
  String get lastError => _lastError;

  /// 这一页是否归译文管（只给界面用；超分那边直接读呈现器自己那份集合）。
  bool isDegraded(int index) => _degradedPages.contains(index);

  bool isOwned(int index) =>
      _presenter?.translationOwnedPages.containsKey(index) ?? false;

  /// 换书 / 换章：清掉所有归属与临时输入，避免拿旧页的产物往新页上贴。
  void reset() {
    _generation++;
    _presenter?.translationOwnedPages.clear();
    _degradedPages.clear();
    try {
      _scratch?.deleteSync(recursive: true);
    } catch (_) {
      // 临时目录删不掉不影响阅读，别在这里抛。
    }
    _scratch = null;
    _inputScratch.clear();
    // 别攥着已经 dispose 掉的呈现器：归属表存在它身上，留着只是拖着一个死对象。
    _presenter = null;
    _phase = TranslatedPagePhase.off;
    _index = -1;
    _lastError = '';
    notifyListeners();
  }

  /// 翻转某一页。返回是否成功（失败时 [lastError] 有话说）。
  Future<bool> toggle({
    required PageSource source,
    required TranslatedPagePresenter presenter,
    required int index,
  }) async {
    _presenter = presenter;
    if (presenter.translationOwnedPages.containsKey(index)) {
      return _turnOff(index, source, presenter, _generation);
    }
    return _turnOn(index, source, presenter);
  }

  Future<bool> _turnOn(
    int index,
    PageSource source,
    TranslatedPagePresenter presenter,
  ) async {
    final config = await OcrSettings.loadConfig();
    if (config == null) return _fail(index, '还没配好翻译端点，去设置里填');
    if (!ocrSupportedHere) return _fail(index, '这个平台不做译文页');
    final missing = await _missingWeights();
    if (missing.isNotEmpty) {
      return _fail(index, '权重没下全：缺 ${missing.join('、')}');
    }

    final generation = _generation;
    _phase = TranslatedPagePhase.building;
    _index = index;
    _lastError = '';
    notifyListeners();

    try {
      final input = await _inputPathFor(source, index);
      final out = await _builder.build(
        imagePath: input,
        pageIndex: index,
        config: config,
        // 换书 / 退出之后，剩下的阶段就不要再跑了：一页要十几秒，
        // 光靠「结果回来再丢弃」是把 CPU 烧完才算完。
        // 粒度只能是阶段 —— Rust 侧一次调用没有协作式取消点。
        shouldCancel: () => _stale(generation),
        force: false,
      );
      if (_stale(generation)) return false; // 书都换了，这份产物没有归属可言
      if (!out.hasText) return _fail(index, '这一页没识别到文字');
      return await _inject(
        index,
        out.path,
        presenter,
        showingOnSuccess: true,
        degraded: out.degraded,
      );
    } on TranslatedPageCancelled {
      // 自己取消的那次构建不是一条错误，也不该有归属：干净收手。
      return false;
    } on OcrModelsMissing catch (e) {
      return _stale(generation) ? false : _fail(index, '$e');
    } on OcrTranslationException catch (e) {
      return _stale(generation) ? false : _fail(index, '翻译失败：${e.message}');
    } catch (e) {
      return _stale(generation) ? false : _fail(index, '成品页构建失败：$e');
    }
  }

  Future<bool> _turnOff(
    int index,
    PageSource source,
    TranslatedPagePresenter presenter,
    int generation,
  ) async {
    final original = await _inputPathFor(source, index);
    // 关的那一路也要认过期：`_inputPathFor` 会问呈现源要路径、必要时落一次临时文件，
    // 这中间换书的话，把旧书的原图注到新书那一页上同样是错的。
    if (_stale(generation)) return false;
    final ok = await _inject(
      index,
      original,
      presenter,
      showingOnSuccess: false,
      degraded: false,
    );
    if (ok) {
      presenter.translationOwnedPages.remove(index);
      _phase = TranslatedPagePhase.off;
      _index = index;
      notifyListeners();
    }
    return ok;
  }

  /// 注入 → 重画 → **向呈现器核对**这一帧确实来自注入的那张图。
  ///
  /// 核对不是形式主义：注入成功但画面没换（原图轨被预取线程写回）是真实发生过的，
  /// 那种情况下声称「已显示译文」就是虚报。
  Future<bool> _inject(
    int index,
    String path,
    TranslatedPagePresenter presenter, {
    required bool showingOnSuccess,
    required bool degraded,
  }) async {
    if (!await File(path).exists()) {
      // 产物在这一步之前被人删了 / 目录被清了：ADR-0018 §决定 3 要的是
      // 「静默回落到原图」，不是弹一条「找不到文件」。原图本来就是真相。
      _presenter?.translationOwnedPages.remove(index);
      _phase = TranslatedPagePhase.off;
      _index = index;
      _lastError = '';
      notifyListeners();
      return false;
    }
    if (!await presenter.setEnhancedImage(index, path)) {
      return _fail(index, '呈现器拒绝注入这张图');
    }
    if (!await presenter.reshowAfterInjection(index)) {
      // 已经注入了：下一次该页上屏自然生效，这里不当失败。
      _claim(presenter, index, path, showingOnSuccess, degraded);
      _phase = showingOnSuccess
          ? TranslatedPagePhase.showing
          : TranslatedPagePhase.off;
      _index = index;
      notifyListeners();
      return true;
    }
    final confirmed = await presenter.presenterUsesEnhanced(index);
    if (confirmed == false) {
      return _fail(index, '注入成功但画面没换，这一页再翻回来会重试');
    }
    _claim(presenter, index, path, showingOnSuccess, degraded);
    _phase = showingOnSuccess
        ? TranslatedPagePhase.showing
        : TranslatedPagePhase.off;
    _index = index;
    _lastError = '';
    notifyListeners();
    return true;
  }

  /// 归档里的页没有磁盘直路径，OCR 与呈现器都要一个文件 —— 落到一个临时目录，
  /// 按页缓存，关译文时同一份原图还要用它注回去。
  /// 构建期间用户换了书 / 章：旧结果一律作废，既不注入也不报错到新页脸上。
  bool _stale(int generation) => generation != _generation;

  Future<String> _inputPathFor(PageSource source, int index) async {
    final direct = await source.getPageFilePath(index);
    if (direct != null) return direct;
    final cached = _inputScratch[index];
    if (cached != null && File(cached).existsSync()) return cached;
    final bytes = await source.getPageBytes(index);
    if (bytes == null) throw StateError('取不到第 $index 页的图像字节');
    final dir = await _scratchDir();
    final file = File('${dir.path}/page_$index.img');
    await file.writeAsBytes(bytes, flush: true);
    _inputScratch[index] = file.path;
    return file.path;
  }

  Future<Directory> _scratchDir() async {
    return _scratch ??= await Directory.systemTemp.createTemp(
      'rossi_ocr_input_',
    );
  }

  Future<List<String>> _missingWeights() async {
    final (_, missing) = await OcrModels.status();
    return missing;
  }

  /// 开译文时登记「这一页归译文 + 归的是哪张图」；关译文时把归属摘掉。
  void _claim(
    TranslatedPagePresenter presenter,
    int index,
    String path,
    bool showingOnSuccess,
    bool degraded,
  ) {
    if (showingOnSuccess) {
      presenter.translationOwnedPages[index] = path;
      if (degraded) {
        _degradedPages.add(index);
      } else {
        _degradedPages.remove(index);
      }
    } else {
      presenter.translationOwnedPages.remove(index);
      _degradedPages.remove(index);
    }
  }

  bool _fail(int index, String message) {
    _phase = TranslatedPagePhase.failed;
    _index = index;
    _lastError = message;
    notifyListeners();
    return false;
  }
}
