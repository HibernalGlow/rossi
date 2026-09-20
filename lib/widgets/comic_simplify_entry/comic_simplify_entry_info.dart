// To parse this JSON data, do
//
//     final comicSimplifyEntryInfo = comicSimplifyEntryInfoFromJson(jsonString);

import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:zephyr/type/enum.dart';

part 'comic_simplify_entry_info.freezed.dart';
part 'comic_simplify_entry_info.g.dart';

ComicSimplifyEntryInfo comicSimplifyEntryInfoFromJson(String str) =>
    ComicSimplifyEntryInfo.fromJson(json.decode(str));

String comicSimplifyEntryInfoToJson(ComicSimplifyEntryInfo data) =>
    json.encode(data.toJson());

@freezed
abstract class ComicSimplifyEntryInfo with _$ComicSimplifyEntryInfo {
  const factory ComicSimplifyEntryInfo({
    @JsonKey(name: "title") required String title,
    @JsonKey(name: "id") required String id,
    @JsonKey(name: "fileServer") required String fileServer,
    @JsonKey(name: "path") required String path,
    @JsonKey(name: "pictureType") required PictureType pictureType,
    @JsonKey(name: "source") @Default('') String source,
    @JsonKey(name: "from") required String from,
    @JsonKey(name: "tags") @Default([]) List<String> tags,
    // 喜欢画师匹配要按命名空间分桶后再比，`tags` 是压平的（语言角标那类判定用它）。
    @JsonKey(name: "artistTags") @Default([]) List<String> artistTags,
    @JsonKey(name: "circleTags") @Default([]) List<String> circleTags,
  }) = _ComicSimplifyEntryInfo;

  factory ComicSimplifyEntryInfo.fromJson(Map<String, dynamic> json) =>
      _$ComicSimplifyEntryInfoFromJson(json);
}
