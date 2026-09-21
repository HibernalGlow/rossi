part of '../local_source_debug_page.dart';

// ignore_for_file: invalid_use_of_protected_member
// 从 class _LocalSourceDebugPageState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。
extension _LocalSourceDebugViewPart on _LocalSourceDebugPageState {
  Widget _toolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _pickFolder,
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('打开文件夹'),
          ),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _pickArchive,
            icon: const Icon(Icons.archive_outlined, size: 18),
            label: const Text('打开 CBZ / CBR'),
          ),
          OutlinedButton.icon(
            onPressed: _busy || _sessionId == null ? null : _sweep,
            icon: const Icon(Icons.timer_outlined, size: 18),
            label: const Text('逐页计时'),
          ),
          Tooltip(
            message: _displaySizedDecode
                ? '当前：解码到预览区像素尺寸。关掉可量全尺寸解码的原始成本。'
                : '当前：按归档里的原始尺寸解码（44.8 MPix 会解出 179 MB 位图）。',
            child: FilterChip(
              selected: _displaySizedDecode,
              avatar: Icon(
                _displaySizedDecode
                    ? Icons.fit_screen_outlined
                    : Icons.photo_size_select_actual_outlined,
                size: 18,
              ),
              label: Text(_displaySizedDecode ? '尺寸：显示' : '尺寸：全尺寸'),
              onSelected: (v) {
                setState(() => _displaySizedDecode = v);
                // 预取缓存是按目标宽度存的，尺寸一变就整批作废。
                _clearPrefetch();
                // 重新读当前页，让两种模式的数字直接可比。
                _loadPage(_current, force: true);
              },
            ),
          ),
          Tooltip(
            message:
                '谁负责解这一页。点按循环切换：\n'
                '自动 = Rust 优先，Rust 明确说「归外壳」时才退回引擎；\n'
                'Rust = 只走 Rust 解码器（avif 唯一能出图的形态）；\n'
                '外壳 = 编码字节过桥交给引擎，只有引擎认识的格式能出图。',
            child: ActionChip(
              avatar: const Icon(Icons.memory_outlined, size: 18),
              label: Text(_decoderMode.label),
              onPressed: () {
                final next = switch (_decoderMode) {
                  _DecoderMode.auto => _DecoderMode.rust,
                  _DecoderMode.rust => _DecoderMode.shell,
                  _DecoderMode.shell => _DecoderMode.auto,
                };
                setState(() => _decoderMode = next);
                // 换了解码器，旧预取是另一条路解出来的，不能混用。
                _clearPrefetch();
                // 立刻重读本页：这个开关的意义就是让两条路的数字当场可比。
                _loadPage(_current, force: true);
              },
            ),
          ),
          Tooltip(
            message: _prefetchEnabled
                ? '当前：翻完一页就顺手解下一页（±1），翻页时直接用已解好的位图。\n'
                      '关掉即可看到「每次翻页现解」的原始数字。\n'
                      '预取缓存：${_prefetch.length} 页 / '
                      '${(_totalPrefetchBytes() / 1e6).toStringAsFixed(1)} MB'
                : '当前：不预取，每次翻页都现解。\n'
                      '这本 AVIF 单页冷解码的地板是 270 ms（一个 tile、dav1d 已用满核），'
                      '所以「翻页 < 200 ms」只能靠预取把解码挪出翻页路径。',
            child: FilterChip(
              selected: _prefetchEnabled,
              avatar: Icon(
                _prefetchEnabled
                    ? Icons.bolt_outlined
                    : Icons.hourglass_empty_outlined,
                size: 18,
              ),
              label: Text(_prefetchEnabled ? '预取：开' : '预取：关'),
              onSelected: (v) {
                setState(() => _prefetchEnabled = v);
                if (!v) {
                  _clearPrefetch();
                } else {
                  _schedulePrefetch();
                }
              },
            ),
          ),
          OutlinedButton.icon(
            onPressed: _busy || _sessionId == null
                ? null
                : () => _loadPage(_current, force: true),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重读本页'),
          ),
          OutlinedButton.icon(
            onPressed: _sessionId == null ? null : () => _closeCurrent(),
            icon: const Icon(Icons.close, size: 18),
            label: const Text('关闭会话'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final n = localCloseAll();
              if (!mounted) return;
              _releaseCurrentImage();
              setState(() {
                _sessionId = null;
                _info = null;
                _pages = const [];
                _currentBytes = null;
                _currentBytesIndex = null;
                _stage = null;
                _history.clear();
              });
              debugPrint('closeAll released $n session(s)');
              await _refreshProbe();
            },
            icon: const Icon(Icons.layers_clear_outlined, size: 18),
            label: const Text('关闭全部'),
          ),
          if (_busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
  Widget _body() {
    final rejection = _rejection;
    if (rejection != null) return _rejectionView(rejection);

    final info = _info;
    if (info == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '选一个漫画文件夹，或一个 CBZ / CBR 归档。\n'
            '读取路径：Dart → FRB → rossi_local_core → 归档，每页都重开归档（不常驻句柄）。\n'
            '翻页后看「分段耗时」：读页 / 解码 / 上屏 各占多少。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoBar(info),
        if (_error != null)
          Container(
            width: double.infinity,
            color: Colors.red.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: const TextStyle(fontSize: 12)),
          ),
        _stageView(),
        if (_sweepMs != null) _sweepView(),
        const Divider(height: 1),
        Expanded(
          child: Row(
            children: [
              SizedBox(width: 240, child: _pageList()),
              const VerticalDivider(width: 1),
              Expanded(child: _viewer()),
            ],
          ),
        ),
      ],
    );
  }
  Widget _infoBar(LocalSourceInfo info) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          Text(
            '来源：${_kindLabel(info.kind)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text('会话 id：${info.id}'),
          Text('页数：${info.pageCount}'),
          Text('总字节：${info.totalBytes}'),
          Text(
            info.path,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
  static String _fmtMs(Duration d) =>
      (d.inMicroseconds / 1000.0).toStringAsFixed(1);
  /// 分段耗时面板 —— 本页存在的主要理由。
  ///
  /// 一个数字不够：`读页 60 ms` 看着没事，`解码 500 ms` 才是手感。三段分开才归得了因。
  Widget _stageView() {
    final stage = _stage;
    final cache = PaintingBinding.instance.imageCache;

    return Container(
      width: double.infinity,
      color: Colors.amber.withValues(alpha: 0.10),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stage == null)
            const Text(
              '翻页后这里会显示 读页 / 解码 / 上屏 的分段耗时。',
              style: TextStyle(fontSize: 12),
            )
          else ...[
            Text(
              '第 ${stage.index + 1} 页（${stage.mode}）：'
              '读页 ${_fmtMs(stage.read)} ms › '
              '解码 ${stage.prefetchHit ? "预取命中" : (stage.cacheHit ? "缓存命中" : "${_fmtMs(stage.decode)} ms")} › '
              '${stage.pack > Duration.zero ? "建图 ${_fmtMs(stage.pack)} ms › " : ""}'
              '上屏 ${_fmtMs(stage.paint)} ms · '
              '合计 ${_fmtMs(stage.total)} ms',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              '${stage.sourceWidth > 0 && stage.sourceWidth != stage.width ? "原始 ${stage.sourceWidth}×${stage.sourceHeight} → 解出 ${stage.width}×${stage.height}（像素 −${(stage.pixelSaving * 100).toStringAsFixed(1)}%）" : "解出 ${stage.width}×${stage.height}"}'
              '${stage.pixels > 0 ? " = ${(stage.pixels / 1e6).toStringAsFixed(1)} MPix" : ""}'
              '${stage.pixels > 0 ? " · RGBA 位图 ${(stage.bitmapBytes / 1e6).toStringAsFixed(1)} MB" : ""}'
              ' · 编码字节 ${_currentBytes?.length ?? 0} B'
              ' （${sniffImageFormat(_currentBytes)}）',
              style: const TextStyle(fontSize: 12),
            ),
            if (stage.prefetchHit) ...[
              const SizedBox(height: 3),
              Text(
                '本页是预取来的：翻页本身只花了「上屏」那 '
                '${_fmtMs(stage.paint)} ms，解码与建图都不在翻页路径上。\n'
                '成本没有消失 —— 这一页当初解了 '
                '${_fmtMs(stage.prefetchCost ?? Duration.zero)} ms（解码 + 建图），'
                '${stage.prefetchWait != null ? "而且翻页等了它 ${_fmtMs(stage.prefetchWait!)} ms（等在跑的那路，好过再解一遍）。\n" : ""}关掉「预取：开」再翻这一页，'
                '就能看到它的真实总价。',
                style: TextStyle(fontSize: 11, color: Colors.teal.shade700),
              ),
            ],
            if (stage.prefetchDuringDecode > 0) ...[
              const SizedBox(height: 3),
              Text(
                '本次解码开始时预取正占着 ${stage.prefetchDuringDecode} 张许可 —— '
                '这两个解码是**同时**跑的。dav1d 一条流几乎不能并行'
                '（1 核 610–667 ms / 16 核 269–295 ms），所以并发不是分核而是两边都慢，'
                '顺带把 Flutter 的帧生产也饿住（命中预取却还要等 100+ ms 出帧就是这个）。\n'
                '翻页时已经让预取退场（`_prefetchGeneration`），但**已经在解的那一页取消不掉** '
                '（dav1d 一次调用不可中断）—— 这是这个形态的残余成本，'
                '上游也是同一处妥协（`app.rs:55198`）。',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
              ),
            ],
            if (!_displaySizedDecode && stage.mode.startsWith('Rust')) ...[
              const SizedBox(height: 3),
              Text(
                '注：当前是「全尺寸」，Rust 路径会把整块 RGBA 搬过桥 —— '
                '这一页的位图 ${(stage.bitmapBytes / 1e6).toStringAsFixed(1)} MB 里，'
                '大部分时间花在搬运而不是解码。切到「显示」可直接对照。',
                style: const TextStyle(fontSize: 11, color: Colors.red),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '全局图片缓存：${(cache.currentSizeBytes / 1e6).toStringAsFixed(1)} MB '
              '/ 上限 ${(cache.maximumSizeBytes / 1e6).toStringAsFixed(0)} MB '
              '· 条目数 ${cache.currentSize}'
              '${stage.cacheHit ? "（本页命中缓存，未重新解码）" : ""}'
              '   ｜   预取缓存：${_prefetch.length} 页 / '
              '${(_totalPrefetchBytes() / 1e6).toStringAsFixed(1)} MB'
              '   ｜   解码许可：${_loadStatsLabel()}',
              style: TextStyle(
                fontSize: 11,
                color: cache.currentSizeBytes > cache.maximumSizeBytes
                    ? Colors.red
                    : Colors.grey,
              ),
            ),
            if (_lastPrefetchDecision != null) ...[
              const SizedBox(height: 3),
              Text(
                '预取门（Rust 侧判决，不是本地判断）：'
                '${_lastPrefetchDecision!.allowed ? "放行" : "拦截"}'
                ' · ${_lastPrefetchDecision!.message}'
                '   [${_lastPrefetchDecision!.reason}]',
                style: TextStyle(
                  fontSize: 11,
                  color: _lastPrefetchDecision!.allowed
                      ? Colors.teal.shade700
                      : Colors.grey.shade700,
                ),
              ),
            ],
            if (_prefetchNote != null) ...[
              const SizedBox(height: 3),
              Text(
                '预取收手：$_prefetchNote',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
              ),
            ],
            const SizedBox(height: 3),
            Text(
              // 「上屏」这个数要用这一行来读：它把「等下一帧」与「画这一帧」分开了。
              // 143 ms 的「上屏」若对应 raster 3 ms，那 140 ms 是**等**出来的
              // （CPU 被解码占满，Flutter 的帧生产排在后面），不是纹理上传慢。
              '最近一帧：${_frameCostLabel()}   ｜   '
              '（「上屏」= 换引用到下一帧画完，含等 vsync；'
              '真正画的耗时看 raster）',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          if (_history.length > 1) ...[
            const SizedBox(height: 6),
            const Text(
              '最近几次（新→旧）：',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            for (final row in _history)
              Text(
                '  第 ${(row.index + 1).toString().padLeft(3)} 页  ${row.mode.padRight(11)}'
                '  读 ${_fmtMs(row.read).padLeft(7)}  解 ${_fmtMs(row.decode).padLeft(8)}'
                '  装 ${_fmtMs(row.pack).padLeft(6)}  屏 ${_fmtMs(row.paint).padLeft(6)}'
                '  合 ${_fmtMs(row.total).padLeft(8)} ms'
                // 病根直接标在行上。让用户自己从「许可 1/6 在用」推出
                // 「所以这一行是被预取拖慢的」，是我不该让他做的事。
                '${row.prefetchDuringDecode > 0 ? "  ⟵ 解码时与预取并发（${row.prefetchDuringDecode} 张）" : ""}'
                '${row.prefetchWait != null ? "  ⟵ 等在跑的预取 ${_fmtMs(row.prefetchWait!)} ms（合并路径）" : ""}',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: row.prefetchDuringDecode > 0
                      ? Colors.orange.shade800
                      : null,
                ),
              ),
          ],
          const SizedBox(height: 3),
          const Text(
            '口径：读页含归档解压与 FRB 过桥；解码是编码字节→位图'
            '（Rust 路径这一段还会把 RGBA 搬过桥）；「装」是位图字节→ui.Image'
            '（只有 Rust 路径有）；上屏是解码完成→含该图的下一帧绘制完（含纹理上传）。'
            '解码宽度 = 预览区宽度 × 设备像素比，两条路径都遵守。\n'
            '「预取命中」那一行的解码/建图是 0，因为成本已经在你读上一页时付掉了 —— '
            '同一页关掉预取再翻一次，才是它的真实总价。',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
  Widget _pageList() {
    return ListView.builder(
      itemCount: _pages.length,
      itemBuilder: (context, i) {
        final p = _pages[i];
        final selected = i == _current;
        return ListTile(
          dense: true,
          selected: selected,
          leading: SizedBox(
            width: 36,
            child: Text(
              '${p.index + 1}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${p.size} B'),
          onTap: () => _loadPage(i),
        );
      },
    );
  }
  Widget _viewer() {
    // 0 页时**不要**留一个转圈：那看起来像「还在加载」，实际是「这本没页可看」。
    // 触发过一次真实误判 —— 归档里 30 张全是 `.avif`（v0.1 当时不认），
    // 用户看到的就是空列表 + 转圈，只能描述成「打开 zip 没反应/崩了」。
    if (_pages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '这个来源里**没有**可显示的页面（0 页）。\n'
            '常见原因：归档里全是 v0.1 不认识的格式，或图片都在被忽略的目录里（隐藏 / __MACOSX）。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 回填给下一次翻页估算解码宽度（首次翻页时还没布局，会退回窗口宽度估算）。
              _viewerWidth = constraints.maxWidth;
              final rustImage = _rustImage;
              final provider = _provider;
              if (rustImage == null && provider == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return InteractiveViewer(
                maxScale: 8,
                child: rustImage != null
                    // Rust 路径：位图已经解好了，直接画。
                    ? RawImage(image: rustImage, fit: BoxFit.contain)
                    : Image(
                        image: provider!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _current > 0 ? () => _loadPage(_current - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('${_current + 1} / ${_pages.length}'),
              IconButton(
                onPressed: _current < _pages.length - 1
                    ? () => _loadPage(_current + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    );
  }
  Widget _sweepView() {
    final ms = _sweepMs!;
    final sorted = [...ms]..sort();
    double pick(double q) =>
        sorted[((sorted.length - 1) * q).round().clamp(0, sorted.length - 1)];

    final first5 =
        ms.take(5).fold<double>(0, (a, b) => a + b) / ms.take(5).length;
    final last5 =
        ms.reversed.take(5).fold<double>(0, (a, b) => a + b) /
        ms.reversed.take(5).length;
    final ratio = first5 == 0 ? double.infinity : last5 / first5;

    final verdict = ratio < 2.0 ? '近似常量 → 按需 seek，未整段解压' : '随页序增长 → 疑似整段解压';

    return Container(
      width: double.infinity,
      color: Colors.blueGrey.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '逐页读一遍 ${ms.length} 页：合计 ${_sweepTotalMs!.toStringAsFixed(1)} ms  '
            '· p50 ${pick(0.5).toStringAsFixed(2)} ms  '
            '· p95 ${pick(0.95).toStringAsFixed(2)} ms  '
            '· max ${sorted.last.toStringAsFixed(2)} ms',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '前 5 页均值 ${first5.toStringAsFixed(2)} ms → 后 5 页均值 '
            '${last5.toStringAsFixed(2)} ms（×${ratio.toStringAsFixed(2)}）：$verdict',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            '口径：含 FRB 过桥与编码字节拷贝，不含解码与上屏；看增长形态，不看绝对值。',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
  Widget _rejectionView(LocalRejection r) {
    final (icon, hint) = switch (r.kind) {
      LocalRejectionKind.unknownFormat => (
        Icons.help_outline,
        '支持图片 / 视频文件、文件夹及 CBZ / CBR；暂不支持 7z、PDF。',
      ),
      LocalRejectionKind.rarSolid => (
        Icons.compress,
        '固实压缩：读第 N 页要先解压前 N-1 页，与「翻页 p95 ≤ 16.7ms」不相容。'
            '可用其它工具重新打包为 CBZ（zip）后重试。',
      ),
      LocalRejectionKind.rarNestedArchive => (
        Icons.account_tree_outlined,
        '归档里套了归档。v0.1 明确不展开嵌套——这是唯一会需要临时文件的场景。',
      ),
      LocalRejectionKind.rarEncrypted => (
        Icons.lock_outline,
        '加密归档：v0.1 不提供密码输入。',
      ),
      LocalRejectionKind.notFound => (Icons.link_off, '路径不存在或不可读。'),
      LocalRejectionKind.io => (Icons.error_outline, 'IO 或解析失败（含归档损坏）。'),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44),
            const SizedBox(height: 12),
            Text(
              '已被拒绝（${r.kind.name}）',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(r.message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => setState(() => _rejection = null),
              child: const Text('换一个'),
            ),
          ],
        ),
      ),
    );
  }
  String _kindLabel(LocalSourceKind kind) => switch (kind) {
    LocalSourceKind.folder => '散图文件夹',
    LocalSourceKind.zip => 'ZIP 归档',
    LocalSourceKind.rar => 'RAR 归档',
    LocalSourceKind.mediaFile => '图片 / 视频文件',
  };
}
