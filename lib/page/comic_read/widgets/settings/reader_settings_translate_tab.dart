part of 'reader_settings_sheet.dart';

/// 「翻译」这一排。
///
/// 正文在 [TranslateSettingsSection]，工作台控制面板那张翻译卡渲染的是同一份。
/// 这一层只做面板才有的那一头：**跳去完整设置页**（面板有路由可弹，
/// 卡片弹不掉任何东西，所以它传 null 改成就地展开 [OcrSettingsBody]）。
///
/// 这一排只在桌面出现：见 [_visibleReaderSettingsTabs] 与 `ocrSupportedHere`。
class _ReaderSettingsTranslateTab extends StatelessWidget {
  const _ReaderSettingsTranslateTab();

  @override
  Widget build(BuildContext context) {
    return _SettingsTabContent(
      child: TranslateSettingsSection(
        onOpenFullSettings: () {
          Navigator.of(context).maybePop();
          AutoRouter.of(context).push(const OcrSettingRoute());
        },
      ),
    );
  }
}
