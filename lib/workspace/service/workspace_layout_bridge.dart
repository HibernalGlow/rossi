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
  Future<WorkspaceLayoutSnapshot> read() async {
    final live = _cubit;
    if (live != null) return live.snapshot;
    try {
      final store = WorkspaceLayoutFileStore(await workspaceLayoutDirectory());
      return await store.load() ?? WorkspaceLayoutSnapshot.defaults();
    } on Object {
      // 拿不到数据目录（或读盘失败）时仍然给得出出厂值：设置页要能打开、
      // 要能改，只是这次改完存不下去 —— 与工作台「布局是可重建的东西，
      // 为它挡住启动不值得」的口径一致。
      return WorkspaceLayoutSnapshot.defaults();
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
}
