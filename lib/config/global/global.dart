// 此文件用于定义全局变量，也做部分初始化工作

/// 存储与同步标识，不可随意改动：它同时是下载根目录名（`get_path.dart`）和
/// WebDAV / S3 的同步根目录名（`comic_sync_core.dart`）。改动会让既有数据找不到目录。
final String appName = 'Breeze';

/// 界面与系统里展示给用户的应用名，与 [appName] 刻意分离。
final String appDisplayName = 'Rossi';

// 这个版本号是用来记录一些重大迁移的
final String mainVersion = "v2";

final String syncVersion = "v1";
