// 提示网关（逐事项门禁 + 同类合并）的判据。
//
// 对照 `docs/adr/0020-in-app-notification-personalization.md` 定的三层口径。
// 刻意不起 UI、不碰 ObjectBox：渲染器是回调，设置与时间是注入进去的假件。
//
// 每条判据都配了阳性对照 —— 断言「静音了」之前先断言「同一把尺看得见它响」，
// 否则恒真的门禁（永远返回 false）也能让整组测试变绿。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/service/notify/notify_gateway.dart';
import 'package:zephyr/service/notify/notify_topic.dart';
import 'package:zephyr/widgets/toast/toast_card.dart' show ToastType;

class _Recorder {
  final List<NotifyEvent> shown = [];

  void render(NotifyEvent event) => shown.add(event);

  /// 网关的入口是 rxdart 的 `PublishSubject`，投递是异步的。
  /// 这里给它一个**不绑帧**的排空窗口：固定 pump 次数是在赌调度负载。
  Future<void> drain() => Future<void>.delayed(const Duration(milliseconds: 5));

  List<String> get texts => shown.map((event) => event.message).toList();
}

NotifyEvent _e({
  required NotifyTopic topic,
  required String message,
  String? title,
  bool userInitiated = false,
}) {
  return NotifyEvent(
    topic: topic,
    type: ToastType.info,
    title: title,
    message: message,
    userInitiated: userInitiated,
  );
}

