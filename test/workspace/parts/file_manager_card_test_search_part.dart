part of '../file_manager_card_test.dart';

void _searchTests(_FileManagerApi Function() getApi) {
  testWidgets('输入先建搜索页签，继续改词和回车复用该页签', (tester) async {
    final api = getApi();
    final source = api.snapshot;
    await _pumpCard(tester);
    await tester.tap(find.byTooltip('搜索（空格分词，-排除）'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'book');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerSetSearchQuery),
      isEmpty,
    );
    expect(source.searchQuery, isEmpty);
    expect(api.snapshot.activeTabId, isNot(source.activeTabId));
    await tester.enterText(find.byType(TextField), 'book newer');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerSearchInNewTab),
      hasLength(1),
    );
    expect(api.snapshot.searchQuery, 'book newer');
    expect(api.history, ['book newer']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('从保存的搜索再输入会创建另一页签', (tester) async {
    final api = getApi();
    api.snapshot = _snapshot(query: 'old', searchActive: true);
    final source = api.snapshot;
    await _pumpCard(tester);
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerSetSearchQuery),
      isEmpty,
    );
    expect(source.searchQuery, 'old');
    expect(api.snapshot.activeTabId, isNot(source.activeTabId));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('页签达到上限时搜索不修改源目录，也不写历史', (tester) async {
    final api = getApi();
    await _pumpCard(tester);
    await tester.tap(find.byTooltip('搜索（空格分词，-排除）'));
    await tester.pumpAndSettle();
    api.snapshotError = StateError('页签数量已达到上限');
    await tester.enterText(find.byType(TextField), 'new');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerSetSearchQuery),
      isEmpty,
    );
    expect(api.snapshot.searchQuery, isEmpty);
    expect(api.history, isEmpty);
    expect(find.textContaining('页签数量已达到上限'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('搜索框默认折叠，展开后提交到 Rust，切换页签后输入框采用 Rust 快照', (tester) async {
    final api = getApi();
    await _pumpCard(tester);
    // 默认折叠：没有搜索输入框。
    expect(find.byType(TextField), findsNothing);

    final searchToggle = find.byTooltip('搜索（空格分词，-排除）');
    await tester.ensureVisible(searchToggle);
    await tester.tap(searchToggle);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'book');
    api.snapshot = _snapshot(query: 'book');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerSearchFileManagerSearchInNewTab)
          .single
          .namedArguments[#query],
      'book',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'book',
    );
    api.snapshot = _snapshot(query: 'from other tab');
    await tester.tap(find.byTooltip('新建页签'));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerBrowseFileManagerNewTab),
      hasLength(1),
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'from other tab',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('输入即搜：不等回车，跨过防抖窗口就提交，提交期间输入框仍可打字', (tester) async {
    final api = getApi();
    await _pumpCard(tester);
    await tester.tap(find.byTooltip('搜索（空格分词，-排除）'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '春 日 -草稿');
    // 防抖窗口内还没发出去 —— 连续敲字不会每个字符打一次桥。
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerSetSearchQuery),
      isEmpty,
    );

    // 让这一次提交挂在飞行中，才测得到「请求期间输入框不能失效」。
    final gate = Completer<FileManagerSnapshot>();
    api.searchTabReply = gate;
    await tester.pump(const Duration(milliseconds: 200));
    final calls = api.callsTo(
      #crateApiFileManagerSearchFileManagerSearchInNewTab,
    );
    expect(calls, hasLength(1));
    expect(calls.single.namedArguments[#query], '春 日 -草稿');
    expect(
      tester.widget<TextField>(find.byType(TextField)).enabled,
      isNot(isFalse),
    );

    // 创建期间继续改词：源目录不能先收到查询，也不能再开第二个页签。
    await tester.enterText(find.byType(TextField), '春 日 -草稿 修');
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerSetSearchQuery),
      isEmpty,
    );
    gate.complete(
      _snapshot(query: '春 日 -草稿', searchActive: true, activeTabId: 3),
    );
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerSearchInNewTab),
      hasLength(1),
    );
    expect(
      api
          .callsTo(#crateApiFileManagerSearchFileManagerSetSearchQuery)
          .single
          .namedArguments[#query],
      '春 日 -草稿 修',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '春 日 -草稿 修',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('搜索时敲进去的空格不会被核心回显吃掉', (tester) async {
    final api = getApi();
    await _pumpCard(tester);
    await tester.tap(find.byTooltip('搜索（空格分词，-排除）'));
    await tester.pumpAndSettle();

    // 核心会把查询 trim 掉，快照里回来的是「春日」；框里必须还是用户打的那一份。
    api.snapshot = _snapshot(query: '春日');
    await tester.enterText(find.byType(TextField), '春日 ');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '春日 ',
    );

    // 但核心自己改了查询（切页签、导航会清空）时必须盖回来，
    // 否则框里留着一个已经不再生效的词。
    api.snapshot = _snapshot();
    await tester.tap(find.byTooltip('新建页签'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('含子目录开关提交条件并触发一次递归搜索', (tester) async {
    final api = getApi();
    await _pumpCard(tester);
    await tester.tap(find.byTooltip('搜索（空格分词，-排除）'));
    await tester.pumpAndSettle();

    api.snapshot = _snapshot(query: '春', subfolders: true);
    await tester.tap(find.text('含子目录'));
    await tester.pumpAndSettle();

    expect(
      api
          .callsTo(
            #crateApiFileManagerSearchFileManagerSetSearchIncludeSubfolders,
          )
          .single
          .namedArguments[#enabled],
      isTrue,
    );
    // 条件一变就跑一次遍历；结果由 Rust 写进页签，卡片不再有第二份列表。
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerSearch),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('递归搜索露出层数档位，并如实说明「更深的没搜」', (tester) async {
    final api = getApi();
    api.snapshot = _snapshot(
      query: '春',
      subfolders: true,
      searchActive: true,
      depthLimited: true,
    );
    await _pumpCard(tester, width: 700);
    await tester.pumpAndSettle();

    // 「没搜到」不等于「没有」：状态行要说清遍历停在哪一层。
    expect(find.textContaining('第 6 层以下未搜'), findsOneWidget);

    final chip = find.text('层数 ≤6');
    expect(chip, findsOneWidget);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerSearchFileManagerSetSearchMaxDepth)
          .single
          .namedArguments[#depth],
      12,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('只搜当前一层且零命中时，给出「在子目录里搜」的出口', (tester) async {
    final api = getApi();
    api.snapshot = _snapshot(query: '春', noEntries: true);
    await _pumpCard(tester, width: 700);
    await tester.pumpAndSettle();

    expect(find.textContaining('当前这一层没有匹配「春」的条目'), findsOneWidget);
    final chip = find.text('在子目录里搜');
    expect(chip, findsOneWidget);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(
            #crateApiFileManagerSearchFileManagerSetSearchIncludeSubfolders,
          )
          .single
          .namedArguments[#enabled],
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('「默认连子目录一起搜」在建会话时交给核心一次', (tester) async {
    final api = getApi();
    await _pumpCard(
      tester,
      settings: _TestGlobalSettingCubit(
        fileManagerSetting: const FileManagerSettingState(
          searchSubfoldersDefault: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 只在建会话时交一次：卡片不该每来一份快照就把用户手动关掉的开关翻回来。
    expect(
      api
          .callsTo(#crateApiFileManagerBrowseFileManagerCreate)
          .single
          .namedArguments[#searchSubfoldersDefault],
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('递归遍历进行中：输入框下有进度条与实时已扫条数', (tester) async {
    final api = getApi();
    api.searchRunReply = Completer<FileManagerSnapshot>();
    api.snapshot = _snapshot(query: '春', subfolders: true, searchActive: true);
    await _pumpCard(tester, width: 700, settle: false);

    // 进度条一直在动，这一条只能自己推帧（`pumpAndSettle` 永远落不了地）。
    Future<void> pumpUntil(bool Function() done, {int maxPumps = 25}) async {
      for (var i = 0; i < maxPumps; i++) {
        if (done()) return;
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    await pumpUntil(
      () => api.callsTo(#crateApiFileManagerSearchFileManagerSearch).isNotEmpty,
    );
    // 遍历刚发出去的这一刻不该亮条：几十毫秒就回来的收窄若闪一下，反而像卡了。
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // 慢遍历：250ms 之后亮出引导条。
    await pumpUntil(
      () => find.byType(LinearProgressIndicator).evaluate().isNotEmpty,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('正在递归搜索'), findsWidgets);

    // 已扫条数是核心的真实读数，跟着轮询往上走 —— 这是「它在干活」的那份证据。
    api.searchProgress = 12345;
    await pumpUntil(
      () => find.textContaining('已扫 1.2 万条').evaluate().isNotEmpty,
    );
    expect(find.textContaining('已扫 1.2 万条'), findsOneWidget);

    // 遍历回来：引导条让位给真实统计。
    api.searchRunReply!.complete(
      _snapshot(query: '春', subfolders: true, searchActive: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('搜索结果页签：命中带相对目录，提供回到目录与存为页签', (tester) async {
    final api = getApi();
    // 查询非空时搜索行本来就在（不必先展开），这一条测的是结果态的画法和出口。
    // 选项行是横向滚动的，宽一点才不用为每个芯片单独滚动。
    api.snapshot = _snapshot(query: '春', subfolders: true, searchActive: true);
    await _pumpCard(tester, width: 700);
    await tester.pumpAndSettle();

    // 副标题最前面带上「哪本子目录」，同名条目才分得开。
    expect(find.textContaining('春组/本子'), findsOneWidget);
    expect(find.text('命中 2 · 已看 120'), findsOneWidget);

    for (final label in ['存为页签', '回到目录']) {
      final chip = find.text(label);
      expect(chip, findsOneWidget);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerSaveSearchAsTab),
      hasLength(1),
    );
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerClearSearch),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('还没下查询时搜索行显示历史，点一下就再搜一次', (tester) async {
    final api = getApi();
    api.history.addAll(['旧词', '更旧的词']);
    await _pumpCard(tester);
    await tester.tap(find.byTooltip('搜索（空格分词，-排除）'));
    await tester.pumpAndSettle();
    expect(find.text('旧词'), findsOneWidget);
    expect(find.text('更旧的词'), findsOneWidget);

    await tester.tap(find.text('旧词'));
    await tester.pumpAndSettle();
    expect(
      api
          .callsTo(#crateApiFileManagerSearchFileManagerSearchInNewTab)
          .single
          .namedArguments[#query],
      '旧词',
    );
    // 点历史词是「主动定下的搜索」，所以要进历史；防抖那一路不进。
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerRecordSearchHistory),
      hasLength(1),
    );

    await tester.tap(find.byTooltip(t.search.history));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.search.clearHistory));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerClearSearchHistory),
      hasLength(1),
    );
    await tester.pumpAndSettle();
    expect(api.history, isEmpty);
    await tester.tap(find.byTooltip(t.search.history));
    await tester.pumpAndSettle();
    expect(find.text(t.search.noHistory), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('防抖那一路不写搜索历史', (tester) async {
    final api = getApi();
    await _pumpCard(tester);
    await tester.tap(find.byTooltip('搜索（空格分词，-排除）'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '随手打词');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerSearchInNewTab),
      hasLength(1),
    );
    expect(
      api.callsTo(#crateApiFileManagerSearchFileManagerRecordSearchHistory),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
