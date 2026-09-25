part of '../file_manager_card.dart';

// 从 class _FileManagerCardState 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。
extension _FileManagerCardSessionPart on _FileManagerCardState {
  /// 把全局开关的当前值同步到**活着的会话**上。
  ///
  /// 开关有两个入口（设置页、这张卡片），只在新建会话时注入的话，用户在设置里
  /// 关掉之后会「点了没反应」，要重启才生效。所以每次两者不一致就补一次设置，
  /// 由会话把新的值回写到快照里。
  Future<void> _syncRememberViewState(bool remember) async {
    final id = _sessionId;
    if (id == null || _disposed || _busy) return;
    if (_snapshot?.rememberViewState == remember) return;
    _syncedRememberViewState = remember;
    await _apply(
      (session) =>
          fileManagerSetRememberViewState(id: session, enabled: remember),
    );
  }

  Future<void> _startSession() async {
    if (_busy) return;
    if (_sessionId != null) {
      await _reload();
      return;
    }
    // ignore: invalid_use_of_protected_member
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final home = _persistedHomePath;
      final remember = _persistedRememberViewState;
      // 「自动恢复上次打开的页签」：读盘放在建会话**之前**，首个页签直接用上次
      // 那一份的第一个目录来建，省掉「先开默认目录、再搬过去」的那一下闪动。
      final restored = await _tabMemory.restore(enabled: _persistedRestoreTabs);
      if (_disposed) return;
      final id = await fileManagerCreate(
        // 「启动时默认打开主页」：开着时首个页签直接落在主页目录，
        // 关掉 / 没设主页时不传这个参数（判据见 [_startPath]）。
        // 上次开着多个页签时以恢复为准，两条的取舍见设置里的 restoreTabs。
        initialPath: restored == null ? _startPath : restored.paths.first,
        homePath: home.isEmpty ? null : home,
        // 目录级视图状态的正本在 Rust 的 `settings.db`，路径在启动期就解析好了
        // （`prepareSettingsDbPath`）；为 null ＝ 本次不记忆，浏览照常。
        settingsDbPath: preparedSettingsDbPath,
        rememberViewState: remember,
      );
      if (_disposed) {
        fileManagerClose(id: id);
        return;
      }
      // 会话已经带着这个值建起来了，别再补发一次。
      _syncedRememberViewState = remember;
      _sessionId = id;
      if (restored != null) await _restoreTabs(id, restored);
      // 会话一就绪就登记进「新页签」通道：别的地方（收藏 / 历史卡片的右键菜单）
      // 只有从这里才能拿到这个会话。登记的是 `this`，`dispose` 时按同一个对象注销。
      FileManagerTabBridge.instance.attach(this, _openPathInNewTab);
      await _reload();
    } catch (error) {
      _showError(error);
    }
  }

  /// 把恢复出来的**其余**页签补开出来，再把焦点放回上次那一个。
  ///
  /// 有意不走 [_apply]：这一段跑在会话刚建好、`_busy` 还是 `true` 的时候，
  /// 走 `_apply` 会被自己的忙状态挡掉（[_openPathInNewTab] 同一个理由）。
  /// 中间那几份快照也**不采纳** —— 它们是「还没切回上次那个页签」的过渡态，
  /// 采纳了就是当着用户的面一页一页蹦出来；末尾的 [_reload] 会给到最终那一帧。
  ///
  /// 单个页签开不出来就跳过它继续下一个：恢复出 5/6 个好过因为一个失效目录
  /// 整批放弃。而失效路径本身也不会抛 —— 核心会向上找到最近的、还在的父目录，
  /// 与 [_startPath] 那条是同一个兜底。
  Future<void> _restoreTabs(BigInt id, FileManagerTabSession session) async {
    FileManagerSnapshot? last;
    for (final path in session.paths.skip(1)) {
      if (_disposed) return;
      try {
        last = await fileManagerNewTab(id: id, path: path);
      } catch (_) {
        continue;
      }
    }
    final tabs = last?.tabs;
    if (_disposed || tabs == null || tabs.isEmpty) return;
    // 按**下标**取而不是按路径找：路径会被核心规范化（补斜杠、走符号链接），
    // 文本比对认不出它自己存出去的值；而下标在「按同一顺序 push 出来的列表」里
    // 一直是同一个页签。少开了几个就夹到末尾 —— 那已经是能给出的最好答案。
    final target = tabs[session.activeIndex.clamp(0, tabs.length - 1)].id;
    if (target == last!.activeTabId) return;
    try {
      await fileManagerActivateTab(id: id, tabId: target);
    } catch (_) {
      // 焦点没落回去只是「停在最后一个页签」，页签本身还在。
    }
  }

  /// 把某个目录设为主页：**先让核心确认，再落盘**。
  ///
  /// 顺序有意义 —— 核心（`set_home_path`）只接受真实存在的目录，落盘的必须是
  /// 它真正接受的那个路径。否则全局设置里会留下一个核心拒绝的路径，重启后
  /// 又被 `_startSession` 静默忽略，表现为「设置页写着有主页、卡片上却按不动」。
  ///
  /// 持久化里仍可能留着一个后来失效的路径（目录被删 / 移动盘没插），那种情况
  /// 由 UI 用「`_persistedHomePath` 非空但 `snapshot.homePath` 为空」判定失效。
  Future<void> _setHomePath(String path) async {
    final ok = await _apply((id) => fileManagerSetHomePath(id: id, path: path));
    if (!ok || !mounted) return;
    final applied = _snapshot?.homePath;
    if (applied == null) return;
    context.read<GlobalSettingCubit>().updateFileManagerSetting(
      (current) => current.copyWith(homePath: applied),
    );
    showSuccessToast(applied, title: '主页已设为', context: context);
  }

  Future<void> _clearHomePath() async {
    final ok = await _apply((id) => fileManagerSetHomePath(id: id, path: null));
    if (!ok || !mounted || _snapshot?.homePath != null) return;
    context.read<GlobalSettingCubit>().updateFileManagerSetting(
      (current) => current.copyWith(homePath: ''),
    );
    showInfoToast('已清除主页', context: context);
  }

  /// 文件操作的总开关（全局设置，跨重启保持）。
  ///
  /// 落盘之后立刻生效：卡片下一帧就会重建 —— [build] 里 `select` 了它。
  /// 关掉时顺手清空选中集合：留着它，下次打开开关会「复活」一批用户早就忘了的
  /// 选中项，而那时他多半只想重新选。
  Future<void> _setFileOperationsEnabled(bool enabled) async {
    context.read<GlobalSettingCubit>().updateFileManagerSetting(
      (current) => current.copyWith(fileOperations: enabled),
    );
    if (!enabled) await _clearSelection();
  }

  /// 主页菜单：把「回主页 / 设为主页 / 清除主页」三个动作收在主页键自己身上。
  ///
  /// 为什么不直接把右键当「设为主页」：那样「回主页」和「清除主页」在卡片上
  /// 都没有入口，用户只能去设置页里翻。菜单让三个动作都出现在它们作用的那个按钮上，
  /// 并且每一项按当前能力置灰（已在主页时不能重复设、没设过时不能清除）。
  Future<void> _openHomeMenu(FileManagerSnapshot snapshot) async {
    if (_busy) return;
    final box = _homeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final hasHome = snapshot.homePath != null;
    final selected = await FluentPopupMenu.show<_HomeAction>(
      context: context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      items: [
        FluentPopupMenuItem(
          value: _HomeAction.goHome,
          enabled: hasHome && !snapshot.isHome,
          title: const Text('回到主页'),
        ),
        FluentPopupMenuItem(
          value: _HomeAction.setHome,
          enabled: snapshot.canSetHome,
          title: const Text('把当前目录设为主页'),
        ),
        const FluentPopupMenuItem.divider(),
        FluentPopupMenuItem(
          value: _HomeAction.clearHome,
          enabled: hasHome,
          title: const Text('清除主页'),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case _HomeAction.goHome:
        await _apply((id) => fileManagerGoHome(id: id));
      case _HomeAction.setHome:
        await _setHomePath(snapshot.activePath);
      case _HomeAction.clearHome:
        await _clearHomePath();
    }
  }

  Future<void> _reload() async {
    final id = _sessionId;
    if (id == null) return;
    final serial = ++_requestSerial;
    // ignore: invalid_use_of_protected_member
    setState(() => _busy = true);
    try {
      final snapshot = await fileManagerSnapshot(id: id);
      if (!mounted || serial != _requestSerial) return;
      // ignore: invalid_use_of_protected_member
      setState(() {
        _acceptSnapshot(snapshot);
        _error = null;
        _busy = false;
      });
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      _showError(error);
    }
  }

  /// 「在文件管理新页签里打开 [path]」落到这张卡片上。
  ///
  /// 有意**不走** [_apply]：那个口径里有 `_busy` 与请求序号两道闸，是给
  /// 「用户在这张卡片上连续点」准备的。这里的调用方在**另一张卡片**上，
  /// 它既看不见也不该受这里的忙状态影响 —— 尤其 `_busy` 为真时 [_apply] 静默
  /// 返回 `false`，那会让调用方以为「文件管理面板没起来」，而它明明开着。
  ///
  /// 失败时由**这里**弹具体错误（只有这一层知道异常是什么），并回
  /// [FileManagerTabOpenOutcome.failed] 让调用方别再补一句笼统的失败提示。
  Future<FileManagerTabOpenOutcome> _openPathInNewTab(String path) async {
    final id = _sessionId;
    if (id == null || _disposed) return FileManagerTabOpenOutcome.noSession;
    try {
      final snapshot = await fileManagerNewTab(id: id, path: path);
      if (!mounted || _disposed) return FileManagerTabOpenOutcome.failed;
      // ignore: invalid_use_of_protected_member
      setState(() => _acceptSnapshot(snapshot));
      return FileManagerTabOpenOutcome.opened;
    } catch (error) {
      if (mounted) _showError(error);
      return FileManagerTabOpenOutcome.failed;
    }
  }

  Future<bool> _apply(
    Future<FileManagerSnapshot> Function(BigInt id) action,
  ) async {
    final id = _sessionId;
    if (id == null || _busy) return false;
    _cancelPendingSearch();
    final serial = ++_requestSerial;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await action(id);
      if (!mounted || serial != _requestSerial) return false;
      // ignore: invalid_use_of_protected_member
      setState(() {
        _acceptSnapshot(snapshot);
        _busy = false;
      });
      return true;
    } catch (error) {
      if (!mounted || serial != _requestSerial) return false;
      _showError(error);
      return false;
    }
  }

  void _acceptSnapshot(FileManagerSnapshot snapshot) {
    _snapshot = snapshot;
    _rememberOpenTabs(snapshot);
    // 列表换代了，选中态要跟着重读 —— 否则界面上会拿旧代的下标去标新代的行。
    if (_ops?.generation != snapshot.generation) _scheduleOpsRefresh();
    _syncSearchField(snapshot);
    final signature = _searchSignatureOf(snapshot);
    if (signature == _searchSignature) return;
    _searchSignature = signature;
    if (!_isRecursiveSearch(snapshot)) {
      // 条件已不成立：把还在跑的遍历也停下，否则它的结果会落在一屏无关的画面上。
      if (_searchRunning) {
        fileManagerCancelSearch(id: snapshot.sessionId);
      }
      return;
    }
    // 搜索条件的正本全在快照里，所以「变了就跑一次」覆盖到了查询、层数、类型
    // 筛选、排序、隐藏项与切页签，不需要在每个控件后面各挂一次。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _searchSignature != signature) return;
      _runSearch(snapshot);
    });
  }

  /// 把当前这批页签记下来，供下次启动恢复（开关见设置里的 restoreTabs）。
  ///
  /// 每一帧快照都会走这里，所以「要不要落盘」交给 [_tabMemory] 按签名判：
  /// 导航、排序、搜索这些不动页签的改动一次盘也不落。
  /// 开关的值**现读**而不是在 build 里订阅：恢复那一半要等新会话才生效，
  /// 记录这一半应该用户一关掉就立刻停手 —— 别把一个他不想要的名额留在盘上。
  void _rememberOpenTabs(FileManagerSnapshot snapshot) {
    final tabs = snapshot.tabs;
    _tabMemory.remember(
      enabled: _persistedRestoreTabs,
      paths: [for (final tab in tabs) tab.path],
      // 找不到当前页签 ⇒ -1，由 remember 夹成 0：快照里 `activeTabId` 与 `tabs`
      // 是同一次生成的，正常不会走到那条兜底。
      activeIndex: tabs.indexWhere((tab) => tab.id == snapshot.activeTabId),
    );
  }

  /// 输入框的文本以「谁最后改了查询」为准，而不是无条件跟随快照。
  ///
  /// 核心收到查询会 `trim`。边打边搜时若无条件回显，用户刚敲下的空格会被吃掉，
  /// 表现为「输入框拒绝空格」。所以只要框还拿着焦点、而核心给出的正是我们刚
  /// 提交的那一份（去掉首尾空白之后），就不动它。
  /// 反之 —— 核心自己改了查询（切页签与导航会清空搜索）—— 必须盖回输入框，
  /// 否则框里留着一个已经不再生效的词。
  void _syncSearchField(FileManagerSnapshot snapshot) {
    final server = snapshot.searchQuery;
    final asked = _pendingSearchQuery;
    if (_searchFocus.hasFocus && asked != null && server == asked.trim()) {
      return;
    }
    _pendingSearchQuery = null;
    if (_searchController.text == server) return;
    _searchController.value = TextEditingValue(
      text: server,
      selection: TextSelection.collapsed(offset: server.length),
    );
  }

  void _showError(Object error) {
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _busy = false;
      _error = error.toString();
    });
  }
}
