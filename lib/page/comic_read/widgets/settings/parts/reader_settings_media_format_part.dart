part of '../reader_settings_sheet.dart';

// rossi

/// 「哪些后缀算图片 / 算视频」。
///
/// # 为什么单独一段而不是塞进上面的视频段
///
/// 这张表判的是**文件管理器列不列一个条目**（`folder_tree::is_recognized_image_ext`
/// 在 Rust 侧），影响面是整库浏览，不是「这一页怎么播」。放错段的代价不是难看而已：
/// 用户要找的是「为什么这个文件看不见」，而它会在播放设置里被划过去。
///
/// # 语义是替换，不是追加
///
/// 照 neoview `media.ts:64-65`：**填了就整体替换内置表**，没列进来的后缀会连页都不算。
/// 留空才继续用内置默认。所以这两颗的提示必须把「填错不是多加一条，而是其余全不见」
/// 说在前面 —— 这是这次改动最容易自我伤害的一处。
/// 上面那段里原有的「自定义视频后缀」是**追加**档，两档并存：替换档定基线，
/// 追加档永远叠在基线之上。
///
/// 存在 `VideoSettingsStore`：两张表要和 `extraVideoExtensions` **同进同出**推给 Rust
/// （见 `VideoSettingsStore._apply`），拆成两个存储就会有一张表被推漏的那天。
class _MediaFormatSection extends StatefulWidget {
  const _MediaFormatSection();

  @override
  State<_MediaFormatSection> createState() => _MediaFormatSectionState();
}

class _MediaFormatSectionState extends State<_MediaFormatSection> {
  VideoSettings _settings = const VideoSettings();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await VideoSettingsStore.instance.load();
    if (!mounted) return;
    setState(() => _settings = loaded);
  }

  Future<void> _write(VideoSettings next) async {
    setState(() => _settings = next);
    await VideoSettingsStore.instance.save(next);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: t.video.mediaSection,
      icon: Icons.folder_copy_rounded,
      children: [
        SettingsCardGroup(
          children: [
            _StringListTile(
              title: t.video.imageFormats,
              hint: t.video.formatsHint,
              dialogHint: t.video.aliasesDialogHint,
              values: _settings.imageFormats,
              validate: (next) => mediaFormatTableProblems(
                image: next,
                video: _settings.videoFormats,
              ),
              onChanged: (next) =>
                  _write(_settings.copyWith(imageFormats: next)),
            ),
            _StringListTile(
              title: t.video.videoFormats,
              hint: t.video.formatsHint,
              dialogHint: t.video.aliasesDialogHint,
              values: _settings.videoFormats,
              validate: (next) => mediaFormatTableProblems(
                image: _settings.imageFormats,
                video: next,
              ),
              onChanged: (next) =>
                  _write(_settings.copyWith(videoFormats: next)),
            ),
          ],
        ),
      ],
    );
  }
}
