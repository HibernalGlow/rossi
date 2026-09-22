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
    try {
      final next = await fileManagerSearch(id: id);
      if (!mounted || serial != _searchSerial) return;
      // 遍历期间用户可能已经改了词或切走：条件签名一变，这批结果就不是现在要看的了。
      if (_searchSignatureOf(next) != _searchSignature) {
        // ignore: invalid_use_of_protected_member
        setState(() => _searchRunning = false);
        return;
      }
      // ignore: invalid_use_of_protected_member
      setState(() {
        _searchRunning = false;
        _acceptSnapshot(next);
      });
    } catch (error) {
      if (!mounted || serial != _searchSerial) return;
      // ignore: invalid_use_of_protected_member
      setState(() => _searchRunning = false);
      _showError(error);
    }
  }
  Future<void> _cancelSearch() async {
    final id = _sessionId;
    if (id == null) return;
    // 只发中止请求：剩下的交给 `_runSearch` 那条 future，它会带着
    // `cancelled` 标记正常返回，界面据此说明结果是部分扫过的。
    await fileManagerCancelSearch(id: id);
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
  /// 搜索选项行：递归开关 + 命中统计。窄卡片下横向滚动，与工具栏同一策略。
  Widget _buildSearchOptions(
    BuildContext context,
    FileManagerSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    final searching = snapshot.searchQuery.isNotEmpty;
    // 统计读的是快照：命中的正本在页签里，重建卡片也还在。
    final status = !searching || !snapshot.searchIncludeSubfolders
        ? null
        : _searchRunning
        ? '正在递归搜索…'
        : snapshot.searchActive
        ? [
            '命中 ${snapshot.searchMatched}',
            '已看 ${snapshot.searchScanned}',
            if (snapshot.searchTruncated) '已达上限',
            if (snapshot.searchCancelled) '已中止',
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
