import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 数据库 schema 比当前代码新时的兜底界面。
///
/// 通常出现在用户降级安装（旧版本覆盖新版本）后，ObjectBox 无法打开
/// 更高版本的数据库。此时不进入正常应用，只提示用户升级。
class DatabaseIncompatibleApp extends StatelessWidget {
  const DatabaseIncompatibleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_rounded, size: 56),
                const SizedBox(height: 16),
                Text(
                  t.database.incompatible,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => SystemNavigator.pop(),
                  child: Text(t.common.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
