part of '../local_source_debug_page.dart';

// ignore_for_file: invalid_use_of_protected_member
// 从 class _LocalSourceDebugPageState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。
extension _LocalSourceDebugPrefetchPart on _LocalSourceDebugPageState {
  void _onFrameTimings(List<ui.FrameTiming> timings) {
    if (timings.isEmpty) return;
    _lastTiming = timings.last;
    // 刻意不 setState：在帧回调里重建会自己制造抖动，量具就成了噪声源。
    // 这个数在下一次由别的原因触发的重建里顺带显示出来。
  }
  /// 一帧的耗时分解，一行字。
  String _frameCostLabel() {
    final t = _lastTiming;
    if (t == null) return '—';
    return 'build ${t.buildDuration.inMilliseconds} '
        'raster ${t.rasterDuration.inMilliseconds} '
        'vsync ${t.vsyncOverhead.inMilliseconds} ms';
  }
  /// 把当前页的相邻页排进预取队列。
  ///
  /// **判决在 Rust 侧**（`local_prefetch_decision` → 上游 `decide_prefetch_allowed`），
  /// 这里只递状态、并按节奏再问一次。目标顺序同样来自 Rust
  /// （`local_prefetch_targets` → 上游 `interleaved_prefetch_positions`）。
  ///
  /// **刻意不在这一层写第二套策略。** 一旦本地也判一次，`rossi_local_core::prefetch_policy`
  /// 里那 13 条测试就管不到真实行为了 —— 我们手搓的「180 ms 延迟 + 一个布尔」
  /// 就是它的退化版，被替换掉正是这次搬运的目的。
  void _schedulePrefetch() {
    if (!_prefetchEnabled) return;
    // 用户明确选了「外壳」就别再走 Rust 解 —— 预取缓存会被 `_takePrefetch`
    // 直接采用，那就等于偷偷把解码器换回去了。
    if (_decoderMode == _DecoderMode.shell) return;
    final id = _sessionId;
    if (id == null) return;
    final generation = ++_prefetchGeneration;
    unawaited(_prefetchNeighbors(id, generation));
  }
  Future<void> _prefetchNeighbors(BigInt id, int generation) async {
    // 等放行。上游是每帧问一次 `decide_prefetch_allowed`；宿主从 egui 的帧循环
    // 换成 Flutter 之后，改成每 50 ms 问一次 —— 同一个门槛，只是问的节奏变了。
    //
    // 代号（`_prefetchGeneration`）在**两个**地方 +1：翻页发起时（`_loadPage`，
    // 对应上游「当前页不可显示 ⇒ 取消其它 pending」）和本函数被重新调度时。
    // 所以下面每个检查点都会在翻页的瞬间直接退场 —— 连翻时一页都不会解，
    // 那是有意的：dav1d 吃满 16 核，跟正在等的那次翻页抢核就是拖慢用户。
    for (var round = 0; ; round++) {
      if (!mounted || generation != _prefetchGeneration) return;
      final decision = await localPrefetchDecision(
        msSinceLastTurn: _lastTurnAt == null
            ? null
            : BigInt.from(
                DateTime.now().difference(_lastTurnAt!).inMilliseconds,
              ),
        visiblePending: _loadInFlight ? 1 : 0,
      );
      if (!mounted || generation != _prefetchGeneration) return;
      if (_lastPrefetchDecision?.reason != decision.reason) {
        setState(() => _lastPrefetchDecision = decision);
      }
      if (decision.allowed) break;
      // 3 秒 backstop 之后判决必然放行（上游保证）。问到 4 秒还拦着，
      // 说明是判决本身出了问题，不是「还没到点」—— 退场而不是死循环。
      if (round > 80) {
        debugPrint('[local-debug] 预取放弃：判决持续拦截 ${decision.message}');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    // 判决放行了，这一轮真的开始跑 —— 把上一轮的收手理由清掉。
    // 不清的话，「预取在让路」会一直挂在界面上，看起来像预取再也没动过。
    if (_prefetchNote != null) setState(() => _prefetchNote = null);

    // 目标顺序 `+1, -1, +2, …`（同距离 forward 先），边界由上游函数处理。
    //
    // **窗口大小是刻意偏离上游的，而且理由不是「上游的页便宜」。**
    //
    // 上游全屏页预取的默认窗口是 `prefetch_forward = 12` / `prefetch_back = 4`
    // （`settings.rs:6065`，keep 各 +1）。它敢开这么大，是因为它的解码**一张只占一个核**：
    // 全屏解码主路径是 `image` crate（`canonical_image_loader.rs:453/466`
    // → zune-jpeg / png，都是单线程），**WIC 只是第二顺位 fallback**（:455/468，
    // 顺序被测试 `byte_fallback_order_is_image_then_wic_then_susie` 钉住），
    // 而 `wic_decoder.rs` 本身也是「全尺寸、单线程、不做解码侧缩放」。
    // 于是「6 张许可」在上游是**真并行**（6 个核），窗口开大 = 纯赚吞吐。
    // 上游单张解码其实也不快 —— 它快在**用并发把单张的慢藏起来**。
    //
    // **更要紧的是**：这套模型建立在「一张图一个核」上，而 `image` 的 avif 后端是
    // `dav1d::Decoder::new()`（`image-0.25.10/src/codecs/avif/decoder.rs:82`，
    // 默认 `n_threads = 0` = auto）—— **一条流吃满 16 核**（1→16 核只有 2.25×，
    // 见 §12.4）。**AVIF 会把上游那套模型同样打破**；我们整本都是 AVIF，
    // 所以**我们从一开始就没有那条路可走，这不是我们的实现缺陷**。
    //
    // 所以窗口按「用户读一页能备好几页」定，不照抄 12/4（那会变成一轮预取跑 8.7 秒、
    // 全程占着核）。而且串行之下**窗口不是瓶颈、吞吐才是**：用户读一页 2 秒，
    // 最多也就备好 3–4 页。
    //
    // 要把上游那条「并发换吞吐」的路在我们这边重新打开，唯一的钥匙是
    // **按优先级分配 dav1d 的线程数**（翻页全核 / 预取少核），而 `image` 不暴露
    // `dav1d::Settings`。见 `docs/v0.1-local-core.md` §12.6 末段。
    final targets = await localPrefetchTargets(
      pos: _current,
      n: _pages.length,
      forward: 2,
      back: 1,
    );
    if (!mounted || generation != _prefetchGeneration) return;
    for (var i = 0; i < targets.length; i++) {
      final target = targets[i];
      if (!mounted || generation != _prefetchGeneration) return;
      if (_prefetch.containsKey(target)) continue;

      // 每页之间重新问一次「用户在等吗」。用户完全可能在我们解上一页的时候翻页了 ——
      // 光靠开头的 generation 检查挡不住这种（那时循环已经在 await 里）。
      // 这不是「等一会儿再来」，而是**整轮退出**：下一轮由翻页完成后的
      // `_schedulePrefetch` 重新发起。
      final stats = await localPageLoadStats();
      if (!mounted || generation != _prefetchGeneration) return;
      final highRunning = stats.running - stats.runningNormal;
      if (highRunning > 0 || stats.waiting > 0) {
        final why =
            '让路：用户在等（翻页在跑 $highRunning 张 / 排队 ${stats.waiting} 个），'
            '本轮还剩 ${targets.length - i} 页没备';
        debugPrint('[local-debug] 预取$why');
        setState(() => _prefetchNote = why);
        return;
      }

      await _prefetchPage(id, target);
    }
  }
  /// 解好并建好一页，收进预取缓存。任何失败都**静默放弃**：
  /// 预取是机会主义行为，它失败不该在界面上留下错误，更不能顶掉当前页。
  Future<void> _prefetchPage(BigInt id, int index) async {
    // 全尺寸一页是 179 MB 位图，预取三页就是 500 MB —— 那种档位不预取。
    if (!_displaySizedDecode) return;
    // 同一页只允许一路在解：老一轮被 generation 退场后，它 await 的那一页
    // 仍在解；新一轮如果瞄准同一页，必须跳过而不是叠上去。
    if (_prefetchInFlight.containsKey(index)) return;
    final task = _prefetchPageTask(id, index);
    _prefetchInFlight[index] = task;
    try {
      await task;
    } finally {
      _prefetchInFlight.remove(index);
    }
  }
  Future<void> _prefetchPageTask(BigInt id, int index) async {
    final targetWidth = _targetDecodeWidth();
    final stale = _prefetch[index];
    if (stale != null && stale.targetWidth == targetWidth) return;

    final swDecode = Stopwatch()..start();
    final LocalPageDecodeResult result;
    try {
      result = await localPagePixels(
        id: id,
        index: index,
        targetWidth: targetWidth,
        // 预取可以等：`Normal` 拿不到那 2 张留给 `High` 的许可，所以
        // 「预取占满许可、用户翻页排在后面」在结构上不会发生。
        priority: LocalPageLoadPriority.normal,
        contract: LocalPageLoadContract.sequential,
      );
    } catch (e) {
      debugPrint('[local-debug] 预取失败 index=$index: $e');
      return;
    }
    final pixels = result.pixels;
    if (pixels == null) {
      // 归外壳、解不开、或被更新的跳页作废 —— 三种都留给翻页时按正常流程处理。
      // 预取是机会主义行为：它失败不该在界面上留下错误，更不能顶掉当前页。
      return;
    }
    final decode = swDecode.elapsed;

    final swPack = Stopwatch()..start();
    final image = await _imageFromRgba(
      pixels.rgba,
      pixels.width,
      pixels.height,
    );
    final pack = swPack.elapsed;

    if (!mounted) {
      image.dispose();
      return;
    }
    _storePrefetch(
      _PrefetchedPage(
        index: index,
        targetWidth: targetWidth,
        image: image,
        width: pixels.width,
        height: pixels.height,
        sourceWidth: pixels.sourceWidth,
        sourceHeight: pixels.sourceHeight,
        decode: decode,
        pack: pack,
      ),
    );
    debugPrint(
      '[local-debug] 预取完成 index=$index '
      '解${decode.inMilliseconds} 图${pack.inMilliseconds}ms '
      '${pixels.width}x${pixels.height}',
    );
  }
  int _totalPrefetchBytes() =>
      _prefetch.values.fold(0, (sum, p) => sum + p.bytes);
  /// 取走一页预取结果。尺寸对不上就丢掉（宁可重解也不能显示错尺寸）。
  _PrefetchedPage? _takePrefetch(int index) {
    final hit = _prefetch.remove(index);
    if (hit == null) return null;
    if (hit.targetWidth != _targetDecodeWidth()) {
      hit.dispose();
      return null;
    }
    return hit;
  }
  /// 丢掉全部预取。翻页宽度、解码器开关、会话变化之后都要走这一趟 ——
  /// 拿着旧尺寸的位图显示，比慢更糟。
  void _clearPrefetch() {
    _prefetchGeneration++;
    for (final page in _prefetch.values) {
      page.dispose();
    }
    _prefetch.clear();
  }
  /// 逐页读一遍并计时。这条曲线是 `docs/v0.1-local-core.md` §7 那把尺子：
  /// 近似常量 ⇒ 归档支持按需 seek；随 N 线性增长 ⇒ 实际在解压整段。
  ///
  /// 注意：这里量的是**过桥 + 编码字节**的耗时，不含解码与上屏；
  /// 绝对值比 Rust 侧探针高，但**增长形态**仍然说明问题。
  Future<void> _sweep() async {
    final id = _sessionId;
    if (id == null || _pages.isEmpty) return;

    // 逐页计时量的是读页耗时，60 ms 量级的信号扛不住旁边一个吃满核的 dav1d ——
    // 先让预取退场，否则这把尺子会量到别人的噪声。
    _clearPrefetch();

    setState(() {
      _busy = true;
      _sweepMs = null;
      _sweepTotalMs = null;
    });

    final swAll = Stopwatch()..start();
    final out = <double>[];
    try {
      for (var i = 0; i < _pages.length; i++) {
        final sw = Stopwatch()..start();
        await localPageBytes(id: id, index: i);
        sw.stop();
        out.add(sw.elapsedMicroseconds / 1000.0);
      }
      swAll.stop();
      if (!mounted) return;
      setState(() {
        _sweepMs = out;
        _sweepTotalMs = swAll.elapsedMicroseconds / 1000.0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '逐页计时中断：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _schedulePrefetch();
    }
  }
}
