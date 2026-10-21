/// 「受限来源」的判定口径。
///
/// 插件没有统一的分类字段，所以按三路取并集，任一命中即视为受限来源：
/// 1. 云端 manifest 显式声明 `breeze-plugin-restricted: true`（插件作者可自行
///    标注，不必等宿主更新）；
/// 2. UUID 命中 [restrictedUuids]（内置源与云端已收录的站点）；
/// 3. 名称 / 描述 / 仓库名命中 [_keywords]（兜底，覆盖名单尚未收录的新条目）。
///
/// 这是**展示层**过滤：关掉开关只影响来源列表、搜索与插件商店，不会卸载任何
/// 已安装插件，也不改变已有数据的读取。名单与关键词都收在这里，新增站点只改一处。
library;

class SourceVisibilityPolicy {
  const SourceVisibilityPolicy._();

  /// 已知受限来源的 UUID（小写、带连字符）。
  ///
  /// 前两条与 `rust/src/qjs/mod.rs` 的 `BIKA_PLUGIN_UUID` / `JM_PLUGIN_UUID`
  /// 一一对应，改那边必须同步改这里。
  static const Set<String> restrictedUuids = {
    // Bika（内置）
    '0a0e5858-a467-4702-994a-79e608a4589d',
    // JM（内置）
    'bf99008d-010b-4f17-ac7c-61a9b57dc3d9',
    // 禁漫天堂（第三方分支）
    '6886291b-f524-441c-844b-c2efae9899a9',
    // e-hentai
    'dba2a6cf-c495-4416-accf-c29263ab4016',
    // hitomi
    'c8f3a1e2-7b4d-4e9a-8f2c-1d5a7b9e3f6a8',
    // nhentai
    '416598d0-84d0-4de9-8ec5-e74816e768f2',
    // 绅士漫画
    '7166a5fc-b66c-4146-8c40-0f999b592a0a',
    // NoyAcg
    'babe7021-2df8-4abc-bba8-00bbfd7a0f75',
  };

  /// 内置源（编译进二进制，不走插件商店）的 UUID。
  ///
  /// 与 [restrictedUuids] 有交集：内置源里属于受限范围的那两条，开关关闭时
  /// 同样从来源列表里隐去。
  static const Set<String> builtinUuids = {
    '0a0e5858-a467-4702-994a-79e608a4589d',
    'bf99008d-010b-4f17-ac7c-61a9b57dc3d9',
  };

  /// 关键词兜底。
  ///
  /// 刻意不收 `jm` / `bika` 这类短词：单独两三个字母会在无关仓库名里误伤；
  /// 仓库名里的 `JmComic` / `bikaComic` 走下面的完整写法即可命中。
  static const List<String> _keywords = [
    '禁漫',
    '哔咔',
    '绅士',
    'jmcomic',
    'bikacomic',
    'nhentai',
    'e-hentai',
    'ehentai',
    'hitomi',
    'noyacg',
    '18comic',
    'r18',
  ];

  /// [declaredRestricted] 来自云端 manifest 的 `breeze-plugin-restricted`。
  /// 显式声明优先于另外两路：作者说自己是受限来源，就按受限来源处理。
  static bool isRestricted({
    required String uuid,
    String name = '',
    String describe = '',
    String repo = '',
    bool declaredRestricted = false,
  }) {
    if (declaredRestricted) return true;
    if (restrictedUuids.contains(uuid.trim().toLowerCase())) return true;
    final haystack = [
      name.toLowerCase(),
      describe.toLowerCase(),
      repo.toLowerCase(),
    ].join('\n');
    return _keywords.any(haystack.contains);
  }
}
