import 'package:flutter/foundation.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/src/rust/api/operation_binding.dart';

/// 启动、同步和恢复共用的迁移边界。成功后绑定与原文备份一起落盘；
/// 损坏或未知版本保留原文，运行时不会尝试执行旧格式。
OperationBindingSettingState migrateOperationBindingSetting(
  OperationBindingSettingState setting, {
  OperationBindingSettingState? fallback,
}) {
  final raw = setting.bindingsJson;
  if (raw.trim().isEmpty) return setting;
  final current = isCurrentBindingsDoc(raw);
  if (current && (fallback == null || raw == fallback.bindingsJson)) {
    return setting;
  }
  try {
    final migrated = operationBindingMigrateDocument(documentJson: raw);
    return setting.copyWith(
      bindingsJson: migrated,
      bindingsMigrationBackupJson: current
          ? setting.bindingsMigrationBackupJson
          : raw,
    );
  } catch (error) {
    debugPrint('操作绑定迁移失败，已保留原配置：$error');
    return fallback ?? setting;
  }
}

GlobalSettingState migrateOperationBindingsInSettings(
  GlobalSettingState state, {
  GlobalSettingState? fallback,
}) {
  final migrated = migrateOperationBindingSetting(
    state.operationBindingSetting,
    fallback: fallback?.operationBindingSetting,
  );
  return identical(migrated, state.operationBindingSetting)
      ? state
      : state.copyWith(operationBindingSetting: migrated);
}
