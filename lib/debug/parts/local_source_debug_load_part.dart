part of '../local_source_debug_page.dart';

// ignore_for_file: invalid_use_of_protected_member
// 从 class _LocalSourceDebugPageState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。
extension _LocalSourceDebugLoadPart on _LocalSourceDebugPageState {
  /// 释放当前页的两条显示资源，连同预取缓存。
  ///
  /// 外壳路径的位图挂在全局图片缓存里，要 `evict`；Rust 路径的是我们自己的
  /// `ui.Image`，要 `dispose`。**两条都必须走这里** —— 一页 44.8 MPix 是 179 MB，
  /// 漏掉任一边都会在翻几页之后把内存顶上去（曾观测到 RSS 592 MB）。
  /// 预取缓存也在这里统一丢：它是「另一个会话 / 另一本书」的位图，留着没有意义。
  void _releaseCurrentImage() {
    final provider = _provider;
    _provider = null;
    unawaited(provider?.evict());

    final rustImage = _rustImage;
    _rustImage = null;
    rustImage?.dispose();

    _clearPrefetch();
  }
  Future<void> _refreshProbe() async {
    final n = localOpenSessionCount();
    if (mounted) setState(() => _probeCount = n);
  }
  Future<void> _closeCurrent({bool silent = false}) async {
    final id = _sessionId;
    if (id == null) return;
    localClose(id: id);
    // 解绑是大位图的唯一释放途径（见类注释第 2 条）。
    _releaseCurrentImage();
    if (!mounted) return;
    setState(() {
      _sessionId = null;
      _info = null;
      _pages = const [];
      _currentBytes = null;
      _currentBytesIndex = null;
      _stage = null;
      _history.clear();
      _sweepMs = null;
      _sweepTotalMs = null;
      if (!silent) _rejection = null;
    });
    await _refreshProbe();
  }
  Future<void> _openPath(String path) async {
    // 打点的目的是**让下一次原生崩溃有现场**。
    // 起因：一次 `zephyr has stopped working` 在 flutter run 控制台里
    // 一行输出都没有（无 Dart 异常、Windows 事件日志也无记录），
    // 事后完全无法判断崩溃前走到哪一步。这条日志就是给那种情况留的指纹。
    final swOpen = Stopwatch()..start();
    debugPrint('[local-debug] open 开始: $path');

    setState(() {
      _busy = true;
      _error = null;
      _rejection = null;
    });

    try {
      // 先关掉上一个会话：调试页要能体现「换书 = 释放」。
      await _closeCurrent(silent: true);

      final result = await openLocalSource(path: path);

      final rejection = result.rejection;
      if (rejection != null) {
        debugPrint(
          '[local-debug] open 被拒绝: ${rejection.kind} ${rejection.message}',
        );
        if (!mounted) return;
        setState(() {
          _rejection = rejection;
          _info = null;
          _pages = const [];
        });
        return;
      }

      final info = result.source!;
      debugPrint(
        '[local-debug] open 成功(未取页): id=${info.id} '
        'kind=${info.kind} pages=${info.pageCount} '
        'bytes=${info.totalBytes} ${swOpen.elapsedMilliseconds}ms',
      );

      final pages = await localSourcePages(id: info.id);
      debugPrint(
        '[local-debug] 取页完成: ${pages.length} 条 '
        '${swOpen.elapsedMilliseconds}ms',
      );

      if (!mounted) return;
      // 换书了：上一本解好的位图一页都不能留。
      _clearPrefetch();
      setState(() {
        _sessionId = info.id;
        _info = info;
        _pages = pages;
        _current = 0;
        _currentBytes = null;
        _currentBytesIndex = null;
        _stage = null;
        _history.clear();
        _sweepMs = null;
        _sweepTotalMs = null;
      });
      await _refreshProbe();
      if (pages.isNotEmpty) {
        await _loadPage(0);
      } else {
        // 0 页必须留下声音：否则「没反应」和「崩溃」在日志里长得一样。
        debugPrint(
          '[local-debug] 打开成功但 0 页 —— '
          '归档里没有任何 v0.1 能识别的页面: $path',
        );
      }
      debugPrint('[local-debug] open 流程结束 ${swOpen.elapsedMilliseconds}ms');
    } catch (e, st) {
      debugPrint('openLocalSource failed: $e\n$st');
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> _pickFolder() async {
    final path = await getDirectoryPath();
    if (path == null || path.isEmpty) return;
    await _openPath(path);
  }
  Future<void> _pickArchive() async {
    const group = XTypeGroup(
      label: '漫画归档',
      extensions: ['cbz', 'cbr', 'zip', 'rar'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    await _openPath(file.path);
  }
  /// 目标解码宽度（物理像素）。
  ///
  /// 取预览区宽度 × 设备像素比；还没布局过就退回窗口宽度的估算值。
  /// 解码宽度只影响**显示**，不影响从归档里读出来的编码字节。
  int? _targetDecodeWidth() {
    if (!_displaySizedDecode) return null;
    final media = MediaQuery.maybeOf(context);
    if (media == null) return null;
    final logical = _viewerWidth > 0 ? _viewerWidth : media.size.width * 0.6;
    final px = (logical * media.devicePixelRatio).round();
    return px.clamp(64, 8192);
  }
  /// 翻页入口：按 `_decoderMode` 决定让谁解。
  ///
  Future<void> _loadPage(int index, {bool force = false}) async {
    final id = _sessionId;
    if (id == null || index < 0 || index >= _pages.length) return;
    if (!force && _currentBytesIndex == index && _rustImage != null) {
      setState(() => _current = index);
      return;
    }
    if (!force && _currentBytesIndex == index && _currentBytes != null) {
      setState(() => _current = index);
      return;
    }

    // 同一页只允许一路翻页在跑。快速连点会让两个 `_loadPage(index)` 同时进来，
    // 都过不了上面的守卫（`_currentBytesIndex` 还没变）。实测（2026-09-16）：
    // 两路一起挤进「等在跑的预取」，预取产出只够一路拿到命中，另一路
    // 「没产出，掉回正常翻页」把同一页**再解一遍**（index=4 / 21 各一次）。
    // `force`（重读语义）刻意不参与去重。
    final existingTurn = _turnInFlight[index];
    if (existingTurn != null && !force) {
      await existingTurn;
      return;
    }
    final task = _loadPageTask(id, index, force: force);
    if (!force) {
      _turnInFlight[index] = task;
    }
    try {
      await task;
    } finally {
      if (!force) _turnInFlight.remove(index);
    }
  }
  /// `auto` 的语义是「**Rust 优先，格式归外壳时退回**」，不是「随便挑一个能用的」。
  /// 只有 Rust 明确回答 `shellOnlyFormat` 才算「这页归外壳」；解码失败是另一回事，
  /// 那种情况就地报错 —— 偷偷换条路会把失败藏起来，而失败正是这张页面要显示的东西。
  Future<void> _loadPageTask(
    BigInt id,
    int index, {
    required bool force,
  }) async {
    // 这两个是给预取判决用的状态（上游 `last_prefetch_scroll_at` 与
    // `visible_state_pending` 的对应物）。判决本身在 Rust 侧，这里只报事实。
    _lastTurnAt = DateTime.now();
    _loadInFlight = true;

    // ── 用户要翻页了：立刻让在跑的预取退场 ──
    //
    // 照的是 mImageViewer `update_prefetch_window` 的做法（`src/app.rs:55192`）：
    // **当前页还没有可显示内容的时候，取消其它 pending，并且连新的先読み也不发**。
    // 上游把这段撤过（判断「有 High 预留枠就不需要」），实机立刻变差：
    // 页面完成 p50 **148 ms → 396 ms**；理由是「已经拿到许可的先読み 会 commit 到
    // 一段不可中断的读取上」。所以这不是保守，是被数据逼回来的一行。
    //
    // 我们这边比上游更硬：dav1d 一条流几乎不能并行（实测 1 核 610–667 ms /
    // 16 核 269–295 ms，1→16 只有 2.25×），所以「预取与翻页并发」不是分核，
    // 而是**两边都慢近一倍**。观测到的正是这个：预取单独跑 431.6 ms，
    // 而它与翻页并发时，翻页那一次报 572–648 ms。
    //
    // 正在跑的那一页**取消不掉**（dav1d 一次调用不可中断，`acquire_cancellable`
    // 只覆盖「等许可」阶段）—— 但它跑完就会看到代号变了而退出循环，
    // 不会再发起下一页。这与上游 `pending.cancel()` 的覆盖面一致。
    _prefetchGeneration++;
    _prefetchNote = null;

    // 相邻页 = 顺序翻页；跨页与「重读当前页」= 跳页。
    //
    // 这个区分交给 Rust 调度器（`FsPageLoadContract`）：`LatestSeek` 会把同一会话里
    // **还在排队**的旧请求作废 —— 用户已经改主意了，中间那些页读完也没人看。
    // 而 `Sequential` 永不作废：连翻三页就是三页都要，中间那页用户真的看过。
    final contract = (index - _current).abs() == 1
        ? LocalPageLoadContract.sequential
        : LocalPageLoadContract.latestSeek;

    // 预取命中：翻页路径上只剩下「换个引用 + 画一帧」。
    // `force`（重读本页 / 切开关）刻意绕过它 —— 那是「立刻重新解一遍」的语义。
    if (!force) {
      final hit = _takePrefetch(index);
      if (hit != null) {
        _presentPrefetched(index, hit);
        _loadInFlight = false;
        return;
      }
      // 翻到了「正在预取的那一页」：等在跑的那一路，而不是再解一遍。
      // 让路机制只挡「发起下一页」，挡不住已经 in-flight 的那路 ——
      // 观测到的正是这个洞：翻页 699 ms + 预取 829 ms，同一页并发解两次。
      // 预取那路万一没产出（解失败 / 单页超预算），掉回正常翻页路径重解。
      final inFlight = _prefetchInFlight[index];
      if (inFlight != null) {
        final swWait = Stopwatch()..start();
        debugPrint('[local-debug] 翻页目标正在预取，等在跑的那一路 index=$index');
        await inFlight;
        final waited = swWait.elapsed;
        debugPrint(
          '[local-debug] 等预取完成 index=$index 等${waited.inMilliseconds}ms',
        );
        final hitAfterWait = _takePrefetch(index);
        if (hitAfterWait != null) {
          _presentPrefetched(
            index,
            hitAfterWait,
            waitedWhilePrefetching: waited,
          );
          _loadInFlight = false;
          unawaited(_refreshLoadStats());
          return;
        }
        debugPrint('[local-debug] 在跑的预取没产出，掉回正常翻页 index=$index');
      }
    }

    try {
      if (_decoderMode != _DecoderMode.shell) {
        final settled = await _loadPageViaRust(id, index, contract: contract);
        if (settled) return;
        debugPrint('[local-debug] Rust 判定这页归外壳，退回外壳路径 index=$index');
      }
      await _loadPageViaShell(id, index);
    } finally {
      // 出图了才算「可见区就绪」。预取的 100 ms 静默期是从**上一次翻页**算起的，
      // 不是从这里算起，所以不需要在这里再加延迟。
      _loadInFlight = false;
      unawaited(_refreshLoadStats());
    }
  }
  /// 外壳路径：把**编码字节**交给 Flutter 引擎解。
  ///
  /// 这是最早的形态，留着有两个理由：引擎认识的格式（jpg / png / …）走这条更省内存
  /// （能按显示尺寸解，不必全尺寸 RGBA 过桥），而且两条路径的耗时需要有个对照。
  Future<void> _loadPageViaShell(BigInt id, int index) async {
    final swAll = Stopwatch()..start();
    debugPrint('[local-debug] 读页开始 index=$index');

    // ── 第 1 段：读页（归档 → Rust → FRB → Dart 字节）──
    final swRead = Stopwatch()..start();
    final Uint8List bytes;
    try {
      bytes = await localPageBytes(id: id, index: index);
    } catch (e) {
      debugPrint('[local-debug] 读页失败 index=$index: $e');
      if (!mounted) return;
      setState(() => _error = '读第 $index 页失败：$e');
      return;
    }
    swRead.stop();
    final read = swRead.elapsed;
    debugPrint(
      '[local-debug] 读页完成 index=$index ${bytes.length} B '
      '${read.inMilliseconds}ms（解码前）',
    );
    if (!mounted) return;

    // ── 第 2 段：解码。解码宽度决定像素量，像素量决定解码与上屏的成本。──
    final targetWidth = _targetDecodeWidth();
    // 显式标注类型：`MemoryImage` 与 `ResizeImage` 的三元表达式会被推断成 `Object`。
    final ImageProvider<Object> provider = targetWidth == null
        ? MemoryImage(bytes)
        : ResizeImage(
            MemoryImage(bytes),
            width: targetWidth,
            allowUpscaling: false,
          );
    final mode = targetWidth == null ? '全尺寸' : '显示 ${targetWidth}px';

    final previous = _provider;
    _provider = provider;
    unawaited(previous?.evict());

    final swDecode = Stopwatch()..start();
    final stream = provider.resolve(ImageConfiguration.empty);
    var handled = false;

    void finish({
      required ui.Image? image,
      required Duration decode,
      required bool cacheHit,
      required bool isError,
      String? errorText,
    }) {
      if (handled || !mounted) return;
      handled = true;
      if (isError) {
        setState(() {
          _current = index;
          _currentBytes = bytes;
          _currentBytesIndex = index;
          _error = _explainDecodeFailure(index, bytes.length, errorText);
        });
        return;
      }

      // 第 3 段：解码完成 → 含该图的下一帧绘制结束。含纹理上传与首帧绘制。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final total = swAll.elapsed;
        final paint = total - read - decode;
        final width = image?.width ?? 0;
        final height = image?.height ?? 0;
        setState(() {
          _current = index;
          _currentBytes = bytes;
          _currentBytesIndex = index;
          // 上一页失败留下的说明要清掉，否则翻到好页也还挂着红字。
          _error = null;
          _stage = _StageRow(
            index: index,
            mode: mode,
            read: read,
            decode: decode,
            // 外壳路径没有「位图字节 → ui.Image」这一步：引擎一步到位。
            pack: Duration.zero,
            paint: paint.isNegative ? Duration.zero : paint,
            total: total,
            width: width,
            height: height,
            cacheHit: cacheHit,
          );
          _history.insert(0, _stage!);
          if (_history.length > 6) _history.removeLast();
        });
        debugPrint(
          '[local-debug] 翻页完成 index=$index $mode '
          '读${read.inMilliseconds} 解${decode.inMilliseconds} '
          '屏${paint.inMilliseconds} 合${total.inMilliseconds}ms '
          '${width}x$height',
        );
      });
    }

    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, synchronousCall) {
        swDecode.stop();
        // 同步回调 = 命中 Flutter 图片缓存，这一次没有真的解码。
        finish(
          image: info.image,
          decode: synchronousCall ? Duration.zero : swDecode.elapsed,
          cacheHit: synchronousCall,
          isError: false,
        );
        stream.removeListener(listener);
      },
      onError: (error, stackTrace) {
        debugPrint('decode page $index failed: $error');
        finish(
          image: null,
          decode: swDecode.elapsed,
          cacheHit: false,
          isError: true,
          errorText: error.toString(),
        );
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }
  /// Rust 路径：`local_page_pixels` —— Rust 解码后把 RGBA 交给 Dart 上屏。
  ///
  /// 返回值是「这件事办完了吗」：`false` 表示 Rust **明确回答这页归外壳**
  /// （`shellOnlyFormat`），调用方该退回外壳路径。这不是错误，是格式归属 ——
  /// 归属与失败必须分开，否则 `auto` 会退化成「随便挑一条能走的路」。
  ///
  /// ## 计时口径与外壳路径不同，别直接比
  ///
  /// 这里「解码」= Rust 解码器 **+ FRB 过桥**（字节量级 = 位图大小），
  /// 读页那一段并了进来（所以 `read` 记 0）；「建图」= `decodeImageFromPixels`。
  /// **Rust 侧解码本身的单价从 Dart 侧量不到**，要用
  /// `cargo run -p rossi_local_core --bin scale_probe` 量。
  ///
  /// ## `targetWidth` 不是可选优化
  ///
  /// 不给宽度就是原尺寸：44.8 MPix 的页解出 170.8 MB 位图，实测这一整段
  /// 要 1526 ms，而 Rust 侧纯解码只要 267 ms —— **83% 花在搬那 170 MB 上**。
  /// 给了宽度之后位图缩到几 MB，这一段跟着掉到 300–400 ms 量级。
  Future<bool> _loadPageViaRust(
    BigInt id,
    int index, {
    required LocalPageLoadContract contract,
  }) async {
    final swAll = Stopwatch()..start();
    final targetWidth = _targetDecodeWidth();

    // 开始解码之前先看一眼许可：预取正占着几张？这一趟解码会跟它抢核，
    // 抢到的结果是**两边都慢**（dav1d 一条流几乎不并行），所以把它记在行上。
    final beforeStats = await localPageLoadStats();
    final concurrentPrefetch = beforeStats.runningNormal;

    final swBridge = Stopwatch()..start();
    debugPrint(
      '[local-debug] Rust 解码开始 index=$index target=$targetWidth '
      '并发的预取=$concurrentPrefetch 许可在跑=${beforeStats.running}'
      '（预取 ${beforeStats.runningNormal}）等 ${beforeStats.waiting}',
    );

    final LocalPageDecodeResult result;
    try {
      result = await localPagePixels(
        id: id,
        index: index,
        targetWidth: targetWidth,
        // 用户此刻在等这一页：`High`。调度器为此留了 2 张许可**不给**预取 ——
        // 「预取不会拖慢翻页」在结构上就是这么成立的，不靠调参。
        priority: LocalPageLoadPriority.high,
        contract: contract,
      );
    } catch (e) {
      debugPrint('[local-debug] Rust 解码调用失败 index=$index: $e');
      return false;
    }
    swBridge.stop();

    final pixels = result.pixels;
    final failure = result.failure;

    if (pixels == null) {
      if (failure?.kind == LocalDecodeFailureKind.shellOnlyFormat) {
        return false;
      }
      if (failure?.kind == LocalDecodeFailureKind.cancelled) {
        // 还没轮到就被更新的跳页取代了。**这不是错误** —— 这一页完全可能解得出，
        // 只是没人要了。报成失败会把用户误导成「这本解不了」。
        debugPrint('[local-debug] 请求已作废 index=$index：${failure?.message}');
        return true;
      }
      debugPrint('[local-debug] Rust 解码失败 index=$index: ${failure?.message}');
      if (!mounted) return true;
      setState(() {
        _current = index;
        _error = '第 $index 页 Rust 解码失败。\n${failure?.message ?? '未知原因'}';
      });
      return true;
    }

    final swPack = Stopwatch()..start();
    final decoded = await _imageFromRgba(
      pixels.rgba,
      pixels.width,
      pixels.height,
    );
    swPack.stop();

    if (!mounted) {
      decoded.dispose();
      return true;
    }

    final stale = _rustImage;
    _rustImage = decoded;
    final staleProvider = _provider;
    _provider = null;
    unawaited(staleProvider?.evict());
    stale?.dispose();

    // 这里必须 setState：`RawImage` 不像 `Image` 那样订阅 ImageStream，
    // 少了这一句新位图根本不会被画出来，要等下一次**别的**原因触发的重建。
    // 实测那种「等」能长到 3.9 s —— 用户不动鼠标就一直不出图，
    // 而且它会被算进下面的「上屏」，让这个数字看起来像上屏花了 3.9 s。
    setState(() {
      _current = index;
      _currentBytes = null;
      _currentBytesIndex = index;
      _error = null;
    });

    // 上屏：与外壳路径同一套口径 —— 等含这张图的下一帧画完再收尾。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_rustImage, decoded)) return;
      final total = swAll.elapsed;
      final bridge = swBridge.elapsed;
      final pack = swPack.elapsed;
      final paint = total - bridge - pack;
      setState(() {
        _stage = _StageRow(
          index: index,
          mode: 'Rust ${pixels.width}px',
          read: Duration.zero,
          decode: bridge,
          pack: pack,
          paint: paint.isNegative ? Duration.zero : paint,
          total: total,
          width: pixels.width,
          height: pixels.height,
          sourceWidth: pixels.sourceWidth,
          sourceHeight: pixels.sourceHeight,
          cacheHit: false,
          prefetchDuringDecode: concurrentPrefetch,
        );
        _history.insert(0, _stage!);
        if (_history.length > 6) _history.removeLast();
      });
      debugPrint(
        '[local-debug] Rust 翻页完成 index=$index '
        '桥${bridge.inMilliseconds} 图${pack.inMilliseconds} '
        '屏${paint.inMilliseconds} 合${total.inMilliseconds}ms '
        '${pixels.sourceWidth}x${pixels.sourceHeight}'
        '→${pixels.width}x${pixels.height}'
        '${concurrentPrefetch > 0 ? " [与 $concurrentPrefetch 张预取并发]" : ""}',
      );
      // 这一页已经上屏，用户接下来多半在读它 —— 这段时间正好用来解下一页。
      _schedulePrefetch();
    });
    return true;
  }
  /// 预取命中：翻页路径上没有任何解码、没有 `decodeImageFromPixels`。
  ///
  /// 这条路径**只可能出现在 Rust 解码路径上**：预取本身走的就是 `local_page_pixels`。
  /// 页面上必须同时报出「预取时花了多少」，否则这个 20 ms 看起来像是解码变快了 ——
  /// 实际是那 300 ms 被挪到了用户读上一页的时候。
  void _presentPrefetched(
    int index,
    _PrefetchedPage hit, {
    Duration? waitedWhilePrefetching,
  }) {
    final swAll = Stopwatch()..start();

    final stale = _rustImage;
    _rustImage = hit.image;
    final staleProvider = _provider;
    _provider = null;
    unawaited(staleProvider?.evict());
    stale?.dispose();

    setState(() {
      _current = index;
      _currentBytes = null;
      _currentBytesIndex = index;
      _error = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_rustImage, hit.image)) return;
      final total = swAll.elapsed;
      setState(() {
        _stage = _StageRow(
          index: index,
          mode: '预取命中',
          read: Duration.zero,
          decode: Duration.zero,
          pack: Duration.zero,
          paint: total,
          total: total,
          width: hit.width,
          height: hit.height,
          sourceWidth: hit.sourceWidth,
          sourceHeight: hit.sourceHeight,
          cacheHit: false,
          prefetchHit: true,
          prefetchCost: hit.decode + hit.pack,
          prefetchWait: waitedWhilePrefetching,
        );
        _history.insert(0, _stage!);
        if (_history.length > 6) _history.removeLast();
      });
      debugPrint(
        '[local-debug] 预取命中 index=$index 屏${total.inMilliseconds}ms '
        '（预取时解${hit.decode.inMilliseconds} 图${hit.pack.inMilliseconds}'
        '${waitedWhilePrefetching != null ? "，等预取${waitedWhilePrefetching.inMilliseconds}ms" : ""}）',
      );
      _schedulePrefetch();
    });
  }
  Future<ui.Image> _imageFromRgba(Uint8List rgba, int width, int height) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }
  /// 刷新调度器快照。翻完一页调一次就够 —— 它不是实时表，是「此刻许可怎么分的」。
  Future<void> _refreshLoadStats() async {
    final stats = await localPageLoadStats();
    if (!mounted) return;
    setState(() => _loadStats = stats);
  }
  String _loadStatsLabel() {
    final stats = _loadStats;
    if (stats == null) return '—';
    final busy = stats.running + stats.cancelling;
    return '$busy/${stats.totalLimit} 张在用'
        '（${stats.runningNormal} 张是预取；预留 ${stats.highReserved} 张给翻页），'
        '${stats.waiting} 个在等';
  }
}
