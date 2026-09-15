import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/src/rust/api/local.dart';

/// 本地来源（判据 A）的调试页：把 `rossi_local_core` 的读取路径真正跑起来。
///
/// 三条边界，写在这里免得以后误读：
///
/// 1. **这里走的是 Dart 兜底显示路径。** 用 `Image.memory` 让 Flutter 解码，
///    即「编码字节过桥」——`docs/v0.1-local-core.md` §9 明确允许，用于兜底与
///    尺寸探测。**目标形态是 Rust 侧解码后直接进 GPU texture**（Phase 1 的
///    `texture-bridge`），本页不代表最终上屏路径，不要拿它的帧率当判据 B/C。
/// 2. **不做页面缓存。** 每次翻页都重新 `localPageBytes`，顺便让「不常驻句柄」
///    这条性质在 UI 上可见（判据 D 的结构性依据）。仅保留当前页，避免调试页
///    自己把内存撑起来掩盖问题。
/// 3. **本页不新增 i18n 键、不注册 auto_route**：调试页属于内部工具，走
///    `MaterialPageRoute` 直连，避免为一个诊断页触发全量 codegen。
///    若将来要转正，再补 `@RoutePage()` 与 `slang` 词条。
class LocalSourceDebugPage extends StatefulWidget {
  const LocalSourceDebugPage({super.key});

  @override
  State<LocalSourceDebugPage> createState() => _LocalSourceDebugPageState();
}

class _LocalSourceDebugPageState extends State<LocalSourceDebugPage> {
  BigInt? _sessionId;
  LocalSourceInfo? _info;
  LocalRejection? _rejection;
  List<LocalPageInfo> _pages = const [];

  String? _error;
  bool _busy = false;

  /// 当前展示的页（-1 表示没有）。
  int _current = 0;
  Uint8List? _currentBytes;
  int? _currentBytesIndex;
  Duration? _lastReadCost;

  /// 「逐页计时」的结果：每页耗时（毫秒）。
  List<double>? _sweepMs;
  double? _sweepTotalMs;

  int _probeCount = 0;

  @override
  void dispose() {
    // 页面销毁时把会话还回去，否则反复进出会看到探针单调上升。
    final id = _sessionId;
    if (id != null) {
      localClose(id: id);
    }
    super.dispose();
  }

  Future<void> _refreshProbe() async {
    final n = localOpenSessionCount();
    if (mounted) setState(() => _probeCount = n);
  }

  Future<void> _closeCurrent({bool silent = false}) async {
    final id = _sessionId;
    if (id == null) return;
    localClose(id: id);
    if (!mounted) return;
    setState(() {
      _sessionId = null;
      _info = null;
      _pages = const [];
      _currentBytes = null;
      _currentBytesIndex = null;
      _lastReadCost = null;
      _sweepMs = null;
      _sweepTotalMs = null;
      if (!silent) _rejection = null;
    });
    await _refreshProbe();
  }

  Future<void> _openPath(String path) async {
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
        if (!mounted) return;
        setState(() {
          _rejection = rejection;
          _info = null;
          _pages = const [];
        });
        return;
      }

      final info = result.source!;
      final pages = await localSourcePages(id: info.id);

      if (!mounted) return;
      setState(() {
        _sessionId = info.id;
        _info = info;
        _pages = pages;
        _current = 0;
        _currentBytes = null;
        _currentBytesIndex = null;
        _sweepMs = null;
        _sweepTotalMs = null;
      });
      await _refreshProbe();
      if (pages.isNotEmpty) {
        await _loadPage(0);
      }
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

  Future<void> _loadPage(int index) async {
    final id = _sessionId;
    if (id == null || index < 0 || index >= _pages.length) return;
    if (_currentBytesIndex == index && _currentBytes != null) {
      setState(() => _current = index);
      return;
    }

    final sw = Stopwatch()..start();
    try {
      final bytes = await localPageBytes(id: id, index: index);
      sw.stop();
      if (!mounted) return;
      setState(() {
        _current = index;
        _currentBytes = bytes;
        _currentBytesIndex = index;
        _lastReadCost = sw.elapsed;
      });
    } catch (e) {
      sw.stop();
      if (!mounted) return;
      setState(() => _error = '读第 $index 页失败：$e');
    }
  }

  /// 逐页读一遍并计时。这条曲线是 `docs/v0.1-local-core.md` §7 那把尺子：
  /// 近似常量 ⇒ 归档支持按需 seek；随 N 线性增长 ⇒ 实际在解压整段。
  ///
  /// 注意：这里量的是**过桥 + 编码字节**的耗时，不含解码与上屏；
  /// 绝对值比 Rust 侧探针高，但**增长形态**仍然说明问题。
  Future<void> _sweep() async {
    final id = _sessionId;
    if (id == null || _pages.isEmpty) return;

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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地来源调试（判据 A）'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '会话数 $_probeCount',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _toolbar(),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

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
          OutlinedButton.icon(
            onPressed: _sessionId == null ? null : () => _closeCurrent(),
            icon: const Icon(Icons.close, size: 18),
            label: const Text('关闭会话'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final n = localCloseAll();
              if (!mounted) return;
              setState(() {
                _sessionId = null;
                _info = null;
                _pages = const [];
                _currentBytes = null;
                _currentBytesIndex = null;
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
            '读取路径：Dart → FRB → rossi_local_core → 归档，每页都重开归档（不常驻句柄）。',
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
          Text('来源：${_kindLabel(info.kind)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('会话 id：${info.id}'),
          Text('页数：${info.pageCount}'),
          Text('总字节：${info.totalBytes}'),
          if (_lastReadCost != null)
            Text('上次读页：${_lastReadCost!.inMicroseconds / 1000.0} ms'),
          Text(
            info.path,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
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
    final bytes = _currentBytes;
    if (bytes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: InteractiveViewer(
            maxScale: 8,
            child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
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

    final first5 = ms.take(5).fold<double>(0, (a, b) => a + b) / ms.take(5).length;
    final last5 =
        ms.reversed.take(5).fold<double>(0, (a, b) => a + b) / ms.reversed.take(5).length;
    final ratio = first5 == 0 ? double.infinity : last5 / first5;

    final verdict = ratio < 2.0
        ? '近似常量 → 按需 seek，未整段解压'
        : '随页序增长 → 疑似整段解压';

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
          'v0.1 只认散图文件夹 / CBZ / CBR。7z、PDF、视频都在这条线之外。',
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
      LocalRejectionKind.notFound => (
          Icons.link_off,
          '路径不存在或不可读。',
        ),
      LocalRejectionKind.io => (
          Icons.error_outline,
          'IO 或解析失败（含归档损坏）。',
        ),
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
      };
}
