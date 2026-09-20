import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_info/action/comic_info_action_entry.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

/// 「详情页那一族」的过桥判据（车道 B，见 `docs/comic-info-action-rail.md` §7.5）。
///
/// 为什么要有这一条、而不是只测纯 Dart：注册表的权威在 Rust，Dart 只负责转发与解码。
/// 中间那一段（`operationBindingActionCatalog()` 返回 JSON 串 → `_decodeList` →
/// `BindingActionInfo`）一旦形状变了 —— 比如哪天给 catalog 加了 `input` 字段，于是
/// 走进了绑定表那条「每条都要有 input.device」的校验 —— 症状是「打开操作绑定设置页
/// 就 Bad state 红屏」，而纯 Dart 的 mock 测不出来：mock 里那份 catalogJson 是人写的，
/// 和真库永远可能不同步。
///
/// 顺带这一条也是「仓库里那份 `rust/target/release/libwindcore.dylib` 还新不新」的
/// 守门人（同 `test/video/waveform_bridge_probe_test.dart` 的理由：hash 对不上时
/// 表现像「原生库在测试里不可用」，实际只是产物过期）。
void main() {
  var nativeReady = false;
  String? nativeError;

  setUpAll(() async {
    try {
      await RustLib.init();
      nativeReady = true;
    } catch (e) {
      nativeError = '$e';
    }
  });

  /// 与 Rust `ACTION_CATALOG` 里 comic-info 那一族**逐字、逐序**对齐。
  ///
  /// 写死是刻意的：这些 id 要落进用户自己排的 rail 配置（车道 D 存的就是这串 id），
  /// 改名等于把用户已存的那份配置读成「不认识的条目」，所以必须让改一次名红一次。
  const expectedIds = [
    'comic-info.back',
    'comic-info.home',
    'comic-info.read',
    'comic-info.collect',
    'comic-info.follow',
    'comic-info.like',
    'comic-info.comments',
    'comic-info.download',
    'comic-info.download-chapters',
    'comic-info.copy-magnet',
    'comic-info.toggle-chapter-order',
    'comic-info.export',
    'comic-info.more',
  ];

  /// 原生库加载不了时**跳过而不是留红**（这台机器之外还有人跑测试，产物新旧不一律
  /// 让别人的跑法整体变红没有意义），但理由要打印出来 —— hash 不符是真问题。
  bool skipIfNoNative() {
    if (nativeReady) return false;
    markTestSkipped('原生库加载不了（$nativeError）');
    return true;
  }

  test('comic-info 一族过桥读得出，implemented 只翻已端到端可达的那几条', () {
    if (skipIfNoNative()) return;
    final family = OperationBindingStore.actionCatalog()
        .where((e) => e.category == OperationBindingStore.comicInfoCategory)
        .toList();

    expect(family.map((e) => e.id).toList(), expectedIds);
    // 判据是「rail 上真画得出来、用户按得到」，不是「Rust 里有这条」。C-2 每接一条
    // 就往这里加一个 id，同时 Rust 侧那条断言也要加（两处一起改，谁漏了谁红）。
    expect(family.where((e) => e.implemented).map((e) => e.id).toList(), [
      ComicInfoActionIds.back,
      ComicInfoActionIds.home,
      ComicInfoActionIds.read,
    ]);
    expect(family.every((e) => e.label.isNotEmpty), isTrue);
    expect(family.every((e) => e.categoryLabel.isNotEmpty), isTrue);
  });

  test('阅读器绑定表整族看不到这些，别的都还在', () {
    if (skipIfNoNative()) return;
    final catalog = OperationBindingStore.actionCatalog();
    final bindable = OperationBindingStore.readerBindableCatalog();

    expect(
      bindable.any(
        (e) => e.category == OperationBindingStore.comicInfoCategory,
      ),
      isFalse,
      reason: '这一族的执行端在详情页，混进阅读器就是一排绑得上、按不动的键',
    );
    expect(bindable.length, catalog.length - expectedIds.length);
    // 阅读器那几条必须还在（排除不能排过头）。
    expect(
      bindable.map((e) => e.id),
      containsAll(<String>[
        'reader.next-page',
        'reader.page-right',
        'radial.open-default',
      ]),
    );
  });

  test('过滤键这个字符串两侧一致', () {
    if (skipIfNoNative()) return;
    // Dart 常量与 Rust `ActionCategory::ComicInfo::as_str()` 必须同一个值：
    // 它是 readerBindableCatalog 的判据，分叉了就等于「整族没挡住」。
    expect(OperationBindingStore.comicInfoCategory, 'comic-info');
    expect(
      OperationBindingStore.actionCatalog().any(
        (e) => e.category == OperationBindingStore.comicInfoCategory,
      ),
      isTrue,
    );
  });
}
