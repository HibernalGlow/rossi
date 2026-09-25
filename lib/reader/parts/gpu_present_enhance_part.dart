part of '../gpu_present_controller.dart';

// 从 class GpuPresentController 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。
extension GpcEnhancePart on GpuPresentController {
  Future<void> _initUpscaleSetting() async {
    try {
      final bool auto = await RealSrSettings.loadAutoUpscale();
      if (!_disposed && auto) {
        setUpscaleEnabled(true);
      }
    } catch (_) {}
  }
  void _onModelChanged() {
    if (_disposed) return;
    SuperResolutionLog.add('模型配置变化：清除旧增强轨，重新处理当前页。');
    _enhancementQueue.clear();
    _enhancementEpoch++;
    _modelRefreshPending = true;
    _upscaleAttempts.clear();
    // 换了模型，旧产物不再代表「这一页的超分图」：阶段回到未落定、尺寸重算
    // （原图尺寸与模型无关，连「量过」的痕迹一起留着）。
    _mutate(() {
      _pagePhases.clear();
      _pageEnhancedSizes.clear();
      _enhancedSizeProbed.clear();
      _pageStatusRevision++;
    });
    unawaited(_refreshModel());
  }
  Future<void> _refreshModel() async {
    if (_disposed || _syncing || !_modelRefreshPending) return;
    final source = _lastPushedSource;
    final index = _pushedIndex;
    final size = _pushedSize;
    if (source == null || index == null || size == null) return;
    await present(source: source, index: index, physicalSize: size);
  }
  bool _acceptsEnhancement(int epoch) =>
      !_disposed &&
      epoch == _enhancementEpoch &&
      !_modelRefreshPending &&
      !_openingSource &&
      _isUpscaleEnabled &&
      !_originalPreview;
  Future<void> _awaitReady() async {
    if (_watchdogRunning) {
      return;
    }
    _watchdogRunning = true;
    try {
      await _awaitReadyLoop();
    } finally {
      _watchdogRunning = false;
    }
  }
  /// 超分替换和原图对比也会覆写共享纹理，必须与翻页/调整画布共用上屏锁。
  Future<bool> _redrawCurrentPage(int index) async {
    if (_disposed ||
        _syncing ||
        _pushedIndex != index ||
        _presentedFrame == null) {
      return false;
    }
    _mutate(() => _syncing = true);
    try {
      await _bridge.show(index);
      if (_disposed) return false;
      _mutate(() => _presentCount++);
      return true;
    } finally {
      _mutate(() => _syncing = false);
      if (_modelRefreshPending) unawaited(_refreshModel());
    }
  }
  Future<bool> _enqueueOriginalPreview(
    bool active, {
    bool ensureEnhanced = true,
  }) {
    final Future<bool> operation = _previewQueue.then(
      (_) => _setOriginalPreview(active, ensureEnhanced: ensureEnhanced),
    );
    _previewQueue = operation.then<void>((_) {}).catchError((_) {});
    return operation;
  }
  /// 写入一页的阶段。同值不写 —— 免得流水线里的重复打点变成一次界面重建。
  void _markPhase(int index, SuperResolutionPagePhase phase) {
    if (_pagePhases[index] == phase) return;
    _mutate(() {
      _pagePhases[index] = phase;
      _pageStatusRevision++;
    });
  }
  /// 记下一页的原图尺寸（量到了才记）。
  void _markSourceSize(int index, Size? size) {
    if (_sourceSizeProbed.contains(index) && size == null) return;
    _sourceSizeProbed.add(index);
    if (size == null || _pageSourceSizes[index] == size) return;
    _mutate(() {
      _pageSourceSizes[index] = size;
      _pageStatusRevision++;
    });
  }
  /// 量一次超分产物的尺寸并记账。**每页只量一次** —— 量的是图片头，
  /// 但 `ImmutableBuffer.fromFilePath` 会把整个文件读进来，重复量等于重复读盘。
  Future<void> _recordEnhancedSize(int index, String outPath) async {
    if (_enhancedSizeProbed.contains(index)) return;
    _enhancedSizeProbed.add(index);
    final Size? size = await RealSrSuperResolution.imageSizeOf(outPath);
    if (size == null) return;
    _mutate(() {
      _pageEnhancedSizes[index] = size;
      _pageStatusRevision++;
    });
  }
  /// 记账整体作废：换了来源或换了模型时页号/缓存键的含义都变了。
  ///
  /// 必须在 `_mutate` 里调 —— 它要顺带把版本号推一格，界面才知道要重新读。
  void _resetPageStatus() {
    _pagePhases.clear();
    _pageSourceSizes.clear();
    _pageEnhancedSizes.clear();
    _sourceSizeProbed.clear();
    _enhancedSizeProbed.clear();
    _pageStatusRevision++;
  }
  Future<void> _setUpscaleEnabled(bool enabled) async {
    // 必须等待旁路切换及当前页重绘完成，再启动超分注入。否则 native
    // 仍处于 bypass_enhanced=true 时，超分图虽已注入也会被原图帧覆盖。
    await _enqueueOriginalPreview(!enabled, ensureEnhanced: false);

    if (enabled &&
        _isUpscaleEnabled &&
        _pushedPath != null &&
        _pushedIndex != null &&
        _lastPushedSource != null) {
      await _scheduleEnhancements(
        _lastPushedSource!,
        _pushedIndex!,
        _pushedWidth ?? 0,
        _pushedHeight ?? 0,
      );
    }
  }
  void _onPrefetchChanged() {
    final source = _lastPushedSource;
    final index = _pushedIndex;
    if (source != null && index != null) {
      unawaited(
        _scheduleEnhancements(
          source,
          index,
          _pushedWidth ?? 0,
          _pushedHeight ?? 0,
        ),
      );
    }
  }
  Future<void> _scheduleEnhancements(
    PageSource source,
    int index,
    int width,
    int height,
  ) {
    final operation = _scheduleEnhancementsSafely(source, index, width, height);
    _enhancementSchedules.add(operation);
    return operation.whenComplete(
      () => _enhancementSchedules.remove(operation),
    );
  }
  Future<void> _scheduleEnhancementsSafely(
    PageSource source,
    int index,
    int width,
    int height,
  ) async {
    final revision = ++_scheduleRevision;
    final epoch = _enhancementEpoch;
    bool isCurrent() =>
        revision == _scheduleRevision &&
        _acceptsEnhancement(epoch) &&
        _pushedPath == source.path;
    try {
      // 翻页立刻清除待执行的旧预超分，配置读取不占用原图呈现路径。
      _enhancementQueue.clear();
      _enhancementTargets = {index};
      if (!_acceptsEnhancement(epoch)) return;
      final (forward, back) = await RealSrSettings.loadPrefetch();
      if (!isCurrent()) return;
      final targets = superResolutionTargets(
        index,
        source.pageCount,
        forward,
        back,
      );
      _enhancementTargets = targets.toSet();
      // 已落盘的当前页不排在正在执行的预超分后面：直接恢复增强轨。
      final cacheKey = await RealSrSettings.loadCacheKey();
      if (!isCurrent()) return;
      final cache = await _srCacheDir();
      if (!isCurrent()) return;
      final cached = await File(
        p.join(cache.path, 'sr_${source.path.hashCode}_${index}_$cacheKey.png'),
      ).exists();
      if (!isCurrent()) return;
      if (cached) await _ensureEnhancedForIndex(source, index, width, height);
      if (!isCurrent()) return;
      if (cached) targets.remove(index);
      // 「排队中」只打给**真的会被处理**的那些页（已落盘的当前页不在其中），
      // 且只打给还没落定的页：已经「无需超分 / 失败 / 已超分」的页不该被
      // 下一次调度按回「排队中」—— 那会让界面上刚说清楚的结论又变得含糊。
      for (final target in targets) {
        final SuperResolutionPagePhase? recorded = _pagePhases[target];
        if (recorded == null ||
            recorded == SuperResolutionPagePhase.queued ||
            recorded == SuperResolutionPagePhase.running) {
          _markPhase(target, SuperResolutionPagePhase.queued);
        }
      }
      _enhancementQueue.replace([
        for (final target in targets)
          (
            (epoch, target),
            () async {
              if (!_acceptsEnhancement(epoch) || _pushedPath != source.path) {
                return;
              }
              await _ensureEnhancedForIndex(source, target, width, height);
            },
          ),
      ]);
    } catch (error, stackTrace) {
      if (isCurrent()) {
        SuperResolutionLog.add(
          '第 ${index + 1} 页：预超分调度失败',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }
  Future<Directory> _srCacheDir() async {
    final Directory? cached = _srCacheDirCache;
    if (cached != null && cached.existsSync()) {
      return cached;
    }
    final Directory srCacheDir = await SuperResolutionLog.cacheDirectory();
    logger.i('[Rossi AI] 超分缓存目录: ${srCacheDir.path}');
    _srCacheDirCache = srCacheDir;
    return srCacheDir;
  }
  /// 把超分产物交给呈现器，并**按实际结果**汇报。
  ///
  /// # 为什么要拆成两段、为什么两段都要看返回值
  ///
  /// 用户眼里的「替换成功」= 画面上换成了超分图。而在代码里，从「超分跑完」到
  /// 「画面上真的换了」中间有两道闸，各自会失败，而且**后者不能由前者推出来**：
  ///
  /// 1. **注入**：[setEnhancedImage] 把像素放进呈现器的双轨缓存。可能失败
  ///    （呈现器未就绪、大图解码失败、这个平台没有这条实现……）；
  /// 2. **上屏**：`show` 之后那一帧**确实取自超分轨**。它同样可能失败 —— 最典型的
  ///    是注入之后该页的原图轨又被预取线程写回，把超分轨整条覆盖掉。
  ///
  /// 从前这两件事和「文件生成了」被写成一句「第 N 页超分成功 …… 已触发原子平滑
  /// 替换呈现」，第 2 段失败时日志照打：**日志说成功、画面还是原图**（虚报）。
  ///
  /// 现在的纪律：
  /// - 上屏后向呈现器要**证据**（`probe.usedEnhanced`），拿不到证据就既不声称成功
  ///   也不声称失败；
  /// - 证据说"这次用的还是原图轨"时**如实报失败**（下次呈现该页会重来一遍，
  ///   而那时盘上已有产物，重来的代价只是注入）。
  ///
  /// 返回是否真的在画面上替换了（`false` = 这次没换上，或已注入、等下一次呈现）。
  Future<bool> _applyEnhancedToPresenter(
    int index,
    String outPath,
    int targetW,
    int targetH,
    int epoch,
  ) async {
    if (!_acceptsEnhancement(epoch)) {
      // 这里原来是静默返回 false：产物在盘上、日志却连一行注入记录都没有，
      // 看起来就像"根本没打算换"。
      SuperResolutionLog.add(
        '第 ${index + 1} 页：任务已过期或处于原图对比，不注入。'
        '开关=$_isUpscaleEnabled；原图对比=$_originalPreview；'
        '模型刷新中=$_modelRefreshPending',
      );
      return false;
    }
    SuperResolutionLog.add('第 ${index + 1} 页：向呈现器注入增强图\n$outPath');
    final bool injected = await setEnhancedImage(
      index,
      outPath,
      width: targetW > 0 ? targetW : null,
      height: targetH > 0 ? targetH : null,
    );
    if (!_acceptsEnhancement(epoch)) return false;
    if (!injected) {
      SuperResolutionLog.add('第 ${index + 1} 页：呈现器拒绝注入，替换失败。');
      logger.w('[Rossi AI] 第 $index 页超分图注入呈现器失败');
      return false;
    }
    if (_pushedIndex != index) {
      SuperResolutionLog.add(
        '第 ${index + 1} 页：已注入缓存，当前正在显示第 ${(_pushedIndex ?? -1) + 1} 页。',
      );
      return false;
    }

    // `show` 与 native 预取线程共用一条队列。注入完成后让队列先跑完当前
    // 帧，再核对像素来源；若恰好读到了前一帧的诊断，立即再重画一次。
    for (var pass = 0; pass < 3; pass++) {
      if (!_acceptsEnhancement(epoch) || _pushedIndex != index) return false;
      if (!await _redrawCurrentPage(index)) return false;
      if (!_acceptsEnhancement(epoch)) return false;
      if (pass > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      final bool? confirmed = await _presenterUsesEnhanced(index);
      SuperResolutionLog.add(
        '第 ${index + 1} 页：第 ${pass + 1} 次上屏核对；'
        '使用增强图=$confirmed；原图对比=$_originalPreview；当前页=${(_pushedIndex ?? -1) + 1}',
      );
      if (!_acceptsEnhancement(epoch)) return false;
      if (confirmed == true) {
        // 呈现器自己说这一帧取自超分轨 —— 这句话是「已超分」唯一的依据。
        _markPhase(index, SuperResolutionPagePhase.applied);
        SuperResolutionLog.add('第 ${index + 1} 页：替换成功，呈现器确认当前画面来自超分图。');
        _upscaleAttempts.remove(index);
        logger.i('[Rossi AI] 第 $index 页超分图已替换上屏（呈现器确认本次呈现取自超分轨）');
        return true;
      }
      if (confirmed == null || _originalPreview || _pushedIndex != index) {
        logger.i('[Rossi AI] 第 $index 页注入后暂时无法核对显示来源: $confirmed');
        return false;
      }
      if (pass < 2) {
        logger.w('[Rossi AI] 第 $index 页注入后仍检测到原图轨，立即重画重试（${pass + 2}/3）');
      }
    }
    logger.w('[Rossi AI] 第 $index 页注入后仍显示原图，已保留缓存并等待下一次呈现重试');
    SuperResolutionLog.add('第 ${index + 1} 页：文件已生成，但呈现器仍显示原图，替换失败。');
    return false;
  }
  /// 问呈现器：「第 [index] 页现在用的是超分轨吗？」
  ///
  /// `null` = **判不了**（呈现器没就绪、或上一次呈现已经不是这一页了）。判不了时
  /// 既不报成功也不报失败 —— 把不确定说成其中之一，正是这次要修的那个 bug。
  ///
  /// 证据来自 Rust 侧 `MacPresenter::show_into_buffer` 的 `usedEnhanced`：它由
  /// **这一帧的像素从哪来**决定，而不是由"我们调用过 show"推断。所以它既能确认
  /// 「替换真的上屏了」，也能在**没换上去**时把这件事说出来 —— 而 Dart 侧自己
  /// 记的账做不到后者（它只知道自己调过注入）。
  Future<bool?> _presenterUsesEnhanced(int index) async {
    try {
      final GpuPresentStats stats = await _bridge.stats();
      final usedEnhanced = stats['usedEnhanced'];
      if (stats['currentIndex'] != index ||
          (usedEnhanced != 0 && usedEnhanced != 1)) {
        return null;
      }
      return usedEnhanced == 1;
    } catch (_) {
      return null;
    }
  }
}
