# Rossi 独立应用标识与数据迁移

Rossi 使用统一标识 `com.hibernalglow.rossi`，因此可以与原版 Breeze（`com.zephyr.breeze`）并存。
这次改动覆盖 Android applicationId、iOS/macOS bundle identifier、Linux GTK/Flatpak application ID、Windows 可执行文件与安装器运行标识。

首次启动时，桌面版会在打开 ObjectBox 之前检查旧的数据目录。它会先复制到临时目录，再校验文件摘要并试开数据库；全部通过后才切换到 Rossi 的目录。旧目录不会删除，也不会覆盖，Breeze 仍能继续使用。Rossi 会在新根目录写入 `.rossi-identity-v1.json`，后续启动不会重复复制。

Android 和 iOS 的应用私有目录由系统按 package/bundle 隔离。新应用不能读取旧应用的 `/data/user/0/com.zephyr.breeze` 或旧沙盒，因此 Android/iOS 首次启动会提示从 Breeze 导出备份，再使用 Rossi 的「设置 → 数据备份 → 导入数据」。旧应用和备份都保留。Android 会检查原包是否仍安装，仅用于显示提示，不会请求 root 或删除原应用。

迁移失败时显示启动失败原因，不会生成空库掩盖旧数据。旧目录和迁移临时目录均保留，排除空间不足、权限或旧应用仍在写入等问题后，重启即可重试。不要在旧应用运行时迁移；校验发现源文件在复制期间发生变化会放弃切换。

## 标识清单

| 平台 | Rossi | 原版 Breeze |
|---|---|---|
| Android | `com.hibernalglow.rossi` | `com.zephyr.breeze` |
| iOS / macOS | `com.hibernalglow.rossi` | `com.zephyr.breeze` |
| Linux GTK / Flatpak | `com.hibernalglow.rossi` | `io.github.windy.breeze` |
| Windows exe | `rossi.exe` | `zephyr.exe` |

MethodChannel 名 `com.zephyr.breeze/file_picker` 是 Dart 与 Android 原生代码之间的内部协议字符串，不能随 package 改名，否则备份文件选择器会失效。

## 验证

```bash
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test test/service/app_identity/data_migration_test.dart
```

Android 包安装后可用以下命令确认共存：

```bash
adb shell pm list packages | rg 'com\.zephyr\.breeze|com\.hibernalglow\.rossi'
adb shell cmd package resolve-activity --brief com.hibernalglow.rossi
```
