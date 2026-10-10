// 把两份**纯 Dart** 判据挂进 `flutter test`，让它们在任何时候都有一把能落地的尺。
//
// 原本那两份的跑法是 `dart run`（文件头写了原因：不用拖起整套 binding）：
//   dart run test/workspace/file_manager_entry_menu_check.dart
//   dart run test/workspace/reveal_in_file_manager_check.dart
// 但本机现在的 `dart run` 进不去：包图里 `objective_c` 的 `hook.dill` 与当前
// Dart SDK 的哈希不合（`Can't load Kernel binary: Invalid SDK hash`），
// **任何** check 文件都被这一步拦下 —— 既有那份 `file_manager_entry_menu_check.dart`
// 同样失败，不是这次改动造成的。所以这里原样调用它们的 `main()`：
// 断言一个字都没改，只是换一个进得去的门。失败时 StateError 的消息会直接
// 出现在测试输出里（`FAIL: …`），和 `dart run` 看到的完全一样。
//
// 这两份判据的 import 图只有 `dart:io` + `package:path` + 规格文件本身，
// 不碰 widget、不碰桥，所以不会被别的在途编译错误连坐。

import 'package:flutter_test/flutter_test.dart';

import 'file_manager_entry_menu_check.dart' as menu_check;
import 'reveal_in_file_manager_check.dart' as reveal_check;

void main() {
  test('右键菜单规格：十一个动作、谁灰、谁要确认、谁在前', () {
    menu_check.main();
  });

  test('「在系统文件管理器里显示」的命令形状：argv 逐字、三家措辞不同', () {
    reveal_check.main();
  });
}
