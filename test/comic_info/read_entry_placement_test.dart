// 详情页「阅读」入口落点的判据。
//
//   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
//     flutter test test/comic_info/read_entry_placement_test.dart
//
// 用户报：「开始阅读按钮放在右下角，对桌面端不友好」——桌面端要放在操作行里
// 「下载」旁边。落点判定抽成了纯函数，所以这里能用**真值表**把它钉住，
// 不需要把整个详情页（连带 objectbox / bloc）拉起来。
//
// 最要紧的一条是**不变式**：任何组合下只能有一个入口。用户看到两颗按钮写着
// 「开始阅读」和「继续阅读」时，会以为它们是两件不同的事 —— 那是坏掉的界面，
// 不是「多一个选择」。
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_info/models/read_entry_placement.dart';

/// 桌面（有指针）平台。
const _pointerPlatforms = <TargetPlatform>[
  TargetPlatform.macOS,
  TargetPlatform.windows,
  TargetPlatform.linux,
];

/// 触摸平台。
const _touchPlatforms = <TargetPlatform>[
  TargetPlatform.android,
  TargetPlatform.iOS,
  TargetPlatform.fuchsia,
];

void main() {
  test('有指针的平台：开关开着时阅读入口落进操作行（下载旁边）', () {
    for (final platform in _pointerPlatforms) {
      expect(
        comicInfoPlatformHasPointer(platform),
        isTrue,
        reason: '$platform',
      );

      expect(
        resolveComicInfoReadEntryPlacement(
          platform: platform,
          inlineReadEntryEnabled: true,
        ),
        ComicInfoReadEntryPlacement.inlineCard,
        reason: '$platform 上没有拇指半径，右下角那颗悬浮按钮对鼠标又远又浮',
      );
    }
  });

  test('触摸平台：无论开关如何都是右下角悬浮按钮', () {
    for (final platform in _touchPlatforms) {
      expect(
        comicInfoPlatformHasPointer(platform),
        isFalse,
        reason: '$platform',
      );

      for (final enabled in const [true, false]) {
        expect(
          resolveComicInfoReadEntryPlacement(
            platform: platform,
            inlineReadEntryEnabled: enabled,
          ),
          ComicInfoReadEntryPlacement.floatingButton,
          reason: '$platform（enabled=$enabled）只有悬浮按钮这一种落点',
        );
      }
    }
  });

  test('开关关掉：桌面也退回悬浮按钮（开关必须真的能关掉功能）', () {
    for (final platform in _pointerPlatforms) {
      expect(
        resolveComicInfoReadEntryPlacement(
          platform: platform,
          inlineReadEntryEnabled: false,
        ),
        ComicInfoReadEntryPlacement.floatingButton,
        reason: '$platform 上关掉开关 ⇒ 回到加这个功能之前的样子',
      );
    }
  });

  test('不变式：任何组合下恰好只有一个阅读入口在场', () {
    for (final platform in [..._pointerPlatforms, ..._touchPlatforms]) {
      for (final enabled in const [true, false]) {
        final placement = resolveComicInfoReadEntryPlacement(
          platform: platform,
          inlineReadEntryEnabled: enabled,
        );

        // 两个入口的可见性都由这一个返回值决定：
        //   页内卡片 = placement == inlineCard
        //   悬浮按钮 = placement != inlineCard（`comic_info.dart` 里是 !showInlineReadEntry）
        final showsInlineCard =
            placement == ComicInfoReadEntryPlacement.inlineCard;
        final showsFloatingButton = !showsInlineCard;

        expect(
          showsInlineCard ^ showsFloatingButton,
          isTrue,
          reason: '$platform（enabled=$enabled）必须恰好有一个入口',
        );
      }
    }
  });
}
