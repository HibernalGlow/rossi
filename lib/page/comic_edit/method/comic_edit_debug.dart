/// 测试用：非空时覆盖图片本地路径解析，避免 widget test 里跑真实文件 I/O。
Future<String> Function({
  required String from,
  required String comicId,
  required String storageChapterId,
  required String path,
})?
debugComicEditImagePathResolver;
