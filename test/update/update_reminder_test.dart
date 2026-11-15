import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/service/update/check_update.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('默认不在静默期', () async {
    expect(await isUpdateReminderSnoozed(), isFalse);
  });

  test('设置后进入静默期', () async {
    expect(await snoozeUpdateReminderForWeek(), isTrue);
    expect(await isUpdateReminderSnoozed(), isTrue);
  });

  test('静默截止时间为 7 天后', () async {
    final lower =
        DateTime.now().add(updateSnoozeDuration).millisecondsSinceEpoch - 1000;
    expect(await snoozeUpdateReminderForWeek(), isTrue);
    final upper =
        DateTime.now().add(updateSnoozeDuration).millisecondsSinceEpoch + 1000;

    final prefs = await SharedPreferences.getInstance();
    final untilMs = prefs.getInt(updateSnoozeUntilPrefsKey);
    expect(untilMs, isNotNull);
    expect(untilMs!, inInclusiveRange(lower, upper));
  });

  test('静默期过期后恢复提醒', () async {
    SharedPreferences.setMockInitialValues({
      updateSnoozeUntilPrefsKey: DateTime.now()
          .subtract(const Duration(seconds: 1))
          .millisecondsSinceEpoch,
    });
    expect(await isUpdateReminderSnoozed(), isFalse);
  });

  test('静默期未过期时保持静默', () async {
    SharedPreferences.setMockInitialValues({
      updateSnoozeUntilPrefsKey: DateTime.now()
          .add(const Duration(days: 6))
          .millisecondsSinceEpoch,
    });
    expect(await isUpdateReminderSnoozed(), isTrue);
  });

  test('打开更新日志后记录已读版本', () async {
    expect(await isChangelogSeen('v1.2.3'), isFalse);

    await markChangelogSeen('v1.2.3');

    expect(await isChangelogSeen('v1.2.3'), isTrue);
    // 新版本仍需重新提示
    expect(await isChangelogSeen('v1.2.4'), isFalse);
  });

  test('没有待提示的更新时打开日志不写入已读版本', () async {
    await markChangelogSeen();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(changelogSeenVersionPrefsKey), isNull);
  });
}
