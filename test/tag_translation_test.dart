import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/util/text/tag_text.dart';
import 'package:zephyr/util/text/tag_translation.dart';

/// 随包的 `asset/tag_translation/etht.json.gz` 必须**真的能解、真的含常用词**：
/// 生成脚本换数据源、或产物被误清空时，这条判据要红，而不是让线上静默退回
/// 「只有登记别名」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('随包字典可加载且双向可查（footjob↔足交、lolicon→萝莉）', () async {
    await TagTranslation.ensureLoaded();
    expect(TagTranslation.isReady, isTrue);

    expect(
      TagTranslation.expansionsNormalized(TagText.normalize('footjob')),
      contains(TagText.normalize('足交')),
    );
    expect(
      TagTranslation.expansionsNormalized(TagText.normalize('足交')),
      contains(TagText.normalize('footjob')),
    );
    expect(
      TagTranslation.expansionsNormalized(TagText.normalize('lolicon')),
      contains(TagText.normalize('萝莉')),
    );
  });

  test('ensureLoaded 重复调用不重复解析', () async {
    await TagTranslation.ensureLoaded();
    final before = TagTranslation.isReady;
    await TagTranslation.ensureLoaded();
    expect(TagTranslation.isReady, before);
  });
}
