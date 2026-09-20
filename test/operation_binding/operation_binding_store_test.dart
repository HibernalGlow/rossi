import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/service/operation_binding/binding_doc.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

/// 跨 FRB 那一层的判据（用 `RustLib.initMock` 顶掉原生库，测的是**转发**本身）。
///
/// 盯的是一条真机踩过的红屏：注册表的行是 `{id,label,category,…}`，**没有** `input`；
/// 而绑定表那条校验恰恰要求每条都有 `input.device`。清单一旦走了绑定表的解码器，
/// 「打开操作绑定设置页」= 「Bad state: 引擎返回的绑定表读不出来」+ 整屏红。
/// 这类「两个形状都像 JSON 数组、校验规则却不同」的错，只有把边界本身钉住才拦得住。
class _FakeApi implements RustLibApi {
  final calls = <Invocation>[];
  String? upgraded;

  static const catalogJson =
      '[{"id":"reader.next-page","label":"下一页","category":"navigation",'
      '"categoryLabel":"导航","implemented":true},'
      '{"id":"reader.zoom-in","label":"放大","category":"zoom",'
      '"categoryLabel":"缩放","implemented":false},'
      '{"id":"radial.open-default","label":"打开轮盘菜单","category":"radial",'
      '"categoryLabel":"轮盘","implemented":true}]';

  static const keyPresetJson =
      '[{"id":"preset-key-0-ArrowRight","action":"reader.page-right",'
      '"context":"reader","enabled":true,"input":{"device":"keyboard",'
      '"code":"ArrowRight","trigger":"down","ctrl":false,"alt":false,'
      '"shift":false,"meta":false}}]';

  static const tapPresetJson =
      '[{"id":"preset-tap-advance","action":"reader.page-right",'
      '"context":"reader","enabled":true,"input":{"device":"area",'
      '"area":"middle-right","button":0,"action":"click"}}]';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    switch (invocation.memberName) {
      case #crateApiOperationBindingOperationBindingActionCatalog:
        return catalogJson;
      case #crateApiOperationBindingOperationBindingKeyPreset:
        return keyPresetJson;
      case #crateApiOperationBindingOperationBindingFactoryPreset:
        return keyPresetJson;
      case #crateApiOperationBindingOperationBindingUpgradeDefaults:
        return upgraded;
      case #crateApiOperationBindingOperationBindingTapPreset:
        return tapPresetJson;
      case #crateApiOperationBindingOperationBindingRadialPreset:
        return '[]';
      case #crateApiOperationBindingOperationBindingRadialDefaultConfig:
        return '{"menus":[],"enabled":true}';
      case #crateApiOperationBindingOperationBindingValidate:
        return true;
      case #crateApiOperationBindingOperationBindingConflicts:
        return '[]';
    }
    throw UnsupportedError('这个引擎调用没被替身覆盖：${invocation.memberName}');
  }
}

class _MemorySettings extends GlobalSettingCubit {
  _MemorySettings(OperationBindingSettingState settings) {
    emit(state.copyWith(operationBindingSetting: settings));
  }

  int saves = 0;
  @override
  void updateOperationBindingSetting(
    OperationBindingSettingState Function(OperationBindingSettingState) update,
  ) {
    saves++;
    emit(
      state.copyWith(
        operationBindingSetting: update(state.operationBindingSetting),
      ),
    );
  }
}

