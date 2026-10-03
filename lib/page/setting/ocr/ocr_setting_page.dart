import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/ocr/ocr_settings_body.dart';

/// 漫画翻译（成品页）的设置页。
///
/// 权重与端点放同一页：缺任何一个都出不了成品页，分两处摆会让人以为「已经配好了」。
/// 正文在 [OcrSettingsBody] —— 工作台的翻译卡片原地展开的是**同一份**，
/// 所以这里只留一层页壳。
@RoutePage()
class OcrSettingPage extends StatelessWidget {
  const OcrSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingPageShell(title: t.ocr.title, child: const OcrSettingsBody());
  }
}
