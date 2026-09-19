// 「切换提示」模板引擎判据 —— 用例从上游
// `packages/nodes/neoview/src/application/switch-toast/ReaderSwitchToast.test.ts`
// 的 `[neoview.switch-toast.template]` 组**逐条对照**翻过来（T3 的验收方式）。
//
// 单独成文件的原因：模板引擎零依赖（连 zephyr 都不 import），于是这一组判据
// 不受应用树的编译状态牵连；服务与卡片的判据在 `switch_toast_test.dart`。
//
// ⚠ 刻意偏离（登记于 docs/ROADMAP.md）：上游 `{{book.emmTags.artist.0}}`
// 这类「对象/数组再下钻」在 Rossi 没有对应变量（变量表全是标量），
// 对照语义统一为「取不到 → 空串」。

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/util/toast/switch_toast_template.dart';

const SwitchToastContext _demoContext = SwitchToastContext(
  book: {
    'name': 'demo.cbz',
    'displayName': 'Demo',
    'path': 'D:/Books/demo.cbz',
    'type': 'CBZ',
    'totalPages': 12,
    'currentPageIndex': 2,
    'currentPageDisplay': 3,
    'progressPercent': 25.0,
  },
  page: {
    'name': '003.jpg',
    'displayName': '003.jpg',
    'path': '003.jpg',
    'index': 2,
    'indexDisplay': 3,
  },
);

void main() {
  group('模板引擎（对照 neoview.switch-toast.template）', () {
    test('已知变量渲染，未识别的根原样保留', () {
      expect(
        renderSwitchToastTemplate(
          '{{ book.displayName }} {{page.name}} {{other.value}}',
          _demoContext,
        ),
        'Demo 003.jpg {{other.value}}',
      );
    });

    test('取不到的键渲染为空串', () {
      expect(
        renderSwitchToastTemplate(
          '{{book.missing}}/{{page.width}}',
          _demoContext,
        ),
        '/',
      );
    });

    test('page 上下文缺失时整页变量为空串', () {
      expect(
        renderSwitchToastTemplate(
          '{{book.displayName}}|{{page.name}}',
          const SwitchToastContext(book: {'displayName': 'Demo'}),
        ),
        'Demo|',
      );
    });

    test('空模板渲染为空串', () {
      expect(renderSwitchToastTemplate('', _demoContext), '');
    });

    test('嵌套对象走 JSON 序列化（上游 JSON.stringify 同款兜底）', () {
      expect(
        renderSwitchToastTemplate(
          '{{book.emmTags}}',
          const SwitchToastContext(
            book: {
              'emmTags': {'artist': ['A']},
            },
          ),
        ),
        '{"artist":["A"]}',
      );
    });

    test('出厂默认模板可完整渲染（默认设置不是空壳）', () {
      // 默认值定义在 global_setting.dart；这里只用等价的字面模板复演渲染结果，
      // 保证「默认模板 → 期望文案」这条链在纯判据里也验到。
      expect(
        renderSwitchToastTemplate(
          '已切换到 {{book.displayName}}（第 {{book.currentPageDisplay}} / {{book.totalPages}} 页）',
          _demoContext,
        ),
        '已切换到 Demo（第 3 / 12 页）',
      );
      expect(
        renderSwitchToastTemplate(
          '第 {{page.indexDisplay}} / {{book.totalPages}} 页',
          _demoContext,
        ),
        '第 3 / 12 页',
      );
      expect(
        renderSwitchToastTemplate('{{page.name}}', _demoContext),
        '003.jpg',
      );
    });
  });
}