void main() {
  // 默认出口会读 `navigatorKey.currentContext`，那要求 binding 已初始化。
  // 真机上 `main.dart:149` 在任何提示之前 `ensureInitialized()`，这里补同样前提；
  // 不给生产代码加「binding 没起来」的分支——那是框架保证不会发生的事。
  TestWidgetsFlutterBinding.ensureInitialized();
  group('逐事项门禁', () {
    test('默认全开；关掉某一项只有那一项静音（阳性对照在前半段）', () async {
      var setting = const NotifySettingState();
      final gateway = NotifyGateway(settings: () => setting);
      final rec = _Recorder();
      gateway.attach(rec.render);

      gateway.submit(
        _e(topic: NotifyTopic.downloadComplete, message: '《A》下载完成'),
      );
      gateway.submit(
        _e(topic: NotifyTopic.downloadFailed, message: '《A》下载失败：超时'),
      );
      await rec.drain();
      expect(rec.shown, hasLength(2), reason: '默认状态下两条都该响');

      rec.shown.clear();
      setting = const NotifySettingState(topics: {'download.complete': false});
      gateway.submit(
        _e(topic: NotifyTopic.downloadComplete, message: '《B》下载完成'),
      );
      gateway.submit(
        _e(topic: NotifyTopic.downloadFailed, message: '《B》下载失败：超时'),
      );
      await rec.drain();
      expect(rec.texts, ['《B》下载失败：超时']);
      gateway.detach();
    });

    test('总闸只静音后台事项，操作反馈与自管事项不受影响', () async {
      const setting = NotifySettingState(enabled: false);
      final gateway = NotifyGateway(settings: () => setting);
      final rec = _Recorder();
      gateway.attach(rec.render);

      gateway.submit(
        _e(topic: NotifyTopic.followUpdate, message: '追更检测到更新'),
      );
      gateway.submit(_e(topic: NotifyTopic.action, message: '已加入收藏'));
      gateway.submit(_e(topic: NotifyTopic.readerSwitch, message: '第 3 / 4 页'));
      await rec.drain();

      // 「点了收藏却一声不响」读起来是按钮坏了，所以关掉总闸也不该拿走它。
      expect(rec.texts, ['已加入收藏', '第 3 / 4 页']);
      gateway.detach();
    });

    test('userInitiated 是直通道：事项被关掉、总闸被关掉都照样响', () async {
      const setting = NotifySettingState(
        enabled: false,
        topics: {'sync.autoSuccess': false},
      );
      final gateway = NotifyGateway(settings: () => setting);
      final rec = _Recorder();
      gateway.attach(rec.render);

      gateway.submit(
        _e(
          topic: NotifyTopic.syncAutoSuccess,
          message: '同步完成',
          userInitiated: true,
        ),
      );
      await rec.drain();
      expect(rec.texts, ['同步完成']);
      gateway.detach();
    });
  });

  group('同类合并', () {
    test('窗口内同一条只响一次，窗口后那条带上被压掉的次数', () async {
      final start = DateTime(2026, 10, 8, 12);
      var now = start;
      final gateway = NotifyGateway(
        settings: () => const NotifySettingState(),
        clock: () => now,
      );
      final rec = _Recorder();
      gateway.attach(rec.render);

      const failure = '同步失败：connection refused';
      gateway.submit(_e(topic: NotifyTopic.syncAutoFailure, message: failure));
      await rec.drain();
      expect(rec.shown, hasLength(1));
      expect(rec.shown.single.merged, 0, reason: '第一条没有前史');

      now = start.add(const Duration(minutes: 1));
      gateway.submit(_e(topic: NotifyTopic.syncAutoFailure, message: failure));
      now = start.add(const Duration(minutes: 5));
      gateway.submit(_e(topic: NotifyTopic.syncAutoFailure, message: failure));
      await rec.drain();
      expect(rec.shown, hasLength(1), reason: '10 分钟窗口内不再敲第二次');

      now = start.add(const Duration(minutes: 10));
      gateway.submit(_e(topic: NotifyTopic.syncAutoFailure, message: failure));
      await rec.drain();
      expect(rec.shown, hasLength(2));
      expect(rec.shown.last.merged, 2);
      expect(rec.shown.last.displayMessage, '$failure（另有 2 次同类提示）');
      gateway.detach();
    });

    test('不同正文、不同事项互不合并（键里带正文是刻意的）', () async {
      final gateway = NotifyGateway(
        settings: () => const NotifySettingState(),
      );
      final rec = _Recorder();
      gateway.attach(rec.render);

      gateway.submit(
        _e(topic: NotifyTopic.downloadComplete, message: '《A》下载完成'),
      );
      gateway.submit(
        _e(topic: NotifyTopic.downloadComplete, message: '《B》下载完成'),
      );
      gateway.submit(
        _e(topic: NotifyTopic.downloadFailed, message: '《A》下载完成'),
      );
      await rec.drain();
      expect(rec.shown, hasLength(3), reason: '三件不同的事，不该压成一条');
      gateway.detach();
    });

    test('selfManaged 事项不进合并窗口（它的去重在自己服务里）', () async {
      final gateway = NotifyGateway(
        settings: () => const NotifySettingState(),
      );
      final rec = _Recorder();
      gateway.attach(rec.render);

      gateway.submit(_e(topic: NotifyTopic.readerSwitch, message: '第 3 / 4 页'));
      gateway.submit(_e(topic: NotifyTopic.readerSwitch, message: '第 3 / 4 页'));
      await rec.drain();
      expect(rec.shown, hasLength(2));
      gateway.detach();
    });
  });

  group('边界与登记表', () {
    test('空正文丢弃，不炸也不弹', () async {
      final gateway = NotifyGateway(
        settings: () => const NotifySettingState(),
      );
      final rec = _Recorder();
      gateway.attach(rec.render);

      gateway.submit(_e(topic: NotifyTopic.action, message: '   '));
      await rec.drain();
      expect(rec.shown, isEmpty);
      gateway.detach();
    });

    test('没有可用宿主时按原样丢掉，不抛异常（默认出口不要求先挂东西）', () async {
      // 出口默认就是提示条。单元测试里既没有 navigatorKey 也没有传 context，
      // 这条路必须安静地不弹，而不是炸在渲染器为 null 上。
      final gateway = NotifyGateway(
        settings: () => const NotifySettingState(),
      );
      expect(
        () => gateway.submit(
          _e(topic: NotifyTopic.action, message: '没有宿主的一条'),
        ),
        returnsNormally,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });

    test('事项登记表自洽：id 唯一、非空，且后台事项那一组不为空', () {
      final ids = NotifyTopic.values.map((topic) => topic.id).toList();
      expect(ids, equals(ids.toSet().toList()), reason: 'id 撞了会互相顶掉开关');
      expect(
        NotifyTopic.ambientTopics,
        isNotEmpty,
        reason: '全被标成 selfManaged 的话，设置页会静默变成空页',
      );
      for (final topic in NotifyTopic.ambientTopics) {
        expect(topic.id, contains('.'), reason: '后台事项统一用「域.事项」');
        expect(topic.id.trim(), equals(topic.id), reason: 'id 里不该有空白');
      }
    });

    test('逐事项覆盖写回时与默认一致就不占坑', () {
      const topic = NotifyTopic.downloadComplete;
      final withOverride = const NotifySettingState(
        topics: {'download.complete': false},
      );
      expect(topic.enabledIn(withOverride), isFalse);
      expect(topic.enabledIn(const NotifySettingState()), isTrue);
    });
  });

  group('源码哨兵', () {
    // 「一条腿有门禁、另一条裸奔」是这个功能立项的那条 bug：自动同步成功查了
    // syncNotify，失败什么门都不过，于是配错时每 5 分钟敲一次且关不掉。
    // 这里按文本量这条腿，防止同类漏法复发。剥注释 —— 注释里出现函数名不算调用。
    String autoSyncBody() {
      final source = File('lib/page/navigation_bar.dart').readAsStringSync();
      final start = source.indexOf('Future<void> _autoSync(');
      expect(start, greaterThan(0), reason: '_autoSync 改名了，这条尺要一起改');
      // 函数体的 `{` 在签名的 `) async {` 之后 —— 直接找签名后面的第一个 `{`
      // 会撞上可选参数的默认值花括号（`{bool force = false}`），量到的是参数表。
      final open = source.indexOf('{', source.indexOf('async', start));
      var depth = 0;
      var i = open;
      for (; i < source.length; i++) {
        final c = source[i];
        if (c == '{') {
          depth++;
        } else if (c == '}') {
          depth--;
          if (depth == 0) break;
        }
      }
      final body = source.substring(open, i + 1);
      return body
          .split('\n')
          .map((line) => line.replaceAll(RegExp(r'//.*$'), ''))
          .join('\n');
    }

    test('自动同步的两条腿都过网关，且不再有裸的 show*Toast', () {
      final body = autoSyncBody();
      expect(body, contains('NotifyTopic.syncAutoSuccess'));
      expect(body, contains('NotifyTopic.syncAutoFailure'));
      for (final bare in [
        'showSuccessToast(',
        'showErrorToast(',
        'showInfoToast(',
        'showWarningToast(',
      ]) {
        expect(body, isNot(contains(bare)), reason: '$bare 不过门禁，正是老 bug 的形状');
      }
    });
  });
}
