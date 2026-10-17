import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/comic_info/view/comic_info.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/path_util.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_local_book_details.dart';

/// 展开即加载真实内容；原封面与书名保留在上方选中卡片中。
class LibraryBookDetails extends StatelessWidget {
  const LibraryBookDetails({
    super.key,
    required this.entry,
    required this.comicId,
    required this.from,
    required this.onClose,
    this.type = ComicEntryType.normal,
    this.extern,
    this.collectionTargetId,
    this.collectionTargetName,
  });
  final LibraryEntry entry;
  final String comicId;
  final String from;
  final ComicEntryType type;
  final Map<String, dynamic>? extern;
  final VoidCallback onClose;
  final String? collectionTargetId;
  final String? collectionTargetName;

  @override
  Widget build(BuildContext context) => isLocalComicSource(from, comicId)
      ? LibraryLocalBookDetails(
          key: ValueKey(comicId),
          entry: entry,
          path: comicId,
          onClose: onClose,
        )
      : EmbeddedComicInfo(
          key: ValueKey('$from:$comicId:$type'),
          comicId: comicId,
          from: from,
          type: type,
          onClose: onClose,
          extern: extern,
          collectionTargetId: collectionTargetId,
          collectionTargetName: collectionTargetName,
        );
}
