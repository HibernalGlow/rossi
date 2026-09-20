import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/model/workspace_interaction_settings.dart';
import 'package:zephyr/workspace/model/workspace_layout_snapshot.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';
import 'package:zephyr/workspace/service/workspace_layout_store.dart';

/// 「设置 → 布局」与**工作台布局**之间的窄接口。
///
/// # 为什么需要这一层
///
/// 布局的**唯一真相**是磁盘上那份 `workspace_layout.json`（`WorkspaceLayoutSnapshot`），
/// 而它平时住在挂载中的 [WorkspaceCubit] 内存里、由去抖器负责落盘。
/// 于是设置页面对象有两条完全不同的路：
///
/// - 工作台**在场**（从工作台里打开设置，或被某条泳道的面板装着）：
///   必须改**活的** cubit —— 直接写文件会被 cubit 下一次去抖落盘**覆盖回去**，
///   现象是「设置里改了、松手就弹回」；
/// - 工作台**不在场**（从导航栏打开设置）：没有 cubit 可改，只能读盘、改那几项、
///   立刻写回去，等下次工作台启动时读到。
///
/// 两条路都收在 [write] 里，调用方不必知道工作台在不在场。
/// 登记方式与 `WorkspaceNavigationBridge` 同构：工作台挂载时登记自己，
/// 卸载时**只注销自己登记的那个**（避免把后来者的引用抹掉）。
class WorkspaceLayoutBridge {
  WorkspaceLayoutBridge._();

  static final WorkspaceLayoutBridge instance = WorkspaceLayoutBridge._();

  WorkspaceCubit? _cubit;

  /// 当前有没有活的工作台（判据 / 设置页据此说明「改完立刻生效」还是「下次启动生效」）。
  bool get isAttached => _cubit != null;

  void attach(WorkspaceCubit cubit) => _cubit = cubit;

  void detach(WorkspaceCubit cubit) {
    if (identical(_cubit, cubit)) _cubit = null;
  }

  /// 当前布局：活的 cubit 优先，其次磁盘，都没有则出厂值。
  ///
  /// 给**要拿一份值来渲染 / 改**的调用方（设置页）。它与 [readIfAvailable] 的关系是
  /// `read() == readIfAvailable() ?? 出厂值` —— 「怎么读」只有 [readIfAvailable] 一份。
  ///
  /// 「都没有则出厂值」这个兜底**不能**给同步用：那边必须区分「用户的布局就是
  /// 出厂值」与「这次没读到」（见 [readIfAvailable]）。
  Future<WorkspaceLayoutSnapshot> read() async =>
      await readIfAvailable() ?? WorkspaceLayoutSnapshot.defaults();

  /// 与 [read] 相同，但**读不到就返回 `null`**（不兜出厂值）。
  ///
  /// 存在的理由是同步：云同步必须分清两件事 ——
  ///
  /// - 「用户的布局**就是**出厂值」（真的没改过）⇒ 让云端说了算；
  /// - 「这次**没读到**」（本机还没存过布局，或拿不到数据目录 / 读盘失败）
  ///   ⇒ **整块不带**。把出厂值当成「本机布局」传上去，会把另一台设备上真正
  ///   那套精心摆好的布局冲掉，而原因只是一次读盘失败 —— 用户看不到任何提示。
  ///
  /// 顺带一个小好处：新装设备（本机还没有布局文件）第一次同步就直接采纳云端
  /// 那套布局，而不是先上传一份出厂值。
  Future<WorkspaceLayoutSnapshot?> readIfAvailable() async {
    final live = _cubit;
    if (live != null) return live.snapshot;
    try {
      final store = WorkspaceLayoutFileStore(await workspaceLayoutDirectory());
      return await store.load();
    } on Object {
      // 拿不到数据目录（或读盘失败）：见上。设置页那条路会退到出厂值 ——
      // 它要能打开、要能改，只是这次改完存不下去，与工作台「布局是可重建的
      // 东西，为它挡住启动不值得」的口径一致。
      return null;
    }
  }

  /// 改布局的**呈现与交互**那两块（默认启动视图 / 焦点独占 / 唤出区）。
  ///
  /// 只碰这两块，其余（泳道宽度、面板与卡片记账、激活泳道）原样保留 ——
  /// 设置页不该有一次「顺手保存」就把用户摆好的泳道宽度抹平。
  ///
  /// 走 [write] 的落盘路径与工作台**自己**改时不同：这里是**立刻写**，
  /// 因为设置页没有去抖器，而「改完就切后台」正好落在去抖窗口里。
  Future<void> write({
    WorkspaceMode? mode,
    WorkspaceInteractionSettings? interaction,
  }) async {
    final live = _cubit;
    if (live != null) {
      if (mode != null) live.setMode(mode);
      if (interaction != null) live.setInteraction(interaction);
      return;
    }

    try {
      final store = WorkspaceLayoutFileStore(await workspaceLayoutDirectory());
      final current = await store.load() ?? WorkspaceLayoutSnapshot.defaults();
      var next = current;
      if (mode != null) next = next.copyWithMode(mode);
      if (interaction != null) next = next.copyWithInteraction(interaction);
      await store.save(next);
    } on Object {
      // 存不下去不炸设置页：见 [read] 里同一条理由。
    }
  }

  /// 用一份**整份**快照替换布局（云同步下载用）。
  ///
  /// 与 [write] 的区别不是「改几项」而是「谁说了算」：[write] 是设置页在改，
  /// 用户要的是「就改这一项、别的别动」；这里是云端那份赢了，语义是
  /// **整份采纳**（调用方已经把「本机独有的字段」按本位保留好了 ——
  /// 见 `WorkspaceSyncCodec.decode`，它接一份本机基线再覆盖）。
  ///
  /// 工作台在场时走活的 cubit：绝不能直接写盘 —— cubit 下一次去抖落盘会把
  /// 它覆盖回去，现象是「同步下载说成功了，界面纹丝不动、一秒后连文件也回去了」。
  /// 而且这次 `restore` 会经工作台自己的持久化监听落盘，不需要这里再写一次。
  Future<void> apply(WorkspaceLayoutSnapshot snapshot) async {
    final live = _cubit;
    if (live != null) {
      live.restore(snapshot);
      return;
    }

    try {
      final store = WorkspaceLayoutFileStore(await workspaceLayoutDirectory());
      await store.save(snapshot);
    } on Object {
      // 存不下去不炸同步流程：见 [read] 里同一条理由。注意这里**吞掉的**是
      // 「拿不到数据目录」这类环境问题 —— 本次同步的其余部分（设置、插件）
      // 已经落地，不该因为布局写不进去而让整轮同步报错。
    }
  }
}
