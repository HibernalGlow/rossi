part of '../file_manager_card.dart';

// 从 class _FileManagerCardState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。
extension _FileManagerCardSearchPart on _FileManagerCardState {
  /// 丢掉还没发出的那一次搜索。
  ///
  /// 必须是任何显式动作的第一步：防抖里的搜索一旦晚于用户的点击发出，
  /// 它就会成为「最后发请求的人」，把点击那份快照当成陈旧结果丢掉 ——
  /// 表现是双击归档后 Reader 没起来。
  void _cancelPendingSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = null;
  }

  /// 搜索专用的提交通道：**不走 [_apply] 的 `_busy` 门控**。
  ///
  /// `_busy` 会同时禁用输入框、列表和整排工具键，那是给「一次动作把目录换掉」
  /// 准备的。增量搜索每敲一个字都要跑一遍，套用同一道闸就打不了字。
  /// 陈旧守卫（[_requestSerial]）仍然共用 —— 快照是全量状态，后发优先。
  /// [commit] 为真表示这是用户**主动**定下的搜索（回车、点历史词），才进历史；
  /// 防抖那一路只是边打边看，进历史会让下拉变成前缀垃圾堆。
  Future<void> _submitSearch(String query, {bool commit = false}) async {
    final id = _sessionId;
    if (id == null || _disposed) return;
    _cancelPendingSearch();
    _pendingSearchQuery = query;
    final serial = ++_requestSerial;
    // ignore: invalid_use_of_protected_member
    if (!_searchPending) setState(() => _searchPending = true);
    try {
      final snapshot = await fileManagerSetSearchQuery(id: id, query: query);
      if (!mounted || serial != _requestSerial) return;
      // ignore: invalid_use_of_protected_member
      setState(() {
        _searchPending = false;
        _acceptSnapshot(snapshot);
      });
      if (commit && query.trim().isNotEmpty) {
        await _recordSearchHistory(query);
      }
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      // ignore: invalid_use_of_protected_member
      setState(() => _searchPending = false);
      _showError(error);
    }
  }

  Future<void> _recordSearchHistory(String query) async {
    try {
      final history = await fileManagerRecordSearchHistory(query: query);
      if (!mounted || history.isEmpty) return;
      // ignore: invalid_use_of_protected_member
      setState(() {
        _searchHistory = history;
        _searchHistoryLoaded = true;
      });
    } catch (_) {
      // 历史是辅助信息：写不进去（SQLite 被占、路径没解析出来）不该让刚出结果的
      // 搜索冒一个红条，更不该把已经拿到的命中丢掉。
    }
  }

  Future<void> _clearSearchHistory() async {
    try {
      await fileManagerClearSearchHistory();
      if (!mounted) return;
      // ignore: invalid_use_of_protected_member
      setState(() => _searchHistory = const []);
      showInfoToast('已清空搜索历史', context: context);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  /// 「递归搜索模式」：只在**确实有查询**且**开了含子目录**时成立。
  ///
  /// 只搜当前一层时不需要另一套结果列表 —— 那一层的过滤已经由 Rust 的 `entries`
  /// 做完并带着子文件名/穿透投影，另起一份只会让两种视图各说各话。
  bool _isRecursiveSearch(FileManagerSnapshot snapshot) =>
      snapshot.searchQuery.isNotEmpty && snapshot.searchIncludeSubfolders;

  /// 会让一次递归搜索作废的条件集合。
  ///
  /// 逐项去挂触发点（类型筛选、排序、隐藏项、层数……）一定会漏，改成「条件变了
  /// 就跑一次」：签名一致时什么都不发，用户连续敲字也只在他真正改动的时刻重扫。
  String _searchSignatureOf(FileManagerSnapshot snapshot) {
    return [
      snapshot.activePath,
      snapshot.activeTabId,
      snapshot.searchQuery,
      snapshot.searchIncludeSubfolders,
      snapshot.searchMaxDepth,
      snapshot.searchInPath,
      snapshot.searchOrMode,
      snapshot.entryFilter.name,
      snapshot.sortField.name,
      snapshot.sortOrder.name,
      snapshot.directoriesFirst,
      snapshot.showHiddenFiles,
    ].join('\x1F');
  }

  /// 跑一次搜索。返回的是**快照**：命中由 Rust 写进当前页签，卡片只负责画它。
  ///
  /// 不参与 [_requestSerial]：那个序号管的是「别用旧快照盖掉新目录」，而遍历不改
  /// 目录。它用自己的序号，配合 [_searchSignature] 决定这一次还要不要画出来。
  Future<void> _runSearch(FileManagerSnapshot snapshot) async {
    final id = _sessionId;
    if (id == null || _disposed) return;
    final serial = ++_searchSerial;
    // ignore: invalid_use_of_protected_member
    setState(() => _searchRunning = true);
    _beginSearchFeedback(id);
    try {
      final next = await fileManagerSearch(id: id);
      if (!mounted || serial != _searchSerial) return;
      // 遍历期间用户可能已经改了词或切走：条件签名一变，这批结果就不是现在要看的了。
      if (_searchSignatureOf(next) != _searchSignature) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _searchRunning = false;
          _endSearchFeedback();
        });
        return;
      }
      // ignore: invalid_use_of_protected_member
      setState(() {
        _searchRunning = false;
        _endSearchFeedback();
        _acceptSnapshot(next);
      });
    } catch (error) {
      if (!mounted || serial != _searchSerial) return;
      // ignore: invalid_use_of_protected_member
      setState(() {
        _searchRunning = false;
        _endSearchFeedback();
      });
      _showError(error);
    }
  }

  /// 遍历开始：先等 250ms，确认它是**慢的那一种**再亮引导条。
  ///
  /// 「接着打字」走的是核心里的就地收窄，几十毫秒就回来 —— 为它闪一下进度条反而像卡了。
  /// 250ms 这个闸门借的是 MD3 对进度指示的分寸：短等待不打扰、长等待必须给出反馈。
  void _beginSearchFeedback(BigInt id) {
    _endSearchFeedback();
    _searchScannedLive = 0;
    _searchSlowTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || !_searchRunning) return;
      // ignore: invalid_use_of_protected_member
      setState(() => _searchSlow = true);
      _searchProgressPoll = Timer.periodic(
        const Duration(milliseconds: 300),
        (_) => _pollSearchProgress(id),
      );
    });
  }

  /// 遍历结束：收掉计时器与引导条。**不自己 setState** —— 调用方都在 setState 里。
  void _endSearchFeedback() {
    _searchSlowTimer?.cancel();
    _searchSlowTimer = null;
    _searchProgressPoll?.cancel();
    _searchProgressPoll = null;
    _searchProgressInFlight = false;
    _searchScannedLive = 0;
    _searchSlow = false;
  }

  /// 问一次「已扫多少条」。
  ///
  /// 慢盘上一次整库遍历要几十秒，数字自己往上走是「它在干活」最直接的证据；
  /// 读不到就当这一轮没有数字（进度是辅助信息，不该让搜索本身冒红）。
  Future<void> _pollSearchProgress(BigInt id) async {
    if (_searchProgressInFlight || !_searchRunning || _disposed) return;
    _searchProgressInFlight = true;
    try {
      final scanned = await fileManagerSearchProgress(id: id);
      if (mounted && _searchRunning && scanned != _searchScannedLive) {
        // ignore: invalid_use_of_protected_member
        setState(() => _searchScannedLive = scanned);
      }
    } catch (_) {
      // 同上：这一轮没有数字，下一次轮询会再试。
    } finally {
      _searchProgressInFlight = false;
    }
  }

  Future<void> _cancelSearch() async {
    final id = _sessionId;
    if (id == null) return;
    // 只发中止请求：剩下的交给 `_runSearch` 那条 future，它会带着
    // `cancelled` 标记正常返回，界面据此说明结果是部分扫过的。
    await fileManagerCancelSearch(id: id);
  }

  /// 层数档位在 chip 上循环：3 → 6 → 12 → 3（12 是核心 `MAX_SEARCH_DEPTH` 的夹值，
  /// 再深会被它压回来，所以不该由 Dart 自己发明第四个档位）。
  Future<void> _cycleSearchDepth(FileManagerSnapshot snapshot) async {
    final index = _searchDepths.indexOf(snapshot.searchMaxDepth);
    final next = _searchDepths[(index + 1) % _searchDepths.length];
    if (next == snapshot.searchMaxDepth) return;
    await _applySearchAction(
      (id) => fileManagerSetSearchMaxDepth(id: id, depth: next),
    );
  }

  /// 搜索行上的动作（条件开关、存为页签、回到目录）。
  ///
  /// 先丢掉还在排队的那一次键入：这些动作是用户**决定**下来的，不能让一个
  /// 晚到的防抖请求把它们的结果当成陈旧数据丢掉。
  Future<void> _applySearchAction(
    Future<FileManagerSnapshot> Function(BigInt id) action,
  ) async {
    _cancelPendingSearch();
    await _apply(action);
  }

  /// 可折叠搜索框：由工具栏的搜索键展开；已有生效查询时强制显示。
  ///
  /// 输入即搜（防抖 [_searchDebounceDuration]），回车只是把这一次提前提交。
  /// 匹配语法由 Rust 侧的 `search_query` 定义：空格分词求交、`-词` 排除、
  /// `"带空格"` 当一个词。
  Widget _buildSearchField(BuildContext context, FileManagerSnapshot snapshot) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      autofocus: snapshot.searchQuery.isEmpty,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: InputDecoration(
        isDense: true,
        hintText: '名称与路径 · 空格分词 · -排除 · “短语”',
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _searchRunning
            ? IconButton(
                tooltip: '中止递归搜索（保留已找到的结果）',
                icon: const Icon(Icons.stop_rounded, size: 16),
                onPressed: _cancelSearch,
              )
            : _searchPending
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: '清除搜索并收起',
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  _submitSearch('');
                  // ignore: invalid_use_of_protected_member
                  setState(() => _searchExpanded = false);
                },
              ),
        border: const OutlineInputBorder(),
      ),
      onChanged: _scheduleSearch,
      onSubmitted: _submitSearch,
    );
  }

  /// 遍历进行中的引导：MD3 的不定式线性进度条 + 实时「已扫 N 条」。
  ///
  /// 两个讲究：
  /// - **位置**在输入框正下方，而不是选项行末尾 —— 选项行横向滚动，窄卡片上它不在视口里；
  /// - **数字**来自核心真实计数（`fileManagerSearchProgress`），不是猜的百分比：
  ///   树的规模在遍历前是无从知道的，编一个进度百分比只会骗人。
  Widget _buildSearchProgress(BuildContext context) {
    final theme = Theme.of(context);
    final scanned = _searchScannedLive;
    final label = scanned > 0
        ? '正在递归搜索 · 已扫 ${_formatScannedCount(scanned)}'
        : '正在递归搜索…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(minHeight: 3),
        const SizedBox(height: 4),
        Text(
          '$label · 慢盘上要几十秒，结果扫完一次给出',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// 大数按中文读法折成「万」：14.6 万比 145827 好认，也不会把这一行撑开。
  String _formatScannedCount(int scanned) => scanned >= 10000
      ? '${(scanned / 10000).toStringAsFixed(1)} 万条'
      : '$scanned 条';

  /// 搜索选项行：递归开关 + 命中统计。窄卡片下横向滚动，与工具栏同一策略。
  Widget _buildSearchOptions(
    BuildContext context,
    FileManagerSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    final searching = snapshot.searchQuery.isNotEmpty;
    // 统计读的是快照：命中的正本在页签里，重建卡片也还在。
    //
    // 遍历进行中的说明**不在这里**：这一行是横向滚动的，窄卡片上它经常不在视口里，
    // 而「看不到任何动画」正是从那儿来的。进行中的引导搬到了输入框正下方
    // （`_buildSearchProgress`，那一行永远可见）。
    final status =
        !searching || !snapshot.searchIncludeSubfolders || _searchSlow
        ? null
        : snapshot.searchActive
        ? [
            '命中 ${snapshot.searchMatched}',
            '已看 ${snapshot.searchScanned}',
            if (snapshot.searchTruncated) '已达上限',
            if (snapshot.searchCancelled) '已中止',
            if (snapshot.searchDepthLimited)
              '第 ${snapshot.searchMaxDepth} 层以下未搜',
          ].join(' · ')
        : null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // 还没下查询时，这一行先当历史下拉用；一旦开始打字就让位给条件开关，
          // 否则边打边看会被一排旧词挤掉。
          if (snapshot.searchQuery.isEmpty && _searchHistory.isNotEmpty) ...[
            for (final history in _searchHistory) ...[
              ChoiceChip(
                label: Text(history),
                tooltip: '再搜一次「$history」',
                selected: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => _submitSearch(history, commit: true),
              ),
              const SizedBox(width: 6),
            ],
            ChoiceChip(
              label: const Text('清空历史'),
              selected: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _clearSearchHistory(),
            ),
            const SizedBox(width: 6),
          ],
          ChoiceChip(
            label: const Text('含子目录'),
            tooltip: '向下递归搜索，层数上限由 Rust 侧夹紧',
            selected: snapshot.searchIncludeSubfolders,
            visualDensity: VisualDensity.compact,
            onSelected: (enabled) => _applySearchAction(
              (id) => fileManagerSetSearchIncludeSubfolders(
                id: id,
                enabled: enabled,
              ),
            ),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('匹配路径'),
            tooltip: '除条目名外，连同它在搜索根之下的相对路径一起匹配',
            selected: snapshot.searchInPath,
            visualDensity: VisualDensity.compact,
            onSelected: (enabled) => _applySearchAction(
              (id) => fileManagerSetSearchInPath(id: id, enabled: enabled),
            ),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('任一词元'),
            tooltip: '多个词元之间取并集（默认全部都要命中）',
            selected: snapshot.searchOrMode,
            visualDensity: VisualDensity.compact,
            onSelected: (enabled) => _applySearchAction(
              (id) => fileManagerSetSearchOrMode(id: id, enabled: enabled),
            ),
          ),
          // 层数上限是「搜不到」与「没有」之间最容易混的一处，所以既露出当前档位，
          // 也给一个不用去设置页就能改的入口。
          if (snapshot.searchIncludeSubfolders) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text('层数 ≤${snapshot.searchMaxDepth}'),
              tooltip:
                  '点按切换递归层数（${_searchDepths.join(' / ')} 层）。'
                  '层数越大越慢：一次整库遍历在慢盘上要几十秒；太浅会漏掉更深的目录',
              // 停在默认档位时不着色：这一行只该在「你把它改离了默认」时跳出来。
              selected: snapshot.searchMaxDepth != _searchDefaultDepth,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _cycleSearchDepth(snapshot),
            ),
          ],
          // 只搜当前一层时零命中，用户不该靠猜才知道还能往下找：给一条明确出口。
          if (searching &&
              !snapshot.searchIncludeSubfolders &&
              snapshot.entries.isEmpty) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('在子目录里搜'),
              tooltip: '当前这一层没有命中；开着「含子目录」再搜一次（整库遍历在慢盘上要几十秒）',
              selected: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _applySearchAction(
                (id) => fileManagerSetSearchIncludeSubfolders(
                  id: id,
                  enabled: true,
                ),
              ),
            ),
          ],
          if (status != null) ...[
            const SizedBox(width: 8),
            Text(
              status,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          // 结果模式下这一屏画的不是目录：给一条明确的原路返回，以及 NeoView 的
          // 「保存搜索到页签」—— 把这次搜索留在一个受保护的页签里反复看。
          if (snapshot.searchActive) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('回到目录'),
              tooltip: '退出搜索结果，回到这个页签自己的目录',
              selected: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) =>
                  _applySearchAction((id) => fileManagerClearSearch(id: id)),
            ),
          ],
          if (snapshot.canSaveSearchTab) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('存为页签'),
              tooltip: '把这次搜索结果另存一个页签',
              selected: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _applySearchAction(
                (id) => fileManagerSaveSearchAsTab(id: id),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
