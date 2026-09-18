import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/bookshelf/bookshelf.dart';

/// 完整复用上游现有 BookshelfPage 的宿主容器
class EmbeddedBookshelfLane extends StatelessWidget {
  const EmbeddedBookshelfLane({super.key});

  @override
  Widget build(BuildContext context) {
    // 外层包裹 ClipRRect 保证圆角边框美观，内部完全运行原生 BookshelfPage
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(12),
        bottomRight: Radius.circular(12),
      ),
      child: const BookshelfPage(),
    );
  }
}
