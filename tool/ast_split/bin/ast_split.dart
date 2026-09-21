// AST 驱动的大文件拆分与等价性审计工具。
//
// 子命令：
//   inspect           列出库（父文件 + 手写 part）的顶层声明与指定类的成员
//   list              只输出声明名，供脚本比对归属
//   snapshot          记录库的有序行序列与每个声明/成员的原文
//   audit             与快照比对，证明「只整块搬家、没改写内容」
//   extract           把若干顶层声明原文搬到新的 part 文件
//   extract-library   把若干顶层声明搬到新的独立库，并在父文件加 export
//   extract-members   把某个类的成员原文搬进 part 文件里的 extension
//
// 搬运一律按 AST 给出的 offset 区间逐字节切片：不重排、不改写函数体。

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

const generatedSuffixes = ['.freezed.dart', '.g.dart', '.mocks.dart'];

/// 基类成员名：搬进 extension 会破坏虚派发，默认拒绝。
const baseMemberDenylist = {
  'build',
  'dispose',
  'initState',
  'setState',
  'didUpdateWidget',
  'deactivate',
  'activate',
  'reassemble',
  'didChangeDependencies',
  'noSuchMethod',
  'toString',
  'hashCode',
  'runtimeType',
  'element',
  'mounted',
  'context',
  'createState',
};

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart bin/ast_split.dart '
      '<inspect|list|snapshot|audit|extract|extract-library|extract-members>'
      ' --file <path> [...]',
    );
    exit(64);
  }
  final opt = parseOptions(args.skip(1).toList());
  switch (args.first) {
    case 'inspect':
      cmdInspect(opt);
    case 'list':
      cmdList(opt);
    case 'snapshot':
      cmdSnapshot(opt);
    case 'audit':
      exit(cmdAudit(opt) ? 0 : 1);
    case 'extract':
      cmdExtract(opt, asPart: true);
    case 'extract-library':
      cmdExtract(opt, asPart: false);
    case 'extract-members':
      cmdExtractMembers(opt);
    case 'text-snapshot':
      cmdTextSnapshot(opt);
    case 'text-audit':
      exit(cmdTextAudit(opt) ? 0 : 1);
    default:
      stderr.writeln('unknown command: ${args.first}');
      exit(64);
  }
}

Map<String, String> parseOptions(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) continue;
    final eq = a.indexOf('=');
    if (eq >= 0) {
      out[a.substring(2, eq)] = a.substring(eq + 1);
    } else {
      final key = a.substring(2);
      if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
        out[key] = args[++i];
      } else {
        out[key] = 'true';
      }
    }
  }
  return out;
}

