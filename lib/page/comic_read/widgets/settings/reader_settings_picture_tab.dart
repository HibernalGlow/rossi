part of 'reader_settings_sheet.dart';

/// 「画面」这一排：改变的是**像素本身** —— 放大、滤镜、墨水屏、动画、
/// 哪些后缀算图 / 算视频。与「界面」那一排的分工判据是：
/// 关掉这一排的开关，画面上的内容就变了；关掉那一排，内容一个像素没动。
class _ReaderSettingsPictureTab extends StatelessWidget {
  const _ReaderSettingsPictureTab();

  @override
  Widget build(BuildContext context) {
    return const _SettingsTabContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SuperResolutionSection(),
          SizedBox(height: 18),
          ImageDenoiseSection(),
          SizedBox(height: 18),
          ImageTuningSection(),
          SizedBox(height: 18),
          _MediaFormatSection(),
          SizedBox(height: 18),
          _VideoSection(),
        ],
      ),
    );
  }
}
