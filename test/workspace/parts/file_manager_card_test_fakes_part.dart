part of '../file_manager_card_test.dart';
// 测试替身：全局设置


/// 卡片现在要读写「文件管理器」全局设置（主页开关与路径）。
///
/// 真实的 [GlobalSettingCubit.updateState] 会落 ObjectBox，而本机的
/// `flutter test` 加载不了 `libobjectbox.dylib`（见 `test_helper.dart` 的说明）。
/// 所以这里只绕开**持久化**这一层：把写入直接 `emit` 到内存 state，
/// 于是「卡片确实把主页写进了全局设置」仍然可断言。
class _TestGlobalSettingCubit extends GlobalSettingCubit {
  _TestGlobalSettingCubit({FileManagerSettingState? fileManagerSetting})
    : super() {
    if (fileManagerSetting != null) {
      emit(state.copyWith(fileManagerSetting: fileManagerSetting));
    }
  }

  @override
  void updateFileManagerSetting(
    FileManagerSettingState Function(FileManagerSettingState current) updates,
  ) {
    emit(state.copyWith(fileManagerSetting: updates(state.fileManagerSetting)));
  }
}

class _FileManagerApi implements RustLibApi {
  FileManagerSnapshot snapshot = _snapshot();

  /// 文件操作那一份会话快照（选中集合 / 剪贴板 / 撤销栈，见 ADR-0017）。
  ///
  /// 它与 [snapshot] 是**两张不同的表**：管理器快照管列表与页签，这一份管
  /// 「选了谁、剪贴板里是什么、能不能撤销」。所以下面必须给 file_ops 那一族
  /// 桥函数单开分支 —— 它们落进 default 的话会拿一个 `FileManagerSnapshot`
  /// 去顶 `FileOpsSnapshot` / `FileOpsReport` / `bool`，炸出来的是一句
  /// 很难看懂的 `type 'Future<FileManagerSnapshot>' is not a subtype of ...`。
  FileOpsSnapshot ops = _opsSnapshot();

  /// 选中集合的替身真本（替核心记一份）。
  ///
  /// 三个「改选中」的桥调用必须**照提交的 path 改这份集合再回快照**，否则
  /// 「长按把选中态立起来 → 再点一行」这条链在测试里根本走不通：桩永远回同一份
  /// 空快照时，卡片第二下读到的仍然是「什么都没选」，也就进不到
  /// `resolveFileManagerEntryTapGesture` 里「多选模式」那一格。
  /// 卡片自己不留副本（正本在 Rust，见 ADR-0017），所以这一份只能记在桩这里。
  final selectedPaths = <String>[];

  FileOpsSnapshot _opsWithSelection() => _opsSnapshot(
    selectedCount: selectedPaths.length,
    selectedPaths: List.of(selectedPaths),
    // 这批里有没有目录，照当前列表现算 —— 它是核心的真实读数，写死成 false
    // 会让「粘贴到这一项」这类门控在测试里拿到假值。
    selectionHasDirectory: selectedPaths.any(
      (path) => snapshot.entries.any((entry) => entry.path == path && entry.isDir),
    ),
  );

  /// 文件树的投影。`hasPending` 固定为 false：真实的懒扫描靠 UI 隔一会儿再问一次，
  /// 测试里若让它一直「有待收」会让 `pumpAndSettle` 转不完。
  FileManagerTreeSnapshot tree = _treeSnapshot();
  final calls = <Invocation>[];
  Object? snapshotError;

  /// 搜索历史的替身。记一次就把那个词挪到最前 —— 与 SQLite 那侧「按最近使用」
  /// 的口径一致，这样卡片只负责显示，不必自己模拟去重。
  final List<String> history = [];

  /// 非空时，`setSearchQuery` 的回复挂在这个 Completer 上。用来造一个「请求还在
  /// 飞行中」的时刻 —— 增量搜索的关键判据（输入框不能因此禁打）只能在那一刻测。
  Completer<FileManagerSnapshot>? searchReply;

  /// 非空时，**递归那一次遍历**（`fileManagerSearch`）的回复挂在这个 Completer 上。
  ///
  /// 真机上遍历要几秒到几十秒，测试里要看的正是那一段：进度条亮不亮、已扫条数会不会涨。
  /// 不挂它时依旧立即回快照，老用例的时序一点不动。
  Completer<FileManagerSnapshot>? searchRunReply;

