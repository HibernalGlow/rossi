# tool/ast_split — 大文件拆分的 AST 工具

把超过 1000 行的源文件按职责拆成多个文件，并且**证明搬家没有改变任何代码内容**。
本工具是独立 Dart 包，不属于应用代码，不参与 Flutter / Cargo 构建。

## 依赖

已用 `dart pub get --offline` 装好（`analyzer: ^10.2.0`）。若需重装：

```bash
cd tool/ast_split && dart pub get --offline
```

## 子命令

```bash
cd tool/ast_split
D='dart bin/ast_split.dart'

# 1) 看结构：顶层声明 + 最大的成员
$D inspect --file ../../lib/xxx/foo.dart
$D inspect --file ../../lib/xxx/foo.dart --class FooState   # 逐成员列出 kind 与风险标记

# 2) 搬家前打快照
$D snapshot --file ../../lib/xxx/foo.dart --out /tmp/foo.json

# 3) 审计：证明「只搬家、没改内容」
$D audit --snapshot /tmp/foo.json --file ../../lib/xxx/foo.dart
```

### 三种搬运动作

| 命令 | 目标形态 | 适用 |
|------|----------|------|
| `extract --file F --to P --decls a,b --note 说明` | P 为 `part of F`，私有符号无需改名 | 同库内按职责分文件（**首选**） |
| `extract-library --file F --to N --decls a,b` | N 为独立库，F 里插入 `export N` | 搬出的符号是**公开**的，希望成为真正的独立模块 |
| `extract-members --file F --class C --to P --extension _CxPart --members m1,m2` | P 里生成 `extension _CxPart on C { ... }` | 拆一个巨大的 State/Controller 类 |

`extract-members` 会在下列情况下**拒绝执行**（不是 bug，是护栏）：成员是字段 / 构造函数 / operator、带 `@override`、函数体里出现 `super`、或成员名与基类成员同名（`build`/`dispose`/`setState`/…）。加 `--force` 只能绕过基类名这一项，其余一律不可绕过。

## audit 的三条不变量

1. **逐键原文哈希**：每个声明/成员的 AST 节点区间原文，搬家后要么完全一致，要么「只少了几整块」（剩余行必须是原行的有序子序列）。
2. **按文件有序子序列**：老文件剩下的行必须保持原有相对顺序（改写或重排会 FAIL）；新文件的每一行必须能按原序追溯到原库。
3. **全局行多重集合守恒**：搬走的每一行都必须整体出现在新文件里，一行都不能蒸发。

自检结论（已在真实文件上验证）：干净搬家 `AUDIT PASS`；把搬走的一行改个数 → `LOST` + `FAIL`；把类里两个方法交换位置 → `ORDER/BODY 破坏` + `FAIL`。

## 语言无关的文本审计（Rust / C++ / JS 用这个）

这些语言没有接进 AST，但同样的「只搬家」判据仍然成立：

```bash
dart bin/ast_split.dart text-snapshot --files rust/local_core/src/foo.rs --out /tmp/foo.json
# ……手动把整块行搬到 foo/ 下的新文件，并在原文件加 mod/使用 语句……
dart bin/ast_split.dart text-audit --snapshot /tmp/foo.json     # 必须 TEXT AUDIT PASS
```

它比较「有意义行」（剔掉空行、纯注释行与 `use/mod/import/#include/part` 等指令行）：
老文件的剩余行必须是原文件的有序子序列；新文件的每一行必须按原序取自原文；全局行多重集合守恒，一行都不许蒸发。

**注意**：`text-audit` 会把被审计文件所在目录下**所有新增的同语言文件**纳入统计，所以快照目录里不要留无关副本（例如备份的 `orig.rs`），否则会虚增行数。

## 与 audit 配套的其它门禁

审计只证明「内容未被改写」，不证明「拆完之后仍然编译」。每个文件还要跑：

```bash
cd /Users/glow/Projects/rossi && flutter analyze      # lib/ 下必须 0 error
cd /Users/glow/Projects/rossi/rust && cargo check -p <crate>
```

`poc/` 子包有 231 个既有 error（依赖未解析），`test/reader/page_split_test.dart` 有 6 个既有 error，属基线噪音；`lib/` 应为 0。

## 硬性约束

- **不要**跑 `build_runner` / `flutter pub run build_runner` / `slang`。代码生成由主线统一串行执行，避免互删生成物。
- 含 `@freezed` / `json_serializable` 的文件（如 `lib/config/global/global_setting.dart`）由主线处理，agent 不要碰。
- `git status` 里已 modified 的文件属并发工作区，不要碰。
- 不要执行任何 `git add` / `commit` / `checkout` / `stash` / `reset`。

## 这套判据本身可信吗

两道独立的证据，都在仓库里、可重跑：

### 1) 自测：证明审计不是橡皮图章

```bash
bash tool/ast_split/selftest.sh
```

5 组用例：顶层声明→part、part 里再拆 part、类成员→extension、`extract-members` 的五类护栏、
以及**反向用例**——把搬走的一行改个数、把类里两个方法交换位置，都必须被审计判负。
另有 Rust 形态的 `text-snapshot/text-audit` 正反向各一条。

### 2) 独立验收：绕开 agent 自报的审计，直接对线开工时的提交

```bash
VERIFY_REF=<开工时的 commit> python3 tool/ast_split/verify_moves.py <路径...>
```

不带参数时自动扫描工作区里所有「HEAD 时有 400+ 有意义行、现在被改过」的源文件。
它从 git 取原文，与工作区里该文件本身 + 本次新增的兄弟文件比对，要求：

- **顺序守恒**：现存文件的每一行按原有相对顺序出现（只允许删行 = 被搬走）。
- **内容守恒**：原文的每个有意义行都还在（多重集合意义下），丢失数必须为 0。
- **无凭空行**：现存文件里出现原文没有的行，数必须为 0（`// ignore:` 之类注释不计入）。
- 只有「行确实取自本文件原文」的新文件才算承接方 —— 否则同目录里别人新建的文件会让
  多重集合虚胖、把丢失行掩盖掉。

⚠️ **并发提交会动摇基线**：用户可能在我们干活时继续往 main 上提交，`HEAD` 不再是拆分前的状态。
所以要显式 `VERIFY_REF=` 钉住开工时那个 commit。
改动留在工作区交给用户。
