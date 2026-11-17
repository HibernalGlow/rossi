import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/service/app_identity/startup.dart';

/// 首启提示复用现有备份页。移动沙盒之间不尝试读写旧应用的私有文件。
class AppIdentityMigrationNotice extends StatefulWidget {
  const AppIdentityMigrationNotice({super.key, required this.child});

  final Widget child;

  @override
  State<AppIdentityMigrationNotice> createState() =>
      _AppIdentityMigrationNoticeState();
}

class _AppIdentityMigrationNoticeState
    extends State<AppIdentityMigrationNotice> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNotice());
  }

  Future<void> _showNotice() async {
    final notice = identityMigrationNotice;
    if (!mounted || notice == null) return;
    final dialogContext = navigatorKey.currentState?.overlay?.context;
    if (dialogContext == null) return;
    identityMigrationNotice = null;
    final copied = notice['status'] == 'copied';
    // incompatible：迁移副本是旧版 Breeze 的新结构，打不开，已改名让开。
    // 对用户来说同样是「没能自动搬过来」，走备份导入那条路。
    final failed =
        notice['status'] == 'error' || notice['status'] == 'incompatible';
    final openBackup = await showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text(t.appIdentityMigration.title),
        content: Text(
          copied
              ? t.appIdentityMigration.copied(
                  source: notice['source'] as String,
                )
              : failed
              ? '${t.appIdentityMigration.sandboxImport}\n\n${notice['error']}'
              : (Platform.isAndroid || Platform.isIOS)
              ? t.appIdentityMigration.mobileImport
              : t.appIdentityMigration.sandboxImport,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.common.confirm),
          ),
          if (!copied)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.dataBackup.importData),
            ),
        ],
      ),
    );
    if (mounted && openBackup == true) {
      await appRouter.push(const DataBackupRoute());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