List<String> nameList(Map<String, String> opt, String key) {
  final raw = opt[key];
  if (raw == null || raw.isEmpty) return const [];
  return raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

// ---------------------------------------------------------------- library view

class Unit {
  Unit(this.path, this.source, this.root);
  final String path;
  final String source;
  final CompilationUnit root;
  bool get isPart => root.directives.any((d) => d is PartOfDirective);
}

Unit parseUnit(String path) {
  final absolute = p.absolute(path);
  final result = parseFile(
    path: absolute,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );
  if (result.errors.isNotEmpty) {
    stderr.writeln('解析失败：$absolute');
    for (final e in result.errors.take(10)) {
      stderr.writeln('  ${e.diagnosticCode.lowerCaseName} @ ${e.offset}');
    }
    exit(2);
  }
  return Unit(absolute, File(absolute).readAsStringSync(), result.unit);
}

/// 父文件 + 其手写 part + 其相对路径 export 出去的独立库（生成物排除在外）。
/// 其中 export 出去的独立库只参与行守恒统计，不参与声明收集。
/// 传入 part 文件时会先解析到库根，保证审计覆盖整个库。
List<Unit> libraryUnits(String entry, {bool includeExports = false}) {
  var parent = parseUnit(entry);
  if (parent.isPart) {
    parent = libraryRootOf(parent);
  }
  final units = <Unit>[parent];
  for (final d in parent.root.directives.whereType<PartDirective>()) {
    final name = d.uri.stringValue ?? '';
    if (generatedSuffixes.any((s) => name.endsWith(s))) continue;
    units.add(parseUnit(p.join(p.dirname(entry), name)));
  }
  if (includeExports) {
    for (final d in parent.root.directives.whereType<ExportDirective>()) {
      final name = d.uri.stringValue ?? '';
      if (name.startsWith('package:') || name.startsWith('dart:')) continue;
      if (generatedSuffixes.any((s) => name.endsWith(s))) continue;
      final path = p.join(p.dirname(entry), name);
      if (!File(path).existsSync()) continue;
      units.add(parseUnit(path));
    }
  }
  return units;
}

String declName(Declaration d) {
  if (d is ClassDeclaration) return d.name.toString();
  if (d is MixinDeclaration) return d.name.toString();
  if (d is EnumDeclaration) return d.name.toString();
  if (d is ExtensionDeclaration) return d.name?.toString() ?? '(anonymous)';
  if (d is FunctionDeclaration) return d.name.toString();
  if (d is TypeAlias) return d.name.toString();
  if (d is TopLevelVariableDeclaration) {
    return d.variables.variables.map((v) => v.name.toString()).join(', ');
  }
  return '(unknown)';
}

class Entry {
  Entry({
    required this.key,
    required this.kind,
    required this.file,
    required this.text,
    required this.startLine,
    required this.endLine,
  });
  final String key;
  final String kind;
  final String file;
  final String text;
  final int startLine;
  final int endLine;
  int get lines => endLine - startLine + 1;
}

/// 声明的完整区间，向前吸收紧邻的文档注释与注解，让注释跟着代码一起搬。
int spanStart(Declaration d, String source) {
  final before = source.substring(0, d.offset);
  final lines = before.split('\n');
  var cut = before.length;
  for (var i = lines.length - 1; i >= 0; i--) {
    final t = lines[i].trim();
    if (t.isEmpty) {
      if (i == lines.length - 1) continue;
      cut -= lines[i].length + 1;
      continue;
    }
    if (t.startsWith('//') ||
        t.startsWith('/*') ||
        t.startsWith('*/') ||
        t.startsWith('*') ||
        t.startsWith('@')) {
      cut -= lines[i].length + 1;
      continue;
    }
    break;
  }
  final start = math.max(cut, 0);
  return source.substring(start, d.offset).trim().isEmpty ? start : d.offset;
}

int lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, math.min(offset, source.length)))
            .length +
    1;

Entry memberEntry(ClassMember m, String owner, Unit u) {
  final String kind;
  final String name;
  if (m is MethodDeclaration) {
    final n = m.name.toString();
    if (m.operatorKeyword != null) {
      kind = 'operator';
      name = 'operator $n';
    } else if (m.isGetter) {
      kind = 'getter';
      name = '$n (getter)';
    } else if (m.isSetter) {
      kind = 'setter';
      name = '$n (setter)';
    } else {
      kind = 'method';
      name = n;
    }
  } else if (m is FieldDeclaration) {
    kind = 'field';
    name = m.fields.variables.map((v) => v.name.toString()).join(', ');
  } else if (m is ConstructorDeclaration) {
    kind = 'constructor';
    name = m.name == null ? 'new $owner' : m.name.toString();
  } else {
    kind = 'other';
    name = '(other)';
  }
  final end = m.endToken.lexeme == ';' ? m.end + 1 : m.end;
  return Entry(
    key: 'member:$owner.$name',
    kind: kind,
    file: u.path,
    text: u.source.substring(m.offset, math.min(end, u.source.length)),
    startLine: lineOf(u.source, m.offset),
    endLine: lineOf(u.source, end),
  );
}

Iterable<ClassMember> membersOf(Declaration d) {
  if (d is ClassDeclaration) return d.members;
  if (d is MixinDeclaration) return d.members;
  if (d is EnumDeclaration) return d.members;
  if (d is ExtensionDeclaration) return d.members;
  return const [];
}

/// 库内所有顶层声明 + 所有类/混入/枚举/扩展成员。原文按节点区间取，不含注释。
List<Entry> collect(String entry) {
  final out = <Entry>[];
  for (final u in libraryUnits(entry)) {
    for (final d in u.root.declarations) {
      out.add(Entry(
        key: 'top:${declName(d)}',
        kind: d.runtimeType.toString(),
        file: u.path,
        text: u.source.substring(d.offset, d.end),
        startLine: lineOf(u.source, d.offset),
        endLine: lineOf(u.source, d.end),
      ));
      final owner = declName(d);
      for (final m in membersOf(d)) {
        out.add(memberEntry(m, owner, u));
      }
    }
  }
  return out;
}

