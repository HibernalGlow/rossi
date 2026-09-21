import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/color_theme_types.dart';
import 'package:zephyr/util/theme/tweakcn_color.dart';

/// 预设色块：圆形样本 + 下方名称，选中的那颗用 primary 描边并打勾。
///
/// 宽度是定值，不再按屏宽切四份 —— 这一屏可能被塞进窄面板，按屏宽算出的
/// 单项宽度会超过可用宽度，让 [Wrap] 退化成一行一个。每行排几颗交给 [Wrap]。
class ColorThemeItem extends StatelessWidget {
  /// 圆样本的直径；外层再留 8px 给选中时加粗的描边。
  static const double _swatchSize = 40.0;
  static const double _itemWidth = 72.0;

  final ColorThemeInfo colorInfo;
  final Color currentColor;
  final ValueChanged<Color> onColorSelected;

  const ColorThemeItem({
    super.key,
    required this.colorInfo,
    required this.currentColor,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final swatch = colorInfo.color;
    final selected = currentColor == swatch;

    return SizedBox(
      width: _itemWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _swatchSize + 8,
            height: _swatchSize + 8,
            child: Tooltip(
              message: colorInfo.localizedLabel,
              child: InkWell(
                onTap: () => onColorSelected(swatch),
                customBorder: const CircleBorder(),
                child: Center(
                  child: Container(
                    width: _swatchSize,
                    height: _swatchSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: swatch,
                      border: Border.all(
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    // 勾的颜色按样本自身亮度算，浅底配深色才不会看不见。
                    child: selected
                        ? Icon(Icons.check, size: 18, color: contrastOn(swatch))
                        : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            colorInfo.localizedLabel,
            style: textTheme.labelSmall?.copyWith(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
