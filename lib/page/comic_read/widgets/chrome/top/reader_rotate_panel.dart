import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/page/comic_read/cubit/reader_presentation_cubit.dart';
import 'package:zephyr/page/comic_read/model/reader_presentation.dart';
import 'package:zephyr/page/comic_read/widgets/chrome/top/reader_toolbar_shell.dart';

/// 顶栏「旋转」面板 —— neoview `RotatePanel` 的对应物。
///
/// 四组各自独立：手动旋转（整帧转）、自动旋转（只转纵向页）、横屏（只转横向页）、
/// 强制（无条件转）。后三组共用同一个 `autoRotation` 字段，**互斥** ——
/// 判据在 [effectiveReaderRotation] 里，与渲染层同一份。
class ReaderRotatePanel extends StatelessWidget {
  const ReaderRotatePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final presentation = context.select((ReaderPresentationCubit c) => c.state);
    final cubit = context.read<ReaderPresentationCubit>();

    return ReaderToolbarPanelRow(
      children: [
        ReaderToolbarLabel('手动旋转 ${presentation.rotation}°'),
        ReaderToolbarPill(
          children: [
            ReaderToolbarIconButton(
              icon: Icons.rotate_right_rounded,
              tooltip: '顺时针旋转 90°',
              onPressed: () => cubit.rotate(1),
            ),
            ReaderToolbarIconButton(
              icon: Icons.rotate_left_rounded,
              tooltip: '逆时针旋转 90°',
              onPressed: () => cubit.rotate(-1),
            ),
          ],
        ),
        const ReaderToolbarSeparator(),
        const ReaderToolbarLabel('自动旋转'),
        _AutoRotationPill(
          current: presentation.autoRotation,
          modes: const [
            ReaderAutoRotation.none,
            ReaderAutoRotation.left,
            ReaderAutoRotation.right,
          ],
        ),
        const ReaderToolbarSeparator(),
        const ReaderToolbarLabel('横屏'),
        _AutoRotationPill(
          current: presentation.autoRotation,
          modes: const [
            ReaderAutoRotation.horizontalLeft,
            ReaderAutoRotation.horizontalRight,
          ],
        ),
        const ReaderToolbarSeparator(),
        const ReaderToolbarLabel('强制'),
        _AutoRotationPill(
          current: presentation.autoRotation,
          modes: const [
            ReaderAutoRotation.forcedLeft,
            ReaderAutoRotation.forcedRight,
          ],
        ),
      ],
    );
  }
}

class _AutoRotationPill extends StatelessWidget {
  final ReaderAutoRotation current;
  final List<ReaderAutoRotation> modes;

  const _AutoRotationPill({required this.current, required this.modes});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ReaderPresentationCubit>();
    return ReaderToolbarPill(
      children: [
        for (final mode in modes)
          ReaderToolbarIconButton(
            icon: _icon(mode),
            tooltip: _label(mode),
            // 「关闭自动旋转」选中时不点亮底色 —— 它是这一组的缺省态，
            // 亮着反而让人以为开了什么。
            selected: current == mode && mode != ReaderAutoRotation.none,
            onPressed: () => cubit.setAutoRotation(mode),
          ),
      ],
    );
  }

  static IconData _icon(ReaderAutoRotation mode) => switch (mode) {
    ReaderAutoRotation.none => Icons.block_rounded,
    ReaderAutoRotation.left ||
    ReaderAutoRotation.horizontalLeft ||
    ReaderAutoRotation.forcedLeft => Icons.rotate_left_rounded,
    ReaderAutoRotation.right ||
    ReaderAutoRotation.horizontalRight ||
    ReaderAutoRotation.forcedRight => Icons.rotate_right_rounded,
  };

  static String _label(ReaderAutoRotation mode) => switch (mode) {
    ReaderAutoRotation.none => '关闭自动旋转',
    ReaderAutoRotation.left => '纵向页左旋',
    ReaderAutoRotation.right => '纵向页右旋',
    ReaderAutoRotation.horizontalLeft => '横向页左旋',
    ReaderAutoRotation.horizontalRight => '横向页右旋',
    ReaderAutoRotation.forcedLeft => '一律左旋',
    ReaderAutoRotation.forcedRight => '一律右旋',
  };
}
