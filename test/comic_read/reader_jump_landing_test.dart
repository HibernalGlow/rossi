import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';

/// 跳页「到底落地没有」的判据。
///
/// 它存在的理由：`PageController.jumpToPage` 有几条**静默不落地**的路 ——
/// 控制器还没挂上、视口尺寸还是 0（那一下只记进 `_cachedPage`，读回来是
/// NaN/Infinity）、位置越界被物理弹回。而阅读状态在跳之前就写好了
/// （`_jumpToGlobalSlot`），不核对就会停在「状态指 X、画面在别处」，
/// 且没有任何东西会纠正它：唯一能纠正的 `onPageChanged` 只在真的换页时才来。
/// 症状就是「点进度条跳到画面已经在的那一页，没反应」。
void main() {
  test('只有真的落在目标那一位才算落地', () {
    expect(didLandOnSlot(actualPage: 7.0, targetSlot: 7), isTrue);
    // 整数容差内的浮点误差（`pixels / viewportDimension` 的往返）仍算落地。
    expect(didLandOnSlot(actualPage: 7.004, targetSlot: 7), isTrue);
  });

  test('阳性对照：同一把尺子必须看得见"差一位"这种违规', () {
    // 这两条是"如果判据恒为 true，本用例会红"的对照 —— 尺子本身要能判否。
    expect(didLandOnSlot(actualPage: 6.0, targetSlot: 7), isFalse);
    expect(didLandOnSlot(actualPage: 8.0, targetSlot: 7), isFalse);
    // 滑动中间态（还没吸附到整数）不算落地，该重试。
    expect(didLandOnSlot(actualPage: 6.6, targetSlot: 7), isFalse);
  });

  test('读不到实际页的三种静默失败都判否', () {
    // 控制器没挂上：`hasClients == false`，读回来是 null。
    expect(didLandOnSlot(actualPage: null, targetSlot: 7), isFalse);
    // 视口尺寸是 0：`getPageFromPixels` 除零。
    expect(didLandOnSlot(actualPage: double.nan, targetSlot: 7), isFalse);
    expect(didLandOnSlot(actualPage: double.infinity, targetSlot: 7), isFalse);
  });
}
