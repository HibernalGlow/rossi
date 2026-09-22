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

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    switch (invocation.memberName) {
      case #crateApiFileManagerFileManagerCreate:
        return Future.value(BigInt.one);
      case #crateApiFileManagerFileManagerSetSearchQuery:
        final gate = searchReply;
        return gate == null ? Future.value(snapshot) : gate.future;
      case #crateApiFileManagerFileManagerClose:
        return true;
      case #crateApiFileManagerFileManagerTreeSnapshot:
      case #crateApiFileManagerFileManagerTreeToggle:
        return Future.value(tree);
      case #crateApiFileManagerFileManagerSearchHistory:
        return Future.value(List<String>.from(history));
      case #crateApiFileManagerFileManagerRecordSearchHistory:
        final query = invocation.namedArguments[#query] as String;
        history.remove(query);
        history.insert(0, query);
        return Future.value(List<String>.from(history));
      case #crateApiFileManagerFileManagerClearSearchHistory:
        history.clear();
        return Future.value(0);
      case #crateApiFileManagerFileManagerOpenEntry:
      case #crateApiFileManagerFileManagerOpenArchive:
        return Future.value(FileManagerActionResult(snapshot: snapshot));
      case #crateApiLocalThumbnailGetFileManagerEntryThumbnail:
        return Future.value(null);

      // ── 文件操作（ADR-0017）──────────────────────────────────────────────
      // 只改选中集合 / 剪贴板的那几个，回的都是同一份 `ops`。
      case #crateApiFileOpsFileOpsSnapshot:
      case #crateApiFileOpsFileOpsSelectSingle:
      case #crateApiFileOpsFileOpsSelectToggle:
      case #crateApiFileOpsFileOpsSelectChain:
      case #crateApiFileOpsFileOpsSelectAll:
      case #crateApiFileOpsFileOpsInvertSelection:
      case #crateApiFileOpsFileOpsClearSelection:
      case #crateApiFileOpsFileOpsCopyToClipboard:
      case #crateApiFileOpsFileOpsClearClipboard:
        return Future.value(ops);
      // 真的落盘的那几个，回一份回执（回执里带着刷新后的快照）。
      case #crateApiFileOpsFileOpsPaste:
      case #crateApiFileOpsFileOpsTrashSelection:
      case #crateApiFileOpsFileOpsDeleteSelection:
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
