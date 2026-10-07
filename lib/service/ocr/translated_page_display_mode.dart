import 'package:shared_preferences/shared_preferences.dart';

import 'package:zephyr/reader/page_display_source.dart';

/// 这一档的存储。
///
/// `TranslatedPageDisplayChoice`（烘焙 / 叠层）**定义在 `page_display_source.dart`** ——
/// 那里是裁决用的同一份枚举，这里只负责存它。在两个文件里各声明一遍，
/// 就是「切换的是一档、裁决读的是另一档」这种错的起点。
///
/// 为什么单独一个文件、不塞进 `OcrSettings`：那是另一条在途工作正压着的文件，
/// 而这是一档独立的选择。键名跟着 `ocr_` 前缀走，分家的是文件不是命名空间。
class TranslatedPageDisplayMode {
  TranslatedPageDisplayMode._();

  static const _keyChoice = 'ocr_display_choice';

  /// 默认**烘焙**。这不是保守，是判据：叠层要求「擦干净的底图」已经落盘
  /// （`TranslatedPageCache.overlayReady`），而渲染台实测把译文叠在没擦字的原图上
  /// 字压字率 0.085 —— 前提不成立时默认走叠层就是默认端出一张中日文叠在一起的页。
  /// 前提一到位，这一行的默认值就该改，且改的时候要说得出那条实测。
  static const defaultChoice = TranslatedPageDisplayChoice.baked;

  static Future<TranslatedPageDisplayChoice> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyChoice);
    return TranslatedPageDisplayChoice.values.firstWhere(
      (c) => c.name == stored,
      orElse: () => defaultChoice,
    );
  }

  static Future<void> save(TranslatedPageDisplayChoice choice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyChoice, choice.name);
  }
}
