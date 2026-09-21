part of '../reader_settings_read_tab.dart';
// rossi


/// 视频播放设置。
///
/// 存在 `VideoSettingsStore` 而不是 `ReadSettingState`，理由与 `_SuperResolutionSection`
/// 一模一样（它也自带一个 SharedPreferences 服务）：**这些项不该触发阅读页重建**。
/// 排版设置一改整本要重排，而「倍速上限」「动图当视频播」只影响播放那条路。
/// 写盘同样是「先 setState 再 await」——设置界面卡顿比晚 100 ms 落盘难看得多。
class _VideoSection extends StatefulWidget {
  const _VideoSection();

  @override
  State<_VideoSection> createState() => _VideoSectionState();
}


class _VideoSectionState extends State<_VideoSection> {
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
    return _SettingsSection(
      title: t.video.settingsSection,
      icon: Icons.video_settings_rounded,
      children: [
        _SettingsCardGroup(
          children: [
            _SettingsSwitchTile(
              title: t.video.autoPlay,
              subtitle: t.video.autoPlayDesc,
              value: _settings.autoPlay,
              onChanged: (value) => _write(_copy(autoPlay: value)),
            ),
            _SettingsSwitchTile(
              title: t.video.hwDecode,
              subtitle: t.video.hwDecodeDesc,
              value: _settings.hardwareDecode,
              onChanged: (value) => _write(_copy(hardwareDecode: value)),
            ),
            _SettingsSwitchTile(
              title: t.video.deinterlace,
              subtitle: t.video.deinterlaceDesc,
              value: _settings.deinterlace,
              onChanged: (value) => _write(_copy(deinterlace: value)),
            ),
            _StringListTile(
              title: t.video.aliases,
              hint: t.video.aliasesHint,
              dialogHint: t.video.aliasesDialogHint,
              values: _settings.extraVideoExtensions,
              validate: (next) =>
                  MediaKindOverrides(extraVideoExtensions: next).invalidEntries,
              onChanged: (next) => _write(_copy(extraVideoExtensions: next)),
            ),
            if (_settings.animatedVideoEnabled)
              _StringListTile(
                title: t.video.animatedKeywords,
                hint: t.video.animatedKeywordsHint,
                dialogHint: t.video.aliasesDialogHint,
                values: _settings.animatedVideoKeywords,
                onChanged: (next) => _write(_copy(animatedVideoKeywords: next)),
              ),
            _SettingsSwitchTile(
              title: t.video.pin,
              subtitle: t.video.pinDesc,
              value: _settings.controlsPinned,
              onChanged: (value) => _write(_copy(controlsPinned: value)),
            ),
            _SettingsSwitchTile(
              title: t.video.animatedVideo,
              subtitle: t.video.animatedVideoDesc,
              value: _settings.animatedVideoEnabled,
              onChanged: (value) => _write(_copy(animatedVideoEnabled: value)),
            ),
            _SettingsAnimatedCollapse(
              isExpanded: _settings.animatedVideoEnabled,
              child: _SettingsSliderCard(
                title: t.video.autoHide,
                value: _settings.autoHideMilliseconds,
                min: 1000,
                max: 10000,
                divisions: 9,
                suffix: 'ms',
                onChanged: (value) =>
                    _write(_copy(autoHideMilliseconds: value)),
              ),
            ),
            _SettingsSliderCard(
              title: t.video.maxRate,
              value: (_settings.maxRate * 100).round(),
              min: 100,
              max: 1600,
              divisions: 30,
              suffix: '%',
              onChanged: (value) => _write(_copy(maxRate: value / 100)),
            ),
            _SettingsSliderCard(
              title: t.video.defaultVolume,
              value: _settings.volumePercent,
              min: 0,
              max: 130,
              divisions: 13,
              suffix: '%',
              onChanged: (value) => _write(_copy(volumePercent: value)),
            ),
          ],
        ),
      ],
    );
  }

  VideoSettings _copy({
    bool? controlsPinned,
    bool? hardwareDecode,
    bool? autoPlay,
    double? maxRate,
    int? autoHideMilliseconds,
    int? volumePercent,
    bool? animatedVideoEnabled,
    bool? deinterlace,
    List<String>? extraVideoExtensions,
    List<String>? animatedVideoKeywords,
  }) => _settings.copyWith(
    controlsPinned: controlsPinned,
    hardwareDecode: hardwareDecode,
    autoPlay: autoPlay,
    maxRate: maxRate,
    autoHideMilliseconds: autoHideMilliseconds,
    volumePercent: volumePercent,
    animatedVideoEnabled: animatedVideoEnabled,
    deinterlace: deinterlace,
    extraVideoExtensions: extraVideoExtensions,
    animatedVideoKeywords: animatedVideoKeywords,
  );
}


/// 自定义后缀列表的编辑器（neoview `MediaSettingsCard.tsx:155-283` 那三档里的字符串列表档）。
///
/// 校验由调用方给：别名有「不许与图片后缀重叠」这类硬规则，关键字没有。
/// 值统一在弹窗里做过 `trim` + 小写，所以登记表与校验器看到的是同一份写法。
///
/// 原名 `_VideoListTile`：它现在同时服务视频别名、动图关键字与两张媒体格式表，
/// 留在旧名字下会让人以为「图片格式不该走这颗」。
class _StringListTile extends StatelessWidget {
  const _StringListTile({
    required this.title,
    required this.hint,
    required this.dialogHint,
    required this.values,
    required this.onChanged,
    this.validate,
  });

  final String title;
  final String hint;
  final String dialogHint;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  /// 校验器：别名有「不许与图片后缀重叠」这类硬规则，关键字没有。
  final List<String> Function(List<String>)? validate;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        title,
        style: context.theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        values.isEmpty ? t.video.aliasesEmpty : values.join('、'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: context.theme.textTheme.bodySmall?.copyWith(
          color: context.theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.edit_outlined, size: 20),
      onTap: () => _edit(context),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: values.join(', '));
    final saved = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t.video.aliasesHint),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(hintText: dialogHint),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              controller.text
                  .split(RegExp(r'[,，\s]+'))
                  .where((e) => e.trim().isNotEmpty)
                  .map((e) => e.trim().toLowerCase())
                  .toList(growable: false),
            ),
            child: Text(t.common.save),
          ),
        ],
      ),
    );
    if (saved == null) return;
    final problems = validate?.call(saved) ?? const <String>[];
    if (problems.isNotEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(problems.join('；'))));
      }
      return;
    }
    onChanged(saved);
  }
}
