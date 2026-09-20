// 插件名缩写 / 标签拼接 / 生成图标色相 的**纯 Dart** 判据。
//
//   dart run test/discover/plugin_display_label_check.dart
//
// 为什么值得单独立一份：缩写规则是**用户看得见**的那截字，改一个字符就会
// 影响所有插件的标签；而它错的方式是「看着怪」，不是抛异常。
// 判据里把三条分支各钉一颗，顺便钉住「同种子同色相」这条 —— 它是
// 「同一个插件在任何地方都是同一个颜色」的唯一保证。
//
// ignore_for_file: avoid_print
import 'package:zephyr/page/discover/service/plugin_display_label.dart';

int _passed = 0;

void check(String label, bool condition, [String? detail]) {
  if (!condition) {
    throw StateError('FAIL: $label${detail == null ? '' : ' — $detail'}');
  }
  _passed++;
}

void main() {
  _shortName();
  _joinLabel();
  _disambiguate();
  _hue();
  print('OK: plugin_display_label 通过 $_passed 项');
}

void _shortName() {
  // 表意文字开头：前两字。
  check('绅士漫画 → 绅士', pluginShortName('绅士漫画') == '绅士');
  check('禁漫 只有两字就取两字', pluginShortName('禁漫') == '禁漫');
  check('前后空白不参与', pluginShortName('  绅士漫画  ') == '绅士');

  // 拉丁 + 首段很短 + 还有后段：取前两段首字母。
  check('e-hentai → eh', pluginShortName('e-hentai') == 'eh');
  check('e/hentai 的分隔符等价', pluginShortName('e/hentai') == 'eh');

  // 其余拉丁：首段前三字符。
  check('BikaACG → Bik', pluginShortName('BikaACG') == 'Bik');
  check('JM漫画 按首段截三位', pluginShortName('JM漫画') == 'JM漫');
  check('Bika 不足三位就整段', pluginShortName('Bika') == 'Bik');
  check(
    'EHentai 取首段前三字符',
    pluginShortName('EHentai') == 'EHe',
    pluginShortName('EHentai'),
  );

  // 空与纯分隔符：返回空串，调用方据此不画这一段。
  check('空名 → 空串', pluginShortName('') == '');
  check('只有空白 → 空串', pluginShortName('   ') == '');
  check('只有分隔符 → 空串', pluginShortName('-· ') == '');

  // 代理对不能被劈开（劈开会留下一个孤立代理项，渲染成豆腐块）。
  final emoji = pluginShortName('😀😀😀😀');
  check(
    'emoji 按码点取',
    emoji.runes.length == 3 && !emoji.runes.any(_isLoneSurrogate),
    emoji,
  );
}

bool _isLoneSurrogate(int rune) => (rune >= 0xd800 && rune <= 0xdfff);

void _joinLabel() {
  check('有缩写时用 · 连', joinTabLabel(shortName: '绅士', label: '排行') == '绅士 · 排行');
  check('缩写为空时只剩标签', joinTabLabel(shortName: '', label: '排行') == '排行');
  check('缩写为 null 时只剩标签', joinTabLabel(shortName: null, label: '排行') == '排行');
  check('缩写只有空白视同空', joinTabLabel(shortName: '  ', label: '设置') == '设置');
}

void _disambiguate() {
  check(
    '不重名就不加序号',
    disambiguateLabel(label: '排行', existingLabels: ['最新']) == '排行',
  );
  check(
    '重名才加 2',
    disambiguateLabel(label: '搜索', existingLabels: ['搜索']) == '搜索 2',
  );
  check(
    '2 也被占了就加 3',
    disambiguateLabel(label: '搜索', existingLabels: ['搜索', '搜索 2']) == '搜索 3',
  );
  check(
    '中间断号不回填（保持已开的标签字不变）',
    disambiguateLabel(label: '搜索', existingLabels: ['搜索', '搜索 3']) == '搜索 2',
  );
  check(
    '空列表原样返回',
    disambiguateLabel(label: '搜索', existingLabels: const []) == '搜索',
  );
}

void _hue() {
  check('同种子同色相', hueOfSeed('plugin-a') == hueOfSeed('plugin-a'));
  check('不同种子多半不同色相', hueOfSeed('plugin-a') != hueOfSeed('plugin-b'));
  for (final seed in ['', 'a', '绅士漫画', 'e-hentai', 'x' * 200]) {
    final hue = hueOfSeed(seed);
    check('色相落在 [0,360)：$seed', hue >= 0 && hue < 360, '$hue');
  }
}