void main() {
  late _FakeApi api;

  setUp(() {
    api = _FakeApi();
    RustLib.initMock(api: api);
  });
  // FRB 2.12 的 `dispose()` 不清 `_EntrypointState`，只 dispose 会让第二个用例撞
  // 「Should not initialize flutter_rust_bridge twice」，于是整个文件只有第一条能跑。
  tearDown(() {
    RustLib.dispose();
    // ignore: invalid_use_of_internal_member
    RustLib.instance.resetState();
  });

  test('注册表清单读得出来（它的行没有 input，不许走绑定表的校验）', () {
    final catalog = OperationBindingStore.actionCatalog();

    expect(catalog, hasLength(3));
    expect(catalog.map((entry) => entry.id), [
      'reader.next-page',
      'reader.zoom-in',
      'radial.open-default',
    ]);
    // 置灰的依据也来自同一份数据，UI 不另立名单。
    expect(catalog[1].implemented, isFalse);
    expect(catalog[1].category, 'zoom');
    expect(catalog[1].categoryLabel, '缩放');
  });

  test('默认表直接使用核心的 Neo 完整预设，不叠加旧三分区', () {
    final doc = OperationBindingStore.factoryBindingsJson();
    final bindings = parseBindings(doc);

    expect(bindings, isNotNull);
    expect(bindings!.map((binding) => binding['action']), [
      'reader.page-right',
    ]);
    for (final binding in bindings) {
      expect(
        (binding['input'] as Map)['device'],
        isNotNull,
        reason: '${binding['id']} 少了 input',
      );
    }
    expect(api.calls.map((call) => call.memberName), [
      #crateApiOperationBindingOperationBindingFactoryPreset,
    ]);
  });

  test('总开关关掉或未播种时运行时不查表', () {
    final seeded = OperationBindingSettingState(
      bindingsJson: OperationBindingStore.factoryBindingsJson(),
    );
    expect(OperationBindingStore.runtimeBindingsJson(seeded), isNotNull);
    expect(
      OperationBindingStore.runtimeBindingsJson(
        seeded.copyWith(bindingsRuntime: false),
      ),
      isNull,
      reason: '关掉开关就该回退到改造前的硬编码分区',
    );
    expect(
      OperationBindingStore.runtimeBindingsJson(
        const OperationBindingSettingState(),
      ),
      isNull,
      reason: '还没播种（空表）同样回退，而不是什么都不做',
    );
  });

  test('首次播种默认表；已存在的轮盘文档及运行时开关保留', () async {
    const radial = '{"enabled":false,"activeMenuId":"custom","menus":[]}';
    final cubit = _MemorySettings(
      const OperationBindingSettingState(
        bindingsRuntime: false,
        radialJson: radial,
      ),
    );
    addTearDown(cubit.close);
    OperationBindingStore.seedIfNeeded(cubit);
    expect(cubit.saves, 1);
    expect(
      parseBindings(cubit.state.operationBindingSetting.bindingsJson),
      parseBindings(_FakeApi.keyPresetJson),
    );
    expect(cubit.state.operationBindingSetting.radialJson, radial);
    expect(cubit.state.operationBindingSetting.bindingsRuntime, false);
    OperationBindingStore.seedIfNeeded(cubit);
    expect(cubit.saves, 1);
  });

  test('旧默认配置升级落盘；核心判为自定义时逐字保留', () {
    const radial = '{"enabled":true,"menus":[]}';
    final cubit = _MemorySettings(
      const OperationBindingSettingState(
        bindingsJson: _FakeApi.tapPresetJson,
        radialJson: radial,
      ),
    );
    addTearDown(cubit.close);
    OperationBindingStore.seedIfNeeded(cubit);
    expect(cubit.saves, 0);
    expect(
      cubit.state.operationBindingSetting.bindingsJson,
      _FakeApi.tapPresetJson,
    );
    api.upgraded = _FakeApi.keyPresetJson;
    OperationBindingStore.seedIfNeeded(cubit);
    expect(cubit.saves, 1);
    expect(
      parseBindings(cubit.state.operationBindingSetting.bindingsJson),
      parseBindings(_FakeApi.keyPresetJson),
    );
    expect(cubit.state.operationBindingSetting.radialJson, radial);
  });

  test('用户主动清空的绑定表不重新播种', () {
    final cubit = _MemorySettings(
      const OperationBindingSettingState(
        bindingsJson: '{"bindings":[]}',
        radialJson: '{"enabled":true,"menus":[]}',
      ),
    );
    addTearDown(cubit.close);
    OperationBindingStore.seedIfNeeded(cubit);
    expect(cubit.saves, 0);
    expect(cubit.state.operationBindingSetting.bindingsJson, '{"bindings":[]}');
  });
}
