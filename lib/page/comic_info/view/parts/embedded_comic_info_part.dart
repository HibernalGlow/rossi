part of '../comic_info.dart';

/// 原位详情复用同一套加载、章节与下载状态；关闭只作用于所在展墙。
class EmbeddedComicInfo extends StatelessWidget {
  const EmbeddedComicInfo({
    super.key,
    required this.comicId,
    required this.from,
    required this.type,
    required this.onClose,
    this.collectionTargetId,
    this.collectionTargetName,
  });
  final String comicId;
  final String from;
  final ComicEntryType type;
  final VoidCallback onClose;
  final String? collectionTargetId;
  final String? collectionTargetName;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => GetComicInfoBloc()
          ..add(
            GetComicInfoEvent(comicId: comicId, from: from.trim(), type: type),
          ),
      ),
      BlocProvider(create: (_) => StringSelectCubit()),
    ],
    child: _ComicInfo(
      comicId: comicId,
      type: type,
      from: from.trim(),
      onClose: onClose,
      collectionTargetId: collectionTargetId,
      collectionTargetName: collectionTargetName,
    ),
  );
}
