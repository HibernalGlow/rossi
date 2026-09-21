import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:material_ui/material_ui.dart';

/// 色环 + HSV 取色面 + 十六进制输入。
///
/// 这里刻意不用该包现成的 `HueRingPicker`：它内嵌的是 `flutter/material` 的
/// `TextField`，而本应用的组件树来自 `material_ui`，两者是不同的类型，
/// 于是找不到 Material 祖先与 MaterialLocalizations 会直接报错。
/// 因此只复用它的画笔组件（色环、取色面、色块指示器），输入框交给 material_ui。
class ColorPickerPage extends StatefulWidget {
  final Color currentColor;
  final Function(Color) onColorChanged;

  const ColorPickerPage({
    super.key,
    required this.currentColor,
    required this.onColorChanged,
  });

  @override
  State<ColorPickerPage> createState() => _ColorPickerPageState();
}

class _ColorPickerPageState extends State<ColorPickerPage> {
  static const double _pickerSize = 250.0;
  static const double _hueRingStrokeWidth = 20.0;

  late HSVColor _hsvColor = HSVColor.fromColor(widget.currentColor);
  final TextEditingController _hexController = TextEditingController();

  /// 上一次已经写进输入框的颜色，用于区分「取色器变了」和「用户正在打字」。
  Color? _hexShownColor;

  @override
  void didUpdateWidget(covariant ColorPickerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在外部颜色真的换了时重新同步，否则把饱和度拉到 0 后转色环会被弹回 0 度。
    if (widget.currentColor != oldWidget.currentColor) {
      _hsvColor = HSVColor.fromColor(widget.currentColor);
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _changeColor(HSVColor hsvColor) {
    setState(() => _hsvColor = hsvColor);
    widget.onColorChanged(_hsvColor.toColor());
  }

  void _changeHex(String value) {
    final Color? color = colorFromHex(value, enableAlpha: false);
    if (color == null) return;
    _hexShownColor = color;
    setState(() => _hsvColor = HSVColor.fromColor(color));
    widget.onColorChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    final Color color = _hsvColor.toColor();
    if (_hexShownColor != color) {
      _hexShownColor = color;
      _hexController.text = colorToHex(
        color,
        includeHashSign: true,
        enableAlpha: false,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: Stack(
              alignment: AlignmentDirectional.center,
              children: [
                SizedBox(
                  width: _pickerSize,
                  height: _pickerSize,
                  child: ColorPickerHueRing(
                    _hsvColor,
                    _changeColor,
                    displayThumbColor: true,
                    strokeWidth: _hueRingStrokeWidth,
                  ),
                ),
                SizedBox(
                  width: _pickerSize / 1.6,
                  height: _pickerSize / 1.6,
                  child: ColorPickerArea(
                    _hsvColor,
                    _changeColor,
                    PaletteType.hsv,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15.0, 5.0, 10.0, 5.0),
            child: Row(
              children: [
                ColorIndicator(_hsvColor),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 5, 0, 20),
                    child: TextField(
                      controller: _hexController,
                      inputFormatters: [
                        UpperCaseTextFormatter(),
                        FilteringTextInputFormatter.allow(
                          RegExp(kValidHexPattern),
                        ),
                      ],
                      decoration: InputDecoration(
                        isDense: true,
                        label: const Text('Hex'),
                        contentPadding: const EdgeInsets.symmetric(vertical: 5),
                      ),
                      onChanged: _changeHex,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
