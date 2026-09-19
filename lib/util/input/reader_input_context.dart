/// neoview 的输入上下文与优先级。
///
/// **词汇与数值照抄 neoview**：`READER_INPUT_CONTEXTS` 与
/// `READER_INPUT_CONTEXT_PRIORITY` / `READER_INPUT_GLOBAL_ISOLATION_CONTEXTS`
/// （`packages/nodes/neoview/src/domain/input/ReaderInputBindings.ts`）。
///
/// 为什么数值必须一致：绑定表与 context 是**要落进用户配置**的东西，schema 一旦有
/// 用户数据就难改（ADR-0009「schema 一次做全、运行时按子集实现」）。数值若与 neoview
/// 分叉，两边的绑定包将来就对不上。
///
/// 本文件只放**词汇表**，不放判定逻辑 —— 判定（优先级 + 隔离 + 冲突）将来由核心
/// 统一做（ADR-0015）。本轮 Dart 侧只当 adapter：把应用的真实状态翻译成
/// 「当前真实活跃的是哪几个 context」（见 `ReaderInputBridge`）。
enum ReaderInputContext {
  /// 全局：优先级最低，且在 `shell` / `editor` / `modal` 在场时**被隔离**（不生效）。
  global,
  reader,
  video,
  panel,
  shell,
  editor,
  modal,
}

extension ReaderInputContextSpec on ReaderInputContext {
  /// neoview `READER_INPUT_CONTEXT_PRIORITY` 的数值，逐条一致（越大越优先）。
  int get priority => switch (this) {
    ReaderInputContext.global => 0,
    ReaderInputContext.reader => 100,
    ReaderInputContext.video => 150,
    ReaderInputContext.panel => 200,
    ReaderInputContext.shell => 250,
    ReaderInputContext.editor => 300,
    ReaderInputContext.modal => 400,
  };

  /// neoview `READER_INPUT_GLOBAL_ISOLATION_CONTEXTS`：这些 context 在场时 `global` 不生效。
  bool get isolatesGlobal =>
      this == ReaderInputContext.shell ||
      this == ReaderInputContext.editor ||
      this == ReaderInputContext.modal;
}
