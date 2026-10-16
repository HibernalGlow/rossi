import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_list/cubit/plugin_paged_comic_list_state.dart';

import 'plugin_list_fixture.dart';

void main() {
  test('直跳只请求目标页，后续连续加载且可由条目得到真实页码', () async {
    final requests = <int>[];
    final list = cubit((page) async {
      requests.add(page);
      return response(page);
    });
    addTearDown(list.close);
    await list.jumpToPage(50);
    expect(requests, [50]);
    expect(list.state.list.first.id, '50-0');
    expect(list.pageForIndex(2), 50);
    await list.loadMore();
    expect(requests, [50, 51]);
    expect(list.pageForIndex(2), 50);
    expect(list.pageForIndex(3), 51);
  });

  test('跳页后迟到的加载更多响应不会污染目标页', () async {
    final old = Completer<Map<String, dynamic>>();
    final list = cubit(
      (page) => page == 2 ? old.future : Future.value(response(page)),
    );
    addTearDown(list.close);
    await list.loadInitial();
    final pending = list.loadMore();
    await list.jumpToPage(40);
    old.complete(response(2));
    await pending;
    expect(list.state.page, 40);
    expect(list.state.list.map((item) => item.id), ['40-0', '40-1', '40-2']);
    expect(list.state.status, PluginPagedComicListStatus.success);
  });

  test('已知末页禁止越界和重复拉取；初始化期间不并行加载更多', () async {
    final first = Completer<Map<String, dynamic>>();
    final requests = <int>[];
    final list = cubit((page) {
      requests.add(page);
      return first.future;
    });
    addTearDown(list.close);
    final pending = list.loadInitial();
    await list.loadMore();
    expect(requests, [1]);
    first.complete(response(1, total: 1));
    await pending;
    await list.loadMore();
    await list.jumpToPage(2);
    await list.jumpToPage(0);
    expect(requests, [1]);
    expect(list.totalPages, 1);
    expect(list.state.hasReachedMax, isTrue);
  });

  test('跳页失败后可以直接重试目标页', () async {
    var fail = true;
    final list = cubit((page) async {
      if (fail) throw StateError('offline');
      return response(page);
    });
    addTearDown(list.close);
    await list.jumpToPage(12);
    expect(list.state.status, PluginPagedComicListStatus.failure);
    expect(list.state.page, 12);
    fail = false;
    await list.jumpToPage(12);
    expect(list.state.list.first.id, '12-0');
  });
}
