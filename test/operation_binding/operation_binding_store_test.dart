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

  test('出厂表是合法绑定表：每条都有 input.device，且键盘与点击预设都在里面', () {
    final doc = OperationBindingStore.factoryBindingsJson(
      tapMode: ReaderTapPageTurnMode.rightHand,
    );
    final bindings = parseBindings(doc);

    expect(bindings, isNotNull);
    expect(bindings!.map((binding) => binding['action']), [
      'reader.page-right',
      'reader.page-right',
    ]);
    for (final binding in bindings) {
      expect((binding['input'] as Map)['device'], isNotNull,
          reason: '${binding['id']} 少了 input');
    }
    // 左右手预设选的是引擎那一侧的名字，不是 Dart 造的。
    final tapCall = api.calls
        .where(
          (call) =>
              call.memberName ==
              #crateApiOperationBindingOperationBindingTapPreset,
        )
        .first;
    expect(tapCall.namedArguments[#preset], 'right-hand');
  });

  test('leftHand 用 left-hand 预设播种；总开关关掉时运行时不查表', () {
    OperationBindingStore.factoryBindingsJson(
      tapMode: ReaderTapPageTurnMode.leftHand,
    );
    final tapCall = api.calls
        .where(
          (call) =>
              call.memberName ==
              #crateApiOperationBindingOperationBindingTapPreset,
        )
        .first;
    expect(tapCall.namedArguments[#preset], 'left-hand');

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
}
