import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/more/view/more.dart';

/// 完整复用上游现有 MorePage（设置/关于/存储/同步）的宿主容器
class EmbeddedAuxiliaryLane extends StatelessWidget {
  const EmbeddedAuxiliaryLane({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(12),
        bottomRight: Radius.circular(12),
      ),
      child: const MorePage(),
    );
  }
}
