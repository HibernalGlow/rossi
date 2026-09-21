import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/workspace/model/shelf_view_state.dart';
import 'package:zephyr/workspace/registry/workspace_ids.dart';
import 'package:zephyr/workspace/service/shelf_view_state_store.dart';

/// 书签 / 历史卡片的视图与排序**真的落到了盘上**。
///
/// 这条判据要防的是「看着记住了，其实只活在 State 里」：卡片被面板回收重建
/// （换泳道、收起再展开）或重启应用，档位与排序都会回到出厂的封面列表。
/// 落盘那份文档是**整体覆写**的，所以两张卡片各持一个实例时的互相打底
/// 也必须验 —— 少一次 `_ensureLoaded` 就会表现为「书签换了视图，历史的记忆没了」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const historyGrid = ShelfViewState(
    viewMode: 'coverGrid',
    sortField: 'time',
    sortAscending: true,
  );
  const favoriteCompact = ShelfViewState(
    viewMode: 'compact',
    sortField: 'author',
    sortAscending: false,
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('没存过的卡片读到 null（而不是默认值）', () async {
    expect(await PreferencesShelfViewStateStore().read('nope'), isNull);
  });

  test('写过的档位与排序，换一个实例（＝重启）还读得回来', () async {
    await PreferencesShelfViewStateStore().write(
      WorkspacePanelId.history,
      historyGrid,
    );
    expect(
      await PreferencesShelfViewStateStore().read(WorkspacePanelId.history),
      historyGrid,
    );
  });

  test('两张卡片各写各的，后写的不会冲掉前一条', () async {
    // 应用里两张卡片共用 `shelfViewStateStore` 那一个实例。这里故意用两个实例，
    // 是为了把「整份文档是覆写出去的」这件事钉在最差的情况下：新实例落盘前
    // 必须先把已有那份读回来打底，否则书签一换视图，历史那条就没了。
    final history = PreferencesShelfViewStateStore();
    await history.write(WorkspacePanelId.history, historyGrid);
    final favorite = PreferencesShelfViewStateStore();
    await favorite.write(WorkspacePanelId.favorite, favoriteCompact);
    expect(
      await favorite.read(WorkspacePanelId.history),
      historyGrid,
      reason: '书签落盘前没把已有文档读回来打底，历史那一条被整份覆写冲掉了',
    );
    // 盘上那一份才是最终真相：再换一个实例（＝重启）两条都还在。
    final reopened = PreferencesShelfViewStateStore();
    expect(await reopened.read(WorkspacePanelId.history), historyGrid);
    expect(await reopened.read(WorkspacePanelId.favorite), favoriteCompact);
  });

  test('偏好里是坏 JSON 时退回「没存过」而不是抛', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kShelfViewStateNamespace: '{"history": ',
    });
    expect(
      await PreferencesShelfViewStateStore().read(WorkspacePanelId.history),
      isNull,
    );
  });

  test('写坏过的键能被下一次写救回来', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kShelfViewStateNamespace: '不是 JSON',
    });
    final store = PreferencesShelfViewStateStore();
    await store.write(WorkspacePanelId.history, historyGrid);
    expect(await store.read(WorkspacePanelId.history), historyGrid);
  });
}