  /// `fileManagerSearchProgress` 的替身读数（下一次轮询读到的「已扫条数」）。
  int searchProgress = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    switch (invocation.memberName) {
      case #crateApiFontListSystemFontFamilies:
        return Future.value(const <String>[]);
      case #crateApiFileManagerBrowseFileManagerCreate:
        return Future.value(BigInt.one);
      case #crateApiFileManagerSearchFileManagerSetSearchQuery:
        final gate = searchReply;
        return gate == null ? Future.value(snapshot) : gate.future;
      case #crateApiFileManagerSearchFileManagerSearch:
        final gate = searchRunReply;
        return gate == null ? Future.value(snapshot) : gate.future;
      case #crateApiFileManagerSearchFileManagerSearchProgress:
        return Future.value(searchProgress);
      case #crateApiFileManagerSettingsFileManagerClose:
        return true;
      case #crateApiFileManagerTreeFileManagerTreeSnapshot:
      case #crateApiFileManagerTreeFileManagerTreeToggle:
        return Future.value(tree);
      case #crateApiFileManagerSearchFileManagerSearchHistory:
        return Future.value(List<String>.from(history));
      case #crateApiFileManagerSearchFileManagerRecordSearchHistory:
        final query = invocation.namedArguments[#query] as String;
        history.remove(query);
        history.insert(0, query);
        return Future.value(List<String>.from(history));
      case #crateApiFileManagerSearchFileManagerClearSearchHistory:
        history.clear();
        return Future.value(0);
      case #crateApiFileManagerEntryOpsFileManagerOpenEntry:
      case #crateApiFileManagerEntryOpsFileManagerOpenArchive:
        return Future.value(FileManagerActionResult(snapshot: snapshot));
      case #crateApiLocalThumbnailGetFileManagerEntryThumbnail:
        return Future.value(null);

      // ── 文件操作（ADR-0017）──────────────────────────────────────────────
      // 改选中集合的那三个，按提交的 path 真的改 [selectedPaths] 再回快照。
      case #crateApiFileOpsFileOpsSelectSingle:
        selectedPaths
          ..clear()
          ..add(invocation.namedArguments[#path] as String);
        return Future.value(_opsWithSelection());
      case #crateApiFileOpsFileOpsSelectToggle:
        final path = invocation.namedArguments[#path] as String;
        if (!selectedPaths.remove(path)) selectedPaths.add(path);
        return Future.value(_opsWithSelection());
      case #crateApiFileOpsFileOpsClearSelection:
        selectedPaths.clear();
        return Future.value(_opsWithSelection());
      // 其余只改选中集合 / 剪贴板的那几个，回的还是那份固定的 [ops]：
      // 「全选 / 反选 / Shift 连选」要的是核心的锚点与下标轨，桩里没有真本，
      // 所以它们的用例仍然自己 `api.ops = _opsSnapshot(...)` 摆好结果。
      case #crateApiFileOpsFileOpsSnapshot:
      case #crateApiFileOpsFileOpsSelectChain:
      case #crateApiFileOpsFileOpsSelectAll:
      case #crateApiFileOpsFileOpsInvertSelection:
      case #crateApiFileOpsFileOpsCopyToClipboard:
      case #crateApiFileOpsFileOpsClearClipboard:
        return Future.value(ops);
      // 真的落盘的那几个，回一份回执（回执里带着刷新后的快照）。
      case #crateApiFileOpsFileOpsPaste:
      case #crateApiFileOpsFileOpsTrashPaths:
      case #crateApiFileOpsFileOpsDeletePaths:
      case #crateApiFileOpsFileOpsRenameEntry:
      case #crateApiFileOpsFileOpsCreateDirectory:
      case #crateApiFileOpsFileOpsUndo:
        return Future.value(_opsReport(ops));
      // 返回 bool 的三个：回收站能不能撤销、打断当前批、以及关会话。
      case #crateApiFileOpsFileOpsTrashRestoreSupported:
        return Future.value(ops.trashRestoreSupported);
      case #crateApiFileOpsFileOpsCancel:
      case #crateApiFileOpsFileOpsClose:
        return Future.value(true);

      default:
        // 兜底：没列出来的 file_ops 桥调用直接炸在明处。
        //
        // 不这么做的话它会掉进下面那句 `Future.value(snapshot)`，变成一个
        // 「类型不符」的怪错误 —— 报错点指向、错的却是别的东西（`fileOpsClose`
        // 曾在 `dispose` 里报出 `Future<FileManagerSnapshot>` 不是 `Future<bool>`）。
        // 新增文件操作时想要的是「判据告诉我桩没跟上」，不是考古。
        final name = invocation.memberName.toString();
        if (name.contains('crateApiFileOps')) {
          throw UnimplementedError('测试桩还没有覆盖这个文件操作桥调用：$name');
        }
        return snapshotError == null
            ? Future.value(snapshot)
            : Future<FileManagerSnapshot>.error(snapshotError!);
    }
  }

  Iterable<Invocation> callsTo(Symbol name) =>
      calls.where((call) => call.memberName == name);
}
