import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/discover/service/plugin_display_label.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/widgets/image_sleep.dart';
import 'package:zephyr/widgets/picture_bloc/picture_bloc.dart';

/// 发现页和插件商店共用的图标，按 URL 缓存，不依赖插件是否已安装。
class PluginIcon extends StatelessWidget {
  const PluginIcon({super.key, required this.url, required this.placeholder});

  final String url;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    final iconUrl = url.trim();
    if (iconUrl.isEmpty) return placeholder;

    final pictureInfo = PictureInfo(
      from: 'plugin_icons',
      url: iconUrl,
      path: sha256.convert(utf8.encode(iconUrl)).toString(),
      pictureType: PictureType.avatar,
    );

    return BlocProvider(
      key: ValueKey(iconUrl),
      create: (_) =>
          PictureBloc()..add(GetPicture(pictureInfo, usePlugin: false)),
      child: BlocBuilder<PictureBloc, PictureLoadState>(
        builder: (context, state) {
          switch (state.status) {
            case PictureLoadStatus.initial:
            case PictureLoadStatus.failure:
              return placeholder;
            case PictureLoadStatus.success:
              return ImageSleep(
                child: Image.file(
                  File(state.imagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => placeholder,
                ),
              );
          }
        },
      ),
    );
  }
}

/// 插件**没给图标**时按名字生成的 MD3 Expressive 语义容器徽标。
///
/// 不再使用任意色相旋转产生高饱和荧光绿/黄（在暗色主题下与浅色文字发生撞色导致不可读），
/// 而是由 [hueOfSeed] 在当前主题的 `primaryContainer`、`secondaryContainer`、
/// `tertiaryContainer` 三组 M3 语义容器对之间连续插值：
/// - 同一插件种子在所有位置保持稳定配色；
/// - 颜色完全收敛在全局 MD3E 调色板内，随动态取色、种子色与明暗模式实时联动；
/// - 底色与前景色始终处于同一语义容器对比档，深浅模式下均具备高对比度可读性。
class GeneratedPluginIcon extends StatelessWidget {
  const GeneratedPluginIcon({
    super.key,
    required this.seed,
    required this.name,
  });

  /// 色相的种子 —— 用插件 uuid，不用显示名：显示名可以改，图标不该跟着变脸。
  final String seed;

  /// 插件显示名，缩写取它。为空时落到一个「?」。
  final String name;

  /// 按种子从主题的三组 M3 容器角色对中连续插值出（底色, 前景色）。
  static ({Color background, Color foreground}) tonalPairOfSeed(
    ColorScheme scheme,
    String seed,
  ) {
    final normalized = (hueOfSeed(seed) % 360.0) / 360.0;
    final scaled = normalized * 3.0;
    final sector = scaled.floor() % 3;
    final t = scaled - scaled.floor();

    final pairs = <({Color bg, Color fg})>[
      (bg: scheme.primaryContainer, fg: scheme.onPrimaryContainer),
      (bg: scheme.secondaryContainer, fg: scheme.onSecondaryContainer),
      (bg: scheme.tertiaryContainer, fg: scheme.onTertiaryContainer),
    ];

    final from = pairs[sector];
    final to = pairs[(sector + 1) % 3];
    return (
      background: Color.lerp(from.bg, to.bg, t) ?? from.bg,
      foreground: Color.lerp(from.fg, to.fg, t) ?? from.fg,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (:background, :foreground) = tonalPairOfSeed(scheme, seed);
    final short = pluginShortName(name);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 无界时按占位尺寸画：调用方没给约束也不该炸，只是字会偏大。
        final side = constraints.biggest.shortestSide;
        final box = side.isFinite && side > 0 ? side : 48.0;
        // 小尺寸（标签条上那 14~16px）塞两个字就是糊，只留第一个。
        final units = box < 28 ? 1 : 2;
        final label = short.isEmpty
            ? '?'
            : String.fromCharCodes(short.runes.take(units));
        final radius = (box * 0.28).clamp(3.0, 16.0);

        return Container(
          decoration: ShapeDecoration(
            color: background,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(radius),
              side: BorderSide(
                color: foreground.withValues(alpha: 0.16),
                width: box >= 32 ? 1.0 : 0.5,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: box * (units == 1 ? 0.48 : 0.33),
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              height: 1.05,
            ),
          ),
        );
      },
    );
  }
}
