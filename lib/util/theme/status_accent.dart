// 状态色：M3 的角色表里没有 success / warning，但把 `Colors.green` 直接画上去更糟 ——
// 它不随亮度走，压在深色 `surfaceContainerHigh` 上几乎糊成一片，也不跟导入的主题有任何关系。
//
// 这里的口径是**固定色相、放开色调**：绿还是绿、橙还是橙，但具体哪一档绿由 Material
// 取色按当前亮度算出来（`ColorScheme.fromSeed(...).primary` 保证与同亮度的 surface
// 有可用对比度）。需要「和主题强调色区分开」的语义状态都走这里。

import 'package:material_ui/material_ui.dart';

/// 需要独立于 M3 角色的状态色。
enum StatusHue { success, warning }

const Map<StatusHue, Color> _statusSeeds = {
  StatusHue.success: Color(0xFF2E9E5B),
  StatusHue.warning: Color(0xFFE08A00),
};

/// 取色要跑一遍 HCT，所以每种色相 × 亮度只算一次（顶层 `final` 是懒初始化的）。
final Map<StatusHue, Map<Brightness, Color>> _statusAccents = {
  for (final entry in _statusSeeds.entries)
    entry.key: {
      for (final brightness in Brightness.values)
        brightness: ColorScheme.fromSeed(
          seedColor: entry.value,
          brightness: brightness,
        ).primary,
    },
};

/// [context] 只用来读亮度：状态色跟明暗档位走，**不**跟用户的种子色走 ——
/// 否则「成功」会和「信息」撞成同一个颜色，状态就白分了。
Color statusAccent(BuildContext context, StatusHue hue) =>
    _statusAccents[hue]![Theme.of(context).brightness]!;