/// 库内所有手写文件的有序非空行；剔除指令与纯注释行，只留可执行文本。
List<String> libraryLines(String entry) {
  final out = <String>[];
  for (final u in libraryUnits(entry)) {
    for (var l in u.source.split('\n')) {
      l = l.trim();
      if (l.isEmpty) continue;
      if (l.startsWith('//')) continue;
      if (l.startsWith('/*') || l.startsWith('*/') || l.startsWith('* ')) {
        continue;
      }
      if (l.startsWith('import ') ||
          l.startsWith('export ') ||
          l.startsWith('part ') ||
          l.startsWith('library ')) {
        continue;
      }
      out.add(l);
    }
  }
  return out;
}

/// new 是否只是 old 删掉若干整块的结果（顺序不变、内容不变、没有新增）。
bool onlyRemoved(String oldText, String newText) {
  List<String> cut(String t) => t
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final o = cut(oldText);
  final n = cut(newText);
  return n.length < o.length && isSubsequence(n, o);
}

/// before 必须是 after 的子序列：证明只发生「整块搬走 + 包上脚手架」。
bool isSubsequence(List<String> before, List<String> after) {
  var i = 0;
  for (final a in after) {
    if (i < before.length && before[i] == a) i++;
  }
  return i == before.length;
}

String sha(String s) {
  // FNV-1a 64：只用于等价性比对，不承担安全用途。
  var h = 0xcbf29ce484222325;
  for (final c in s.codeUnits) {
    h = (h ^ c) & 0xFFFFFFFFFFFFFFFF;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(16, '0');
}

int countLines(String path) => File(path).readAsStringSync().split('\n').length;

String slash(String path) => path.replaceAll(p.separator, '/');

/// 若目标文件本身是某个库的 part，返回它的库根 unit；否则返回自身。
Unit libraryRootOf(Unit u) {
  if (!u.isPart) return u;
  // part of 的 URI 在 analyzer 10 是未公开导出的 DirectiveUri，按文本取。
  final uri = RegExp(
    "^[ \\t]*part[ \\t]+of[ \\t]+['\"]([^'\"]+)['\"]",
    multiLine: true,
  ).firstMatch(u.source)?.group(1);
  if (uri == null || uri.isEmpty) {
    stderr.writeln('无法解析 ${u.path} 的 part of 目标（只支持字符串 URI）');
    exit(6);
  }
  return parseUnit(p.join(p.dirname(u.path), uri));
}

// ------------------------------------------------------------------ commands

void cmdList(Map<String, String> opt) {
  final scope = opt['scope'] ?? 'top';
  final seen = <String>{};
  for (final e in collect(opt['file']!)) {
    if (scope == 'top' && !e.key.startsWith('top:')) continue;
    if (scope == 'member' && !e.key.startsWith('member:')) continue;
    final name = e.key.split(':').last;
    if (seen.add(name)) stdout.writeln(name);
  }
}

void cmdInspect(Map<String, String> opt) {
  final file = opt['file']!;
  final cls = opt['class'];
  final entries = collect(file);
  final base = Directory.current.path;
  String rel(String path) => p.relative(path, from: base);
  if (cls == null) {
    stdout.writeln('== 顶层声明 ($file)  [行数 起始行 名称 种类 所在文件]');
    for (final e in entries.where((e) => e.key.startsWith('top:'))) {
      stdout.writeln(
        '${e.lines.toString().padLeft(5)}  ${e.startLine.toString().padLeft(5)}  '
        '${e.key.substring(4).padRight(38)}${e.kind.padRight(22)}${rel(e.file)}',
      );
    }
    stdout.writeln('== 成员（按类聚合，取行数最大 25 个）');
    final members = entries.where((e) => e.key.startsWith('member:')).toList()
      ..sort((a, b) => b.lines.compareTo(a.lines));
    for (final e in members.take(25)) {
      stdout.writeln(
        '${e.lines.toString().padLeft(5)}  ${e.startLine.toString().padLeft(5)}  '
        '${e.key.substring(7).padRight(45)}${e.kind}',
      );
    }
    return;
  }
  final prefix = 'member:$cls.';
  final members =
      entries.where((e) => e.key.startsWith(prefix)).toList()
        ..sort((a, b) => a.startLine.compareTo(b.startLine));
  stdout.writeln('== class $cls 成员  [行数 起始行 名称 种类 风险标记]');
  for (final e in members) {
    final short = e.key.substring(prefix.length);
    final flags = <String>[];
    if (RegExp(r'\bsuper\b').hasMatch(e.text)) flags.add('USES-SUPER');
    if (e.text.contains('@override')) flags.add('OVERRIDE');
    if (baseMemberDenylist.contains(short.trim())) flags.add('BASE-NAME');
    if (const {'field', 'constructor', 'operator'}.contains(e.kind)) {
      flags.add('CANNOT-MOVE');
    }
    stdout.writeln(
      '${e.lines.toString().padLeft(5)}  ${e.startLine.toString().padLeft(5)}  '
      '${short.padRight(38)}${e.kind.padRight(12)}${flags.join(' ')}',
    );
  }
  var movable = 0;
  var movableCount = 0;
  for (final e in members) {
    final short = e.key.substring(prefix.length).trim();
    if (!const {'method', 'getter', 'setter'}.contains(e.kind)) continue;
    if (RegExp(r'\bsuper\b').hasMatch(e.text)) continue;
    if (e.text.contains('@override')) continue;
    if (baseMemberDenylist.contains(short)) continue;
    movable += e.lines;
    movableCount++;
  }
  stdout.writeln('== 可搬成员合计: $movable 行 / $movableCount 个 (类内共 ${members.length} 个成员)');
}

/// 每个手写文件 -> 有序可执行行（含 export 出去的独立库）。
Map<String, List<String>> linesPerFile(String entry) {
  final out = <String, List<String>>{};
  for (final u in libraryUnits(entry, includeExports: true)) {
    final lines = <String>[];
    for (var l in u.source.split('\n')) {
      l = l.trim();
      if (l.isEmpty) continue;
      if (l.startsWith('//')) continue;
      if (l.startsWith('/*') || l.startsWith('*/') || l.startsWith('* ')) {
        continue;
      }
      if (l.startsWith('import ') ||
          l.startsWith('export ') ||
          l.startsWith('part ') ||
          l == 'library;' ||
          l.startsWith('library ')) {
        continue;
      }
      lines.add(l);
    }
    out[p.normalize(u.path)] = lines;
  }
  return out;
}

void cmdSnapshot(Map<String, String> opt) {
  final file = opt['file']!;
  final out = opt['out'] ?? '$file.ast-snapshot.json';
  final entries = collect(file);
  final perFile = linesPerFile(file);
  final concatenated = <String>[];
  for (final l in perFile.values) {
    concatenated.addAll(l);
  }
  final inventory = <String, int>{};
  for (final l in concatenated) {
    inventory[l] = (inventory[l] ?? 0) + 1;
  }
  final json = {
    'entry': p.normalize(file),
    'totalLines': countLines(file),
    'perFile': perFile,
    'lineSequence': concatenated,
    'lineInventory': inventory,
    'entries': {
      for (final e in entries)
        e.key: {'sha': sha(e.text), 'lines': e.lines, 'text': e.text},
    },
  };
  File(out).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  stdout.writeln('snapshot -> $out (${entries.length} entries, '
      '${perFile.length} files, ${concatenated.length} 可执行行)');
}

bool cmdAudit(Map<String, String> opt) {
  final snapFile = opt['snapshot']!;
  final snap =
      jsonDecode(File(snapFile).readAsStringSync()) as Map<String, dynamic>;
  final file = (opt['file'] ?? snap['entry']) as String;
  final before = (snap['entries'] as Map).cast<String, dynamic>();
  final after = {for (final e in collect(file)) e.key: e};
  var ok = true;
  stdout.writeln('audit ${p.normalize(file)}');

  // (1) 逐键原文哈希：容器类节点因成员搬出而变小属预期，其余一律视为改写。
  final modified = <String>[], shrunk = <String>[];
  final movedOut = <String>[], added = <String>[];
  for (final kv in before.entries) {
    final a = after[kv.key];
    if (a == null) {
      movedOut.add(kv.key);
      continue;
    }
    final oldText = (kv.value as Map)['text']?.toString() ?? '';
    if ((kv.value as Map)['sha'] != sha(a.text)) {
      // 允许「中间整块被搬走」：剩余行必须是原行的子序列且更短。
      if (onlyRemoved(oldText, a.text)) {
        shrunk.add(kv.key);
      } else {
        modified.add(kv.key);
      }
    }
  }
  for (final k in after.keys) {
    if (!before.containsKey(k)) added.add(k);
  }
  stdout.writeln('  改写: ${modified.length}  缩小: ${shrunk.length}  '
      '搬出: ${movedOut.length}  新键: ${added.length}');
  for (final m in modified.take(20)) {
    stdout.writeln('  MODIFIED  $m');
    ok = false;
  }
  for (final s in shrunk.take(6)) {
    stdout.writeln('  SHRUNK    $s  (成员搬出，预期)');
  }
  for (final r in movedOut.take(6)) {
    stdout.writeln('  MOVED-OUT $r  (整块搬走)');
  }
  for (final a in added.take(6)) {
    stdout.writeln('  NEW       $a  ${after[a]!.lines}L');
  }

  // (2) 每个文件的行必须是原先的**子序列**：只允许删行（被搬走），不允许改写或重排。
  final oldPerFile = (snap['perFile'] as Map).cast<String, dynamic>();
  final newPerFile = linesPerFile(file);
  final beforeAll = (snap['lineSequence'] as List).cast<String>();
  for (final kv in newPerFile.entries) {
    final oldPath = oldPerFile[kv.key];
    if (oldPath != null) {
      final old = (oldPath as List).cast<String>();
      if (!isSubsequence(kv.value, old)) {
        stdout.writeln('  ORDER/BODY 破坏: ${kv.key}  '
            '(${old.length} -> ${kv.value.length} 行，剩余行不再保持原顺序)');
        ok = false;
      } else if (old.length != kv.value.length) {
        stdout.writeln('  瘦身: ${kv.key}  '
            '${old.length} -> ${kv.value.length} 行（${old.length - kv.value.length} 行搬出）');
      }
    } else {
      // 新文件允许 extension 脚手架行（它不在原库中，属包装而非内容）。
      final body = kv.value
          .where((l) => !RegExp(r'^extension \w+ on .+ \{$').hasMatch(l))
          .toList();
      if (!isSubsequence(body, beforeAll)) {
        stdout.writeln('  新文件内容不是原库的原文子序列: ${kv.key}');
        ok = false;
      } else {
        stdout.writeln('  新文件: ${kv.key}  ${body.length} 行，'
            '全部为原库原文（按序）');
      }
    }
  }
  final oldFiles = <String>{for (final k in oldPerFile.keys) k};
  for (final k in oldFiles) {
    if (!newPerFile.containsKey(k)) {
      stdout.writeln('  文件消失: $k');
      ok = false;
    }
  }

  // (3) 全局行多重集合守恒：搬走的行必须整体出现在别处，一行都不许蒸发。
  final afterInv = <String, int>{};
  for (final l in beforeAll) {
    afterInv[l] = (afterInv[l] ?? 0) + 1;
  }
  final afterAll = <String>[];
  for (final l in newPerFile.values) {
    afterAll.addAll(l);
  }
  final afterCount = <String, int>{};
  for (final l in afterAll) {
    afterCount[l] = (afterCount[l] ?? 0) + 1;
  }
  final lost = <String>[];
  for (final kv in afterInv.entries) {
    final have = afterCount[kv.key] ?? 0;
    if (have < kv.value) lost.add('${kv.key}  (x${kv.value} -> x$have)');
  }
  stdout.writeln('  丢失行: ${lost.length}   总可执行行: '
      '${beforeAll.length} -> ${afterAll.length}');
  for (final l in lost.take(15)) {
    stdout.writeln('  LOST   $l');
    ok = false;
  }
  if (opt['diff'] == 'true') {
    for (final m in modified) {
      stdout.writeln('--- DIFF $m');
      final a = ((before[m] as Map)['text'] ?? '').toString().split('\n');
      final b = after[m]!.text.split('\n');
      for (var i = 0; i < math.max(a.length, b.length); i++) {
        final x = i < a.length ? a[i] : '<none>';
        final y = i < b.length ? b[i] : '<none>';
        if (x != y) stdout.writeln('  -$x\n  +$y');
      }
    }
  }
  stdout.writeln('  行数: ${snap['totalLines']} -> ${countLines(file)}');
  stdout.writeln(ok ? 'AUDIT PASS' : 'AUDIT FAIL');
  return ok;
}

// ------------------------------------------------------------------ mutations

/// Dart 要求指令顺序：library -> import -> export -> part。
/// 用 AST 里真实 directive 的偏移插入，避免落进跨行指令内部。
String insertDirectiveAt(String src, String directive, CompilationUnit root) {
  Directive? lastPart, lastExport, lastImport, firstPart;
  for (final d in root.directives) {
    if (d is PartDirective) {
      lastPart = d;
      firstPart ??= d;
    } else if (d is ExportDirective) {
      lastExport = d;
    } else if (d is ImportDirective) {
      lastImport = d;
    }
  }
  // 没有任何指令时，必须插在第一个声明之前，否则触发
  // directive_after_declaration。
  final firstDecl =
      root.declarations.isNotEmpty ? root.declarations.first.offset : null;
  final int at;
  if (directive.startsWith('part ')) {
    at = lastPart?.end ??
        lastExport?.end ??
        lastImport?.end ??
        firstDecl ??
        src.length;
  } else {
    at = firstPart?.offset ??
        lastExport?.end ??
        lastImport?.end ??
        firstDecl ??
        src.length;
  }
  if (at == 0) return '$directive\n\n$src';
  final head = src.substring(0, at);
  final tailText = src.substring(at);
  final lead = head.endsWith('\n') ? '' : '\n';
  final tail = tailText.startsWith('\n') || tailText.isEmpty ? '' : '\n';
  return '$head$lead$directive\n$tail$tailText';
}

List<String> directivesOf(CompilationUnit root, String source) =>
    root.directives
        .where((d) => d is ImportDirective || d is ExportDirective)
        .map((d) => source.substring(d.offset, d.end))
        .toList();

void cmdExtract(Map<String, String> opt, {required bool asPart}) {
  final file = opt['file']!;
  final to = opt['to']!;
  final wanted = nameList(opt, 'decls');
  final note = opt['note'] ?? '';
  final units = libraryUnits(file);
  final parent = units.first;
  final found = <Declaration, Unit>{};
  for (final u in units) {
    for (final d in u.root.declarations) {
      if (wanted.contains(declName(d))) found[d] = u;
    }
  }
  final got = found.keys.map(declName).toSet();
  if (got.length != wanted.length) {
    final missing = wanted.where((w) => !got.contains(w)).join(', ');
    stderr.writeln('找不到声明: $missing  (命中 ${got.length}/${wanted.length})');
    exit(3);
  }
  final byFile = <String, List<Declaration>>{};
  for (final e in found.entries) {
    byFile.putIfAbsent(e.value.path, () => []).add(e.key);
  }
  final edits = <String, String>{};
  byFile.forEach((path, decls) {
    var src = File(path).readAsStringSync();
    final ranges = decls.map((d) => [spanStart(d, src), d.end]).toList()
      ..sort((a, b) => b[0].compareTo(a[0]));
    for (final r in ranges) {
      src = src.substring(0, r[0]) + src.substring(r[1]);
    }
    edits[path] = src.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  });
  final pieces = <String>[];
  if (asPart) {
    pieces.add("part of '${slash(p.relative(file, from: p.dirname(to)))}';");
  } else {
    pieces.add('// 从 ${p.basename(file)} 抽出的独立模块。');
    pieces.add('// 原文件 export 本文件，因此既有调用方的 import 无需改动。');
  }
  if (note.isNotEmpty) pieces.add('// $note');
  pieces.add('');
  if (!asPart) {
    pieces.addAll(directivesOf(parent.root, parent.source));
    pieces.add('');
  }
  for (final e in found.entries) {
    final src = File(e.value.path).readAsStringSync();
    pieces.add(src.substring(spanStart(e.key, src), e.key.end).trimRight());
    pieces.add('');
  }
  Directory(p.dirname(to)).createSync(recursive: true);
  File(to).writeAsStringSync(pieces.join('\n'));
  final root = libraryRootOf(parent);
  // 独立库要同时 import + export：Dart 的 export 不会把符号带进本库作用域，
  // 父文件里剩下的代码仍要引用被搬走的类型。
  final directives = asPart
      ? [
          "part '${slash(p.relative(to, from: p.dirname(root.path)))}';",
        ]
      : [
          "import '${slash(p.relative(to, from: p.dirname(root.path)))}';",
          "export '${slash(p.relative(to, from: p.dirname(root.path)))}';",
        ];
  final touched = edits.keys.toSet()..add(root.path);
  for (final path in touched) {
    var text = edits[path] ?? File(path).readAsStringSync();
    if (path == root.path) {
      for (final d in directives) {
        final re = parseUnit(path.startsWith('/') ? path : p.absolute(path));
        text = insertDirectiveAt(text, d, re.root);
      }
    }
    File(path).writeAsStringSync(text);
  }
  stdout.writeln(
    'extracted ${found.length} decl(s) -> $to  主文件 ${countLines(file)} 行',
  );
}

void cmdExtractMembers(Map<String, String> opt) {
  final file = opt['file']!;
  final to = opt['to']!;
  final cls = opt['class']!;
  final ext = opt['extension']!;
  final wanted = nameList(opt, 'members');
  final force = opt.containsKey('force');
  Unit? owner;
  ClassDeclaration? target;
  for (final u in libraryUnits(file)) {
    for (final d in u.root.declarations) {
      if (d is ClassDeclaration && declName(d) == cls) {
        target = d;
        owner = u;
      }
    }
  }
  if (target == null || owner == null) {
    stderr.writeln('找不到 class $cls');
    exit(3);
  }
  final src = owner.source;
  final picked = <ClassMember>[];
  final problems = <String>[];
  for (final m in target.members) {
    final e = memberEntry(m, cls, owner);
    final short = e.key.substring('member:$cls.'.length);
    if (!wanted.contains(short)) continue;
    if (m is FieldDeclaration) problems.add('$short: 字段不能进 extension');
    if (m is ConstructorDeclaration) {
      problems.add('$short: 构造函数不能进 extension');
    }
    if (m is MethodDeclaration && m.operatorKeyword != null) {
      problems.add('$short: operator 不能进 extension');
    }
    if (m.metadata.any((a) => a.name.toString().contains('override'))) {
      problems.add('$short: 带 @override，搬走会破坏覆写');
    }
    if (RegExp(r'\bsuper\b').hasMatch(src.substring(m.offset, m.end))) {
      problems.add('$short: 用了 super');
    }
    if (baseMemberDenylist.contains(short.trim()) && !force) {
      problems.add('$short: 与基类成员同名，静态派发会改变行为');
    }
    picked.add(m);
  }
  if (picked.isEmpty) {
    stderr.writeln('没有匹配到任何成员，拒绝写出空 extension');
    exit(5);
  }
  if (problems.isNotEmpty) {
    stderr.writeln('拒绝执行（class $cls）：');
    for (final pr in problems) {
      stderr.writeln('  - $pr');
    }
    exit(4);
  }
  if (picked.length != wanted.length) {
    stderr.writeln('只匹配到 ${picked.length}/${wanted.length} 个成员');
    exit(3);
  }
  // 从行首切，保住成员自身的缩进，也不在原处留下带空格的残行。
  int start(String src, ClassMember m) {
    final ls = src.lastIndexOf('\n', m.offset - 1) + 1;
    return src.substring(ls, m.offset).trim().isEmpty ? ls : m.offset;
  }

  final ranges = picked.map((m) => [start(src, m), m.end]).toList()
    ..sort((a, b) => b[0].compareTo(a[0]));
  final movedText = picked
      .map((m) => src.substring(start(src, m), m.end).trimRight())
      .join('\n');
  var newSrc = src;
  for (final r in ranges) {
    newSrc = newSrc.substring(0, r[0]) + newSrc.substring(r[1]);
  }
  newSrc = newSrc.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  Directory(p.dirname(to)).createSync(recursive: true);
  File(to).writeAsStringSync(
    "part of '${slash(p.relative(file, from: p.dirname(to)))}';\n\n"
    '// 从 class $cls 搬出的方法组；extension 与宿主类同库，可直接访问私有成员。\n'
    'extension $ext on $cls {\n$movedText\n}\n',
  );
  final root = libraryRootOf(owner);
  // 先写回被摘除成员的宿主文件，再把新 part 注册到库根。
  if (owner.path != root.path) {
    File(owner.path).writeAsStringSync(newSrc);
  }
  File(root.path).writeAsStringSync(
    insertDirectiveAt(
      root.path == owner.path ? newSrc : root.source,
      "part '${slash(p.relative(to, from: p.dirname(root.path)))}';",
      root.root,
    ),
  );
  stdout.writeln(
    'extracted ${picked.length} member(s) of $cls -> $to '
    '(extension $ext)  主文件 ${countLines(file)} 行',
  );
}


// ------------------------------------------------ 语言无关的文本守恒审计

/// 供 Rust / C++ / JS 等没有 AST 解析器的语言使用：
/// 不看语法结构，只看「有意义的行」是否整体搬移、顺序是否保持。
List<String> textMeaningfulLines(String path) {
  final out = <String>[];
  for (var l in File(path).readAsStringSync().split('\n')) {
    l = l.trim();
    if (l.isEmpty) continue;
    if (l.startsWith('//') || l.startsWith('/*') || l.startsWith('*/') ||
        l.startsWith('*') || (l.startsWith('#') && !l.startsWith('#['))) {
      continue;
    }
    if (l.startsWith('use ') || l.startsWith('pub use ') ||
        l.startsWith('mod ') || l.startsWith('pub mod ') ||
        l.startsWith('#include') || l.startsWith('import ') ||
        l.startsWith('export ') || l.startsWith('from ') ||
        l.startsWith('part ') || l.startsWith('library ')) {
      continue;
    }
    out.add(l);
  }
  return out;
}

Map<String, List<String>> textPerFile(List<String> files) {
  final out = <String, List<String>>{};
  for (final f in files) {
    out[p.normalize(p.absolute(f))] = textMeaningfulLines(f);
  }
  return out;
}

void cmdTextSnapshot(Map<String, String> opt) {
  final files = nameList(opt, 'files');
  if (files.isEmpty) {
    stderr.writeln('需要 --files a,b,c');
    exit(64);
  }
  final perFile = textPerFile(files);
  final all = <String>[];
  for (final l in perFile.values) {
    all.addAll(l);
  }
  final inv = <String, int>{};
  for (final l in all) {
    inv[l] = (inv[l] ?? 0) + 1;
  }
  File(opt['out']!).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'files': perFile.keys.toList(),
    'perFile': perFile,
    'inventory': inv,
    'total': all.length,
  }));
  stdout.writeln('text-snapshot -> ${opt['out']} (${files.length} 文件, '
      '${all.length} 有意义行)');
}

