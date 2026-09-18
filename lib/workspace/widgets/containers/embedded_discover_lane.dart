import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/discover/view/discover_page.dart';

/// 完整复用上游现有 DiscoverPage 的宿主容器
class EmbeddedDiscoverLane extends StatelessWidget {
  const EmbeddedDiscoverLane({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(12),
        bottomRight: Radius.circular(12),
      ),
      child: const DiscoverPage(),
    );
  }
}
