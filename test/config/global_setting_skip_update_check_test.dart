import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';

/// fork 构建的「跳过更新检查」默认值。
///
/// 判的是**默认值本身**：本仓版本号（0.1.x）永远低于上游（3.x），启动时那次
/// `checkUpdate()` 只会把用户引向 deretame/Breeze 的安装包。默认值一旦被改回
/// false，已经装好的用户不会收到任何提示 —— 弹窗会照旧每次启动都出现。
void main() {
  test('出厂值跳过；老数据里没有这个键时也跳过', () {
    expect(const GlobalSettingState().skipUpdateCheck, isTrue);

    // 老版本的 globalSettingData 里没有 skipUpdateCheck，走的是 `?? 默认值`
    // 这条兜底 —— 升级后不该又弹一次上游更新。
    final restored = GlobalSettingState.fromJson(const <String, dynamic>{});
    expect(restored.skipUpdateCheck, isTrue);
  });

  test('手动关掉开关后能原样往返（导出 / 设置同步走的就是这条路）', () {
    final json = const GlobalSettingState()
        .copyWith(skipUpdateCheck: false)
        .toJson();

    expect(json['skipUpdateCheck'], isFalse);
    expect(GlobalSettingState.fromJson(json).skipUpdateCheck, isFalse);
  });
}