bool cmdTextAudit(Map<String, String> opt) {
  final snapFile = opt['snapshot']!;
  final snap =
      jsonDecode(File(snapFile).readAsStringSync()) as Map<String, dynamic>;
  final oldPerFile = (snap['perFile'] as Map).cast<String, dynamic>();
  final oldAll = <String>[];
  for (final l in oldPerFile.values) {
    oldAll.addAll((l as List).cast<String>());
  }
  final oldInv = (snap['inventory'] as Map).cast<String, dynamic>();
  // 现在这批文件 + 它们同目录/子目录下新增的同语言文件
  final candidates = <String>[for (final k in oldPerFile.keys) k];
  final declared = nameList(opt, 'new').map((f) => p.absolute(f)).toList();
  if (declared.isNotEmpty) {
    // 显式声明新文件，避免把并发 agent 落在同一目录的文件算进来。
    candidates.addAll(declared.where((f) => File(f).existsSync()));
  } else {
    final dirs = <String>{for (final k in oldPerFile.keys) p.dirname(k)};
    for (final d in dirs) {
      for (final e in Directory(d).listSync(recursive: true)) {
        if (e is! File) continue;
        final abs = p.absolute(e.path);
        if (candidates.contains(abs)) continue;
        if (!const ['.rs', '.cpp', '.h', '.js', '.py', '.dart']
            .contains(p.extension(abs))) {
          continue;
        }
        candidates.add(abs);
      }
    }
  }
  final nowPerFile = textPerFile(candidates);
  var ok = true;
  var lostTotal = 0;
  for (final kv in oldPerFile.entries) {
    final old = (kv.value as List).cast<String>();
    final now = nowPerFile[kv.key] ?? const <String>[];
    if (!isSubsequence(now, old)) {
      stdout.writeln('  改写/重排: ${kv.key}  (${old.length} -> ${now.length} 行，'
          '剩余行未保持原顺序)');
      ok = false;
    } else if (now.length < old.length) {
      stdout.writeln('  瘦身: ${p.basename(kv.key)}  ${old.length} -> ${now.length}'
          '  (${old.length - now.length} 行搬出)');
    }
  }
  final nowInv = <String, int>{};
  final nowAll = <String>[];
  for (final l in nowPerFile.values) {
    for (final x in l) {
      nowInv[x] = (nowInv[x] ?? 0) + 1;
      nowAll.add(x);
    }
  }
  for (final kv in oldInv.entries) {
    final want = kv.value as int;
    final have = nowInv[kv.key] ?? 0;
    if (have < want) {
      lostTotal++;
      if (lostTotal <= 15) {
        stdout.writeln('  LOST  ${kv.key}  (x$want -> x$have)');
      }
      ok = false;
    }
  }
  for (final kv in nowPerFile.entries) {
    if (oldPerFile.containsKey(kv.key)) continue;
    if (kv.value.isEmpty) continue;
    if (!isSubsequence(kv.value, oldAll)) {
      stdout.writeln('  新文件不是原文子序列: ${kv.key}  (${kv.value.length} 行)');
      ok = false;
    } else {
      stdout.writeln('  新文件: ${p.basename(kv.key)}  ${kv.value.length} 行，'
          '全部为原文（按序）');
    }
  }
  stdout.writeln('  有意义行合计: ${oldAll.length} -> ${nowAll.length}   '
      '丢失: $lostTotal');
  stdout.writeln(ok ? 'TEXT AUDIT PASS' : 'TEXT AUDIT FAIL');
  return ok;
}
