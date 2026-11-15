import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/widget/markdown_block.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:permission_guard/permission_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/network/utils/github_proxy.dart';
import 'package:zephyr/service/update/json/github_release_json.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/widgets/toast.dart';

/// 「一周内不再提醒」静默期截止时间的存储键（毫秒时间戳）。
const String updateSnoozeUntilPrefsKey = 'update_snooze_until_ms';

/// 「一周内不再提醒」的静默时长。
const Duration updateSnoozeDuration = Duration(days: 7);

/// 用户已查看过更新日志的版本号存储键。
const String changelogSeenVersionPrefsKey = 'changelog_seen_version';

/// 检测到的可用更新；非空时「更新日志」条目展示 NEW 徽标。
/// 只做界面提示，不额外发送通知。
final ValueNotifier<GithubReleaseJson?> pendingAppUpdate =
    ValueNotifier<GithubReleaseJson?>(null);

/// 该版本的更新日志是否已看过（看过则不再展示 NEW 徽标）。
Future<bool> isChangelogSeen(String version) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(changelogSeenVersionPrefsKey) == version;
  } catch (e, stackTrace) {
    logger.e('读取更新日志已读版本失败', error: e, stackTrace: stackTrace);
    return false;
  }
}

/// 打开更新日志后调用：清掉徽标并记住该版本，同一版本不再提示。
/// 不传版本时取当前检测到的可用更新版本。
Future<void> markChangelogSeen([String? version]) async {
  final seenVersion = version ?? pendingAppUpdate.value?.tagName;
  pendingAppUpdate.value = null;
  if (seenVersion == null) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(changelogSeenVersionPrefsKey, seenVersion);
  } catch (e, stackTrace) {
    logger.e('保存更新日志已读版本失败', error: e, stackTrace: stackTrace);
  }
}

/// 更新提醒是否处于「一周内不再提醒」的静默期。
Future<bool> isUpdateReminderSnoozed() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final untilMs = prefs.getInt(updateSnoozeUntilPrefsKey);
    if (untilMs == null) return false;
    return DateTime.now().millisecondsSinceEpoch < untilMs;
  } catch (e, stackTrace) {
    logger.e('读取更新提醒静默时间失败', error: e, stackTrace: stackTrace);
    return false;
  }
}

/// 设置「一周内不再提醒」。
Future<bool> snoozeUpdateReminderForWeek() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final untilMs = DateTime.now()
        .add(updateSnoozeDuration)
        .millisecondsSinceEpoch;
    await prefs.setInt(updateSnoozeUntilPrefsKey, untilMs);
    return true;
  } catch (e, stackTrace) {
    logger.e('保存更新提醒静默时间失败', error: e, stackTrace: stackTrace);
    return false;
  }
}

Future<String> getAppVersion() async {
  String version = 'Unknown';

  try {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    version = packageInfo.version;
  } catch (e, stackTrace) {
    logger.e(e, stackTrace: stackTrace);
  }

  return version;
}

Future<GithubReleaseJson> getCloudVersion() async {
  const releasesApi =
      "https://api.github.com/repos/breeze-project-org/Breeze/releases/latest";

  try {
    logger.d('尝试使用自建 API: $breezeLatestReleaseApi');
    final response = await fetch(
      breezeLatestReleaseApi,
      headers: {'Accept': 'application/json, text/plain, */*'},
    );
    final body = response.text.trim();
    if (body.isNotEmpty) {
      return GithubReleaseJson.fromJson(jsonDecode(body));
    }
  } catch (e, stackTrace) {
    logger.w(
      '自建 API 通道失败: $breezeLatestReleaseApi',
      error: e,
      stackTrace: stackTrace,
    );
  }

  try {
    final temp = await fetch(
      "https://breeze-version.s3.bitiful.net/breeze-version.json",
    );
    final tempJson = temp.json;
    var version = (tempJson is Map ? tempJson['version'] : null) ?? 'latest';

    const ghCdnMirrors = [
      'https://cdn.jsdmirror.com/',
      'https://cdn.jsdmirror.cn/',
      'https://jsd.onmicrosoft.cn/',
      'https://cdn.jsdelivr.net/',
    ];

    for (final mirror in ghCdnMirrors) {
      final url =
          '${mirror}gh/breeze-project-org/Breeze@$version/update-tag-version/latest-release.json';
      logger.d('尝试使用 GitHub CDN 镜像: $url');
      try {
        final response = await fetch(
          url,
          headers: {'Accept': 'application/json, text/plain, */*'},
        );
        final body = response.text.trim();
        if (body.isNotEmpty) {
          return GithubReleaseJson.fromJson(jsonDecode(body));
        }
      } catch (e, stackTrace) {
        logger.w('CDN 镜像通道失败: $url', error: e, stackTrace: stackTrace);
      }
    }
  } catch (e) {
    logger.e(e);
  }

  while (true) {
    try {
      return await fetchReleaseData(releasesApi)
          .let(GithubReleaseJson.fromJson);
    } catch (e) {
      logger.e(e);
      await Future.delayed(const Duration(minutes: 5));
    }
  }
}

bool isUpdateAvailable(String cloudVersion, String localVersion) {
  logger.d('App version: $localVersion\nCloud version: $cloudVersion');

  cloudVersion = cloudVersion.replaceFirst('v', '');

  final cloudVersionParts = cloudVersion.split('.');
  final localVersionParts = localVersion.split('.');

  for (int i = 0; i < 3; i++) {
    final int cloudPart = int.parse(cloudVersionParts[i]);
    final int localPart = int.parse(localVersionParts[i]);

    if (cloudPart > localPart) {
      return true;
    } else if (cloudPart < localPart) {
      return false;
    }
  }

  return false;
}

Future<void> installApk(String apkUrl) async {
  if (await _requestInstallPackagesPermission()) {
    try {
      String tempDir = await getCachePath();
      String apkFilePath = p.join(tempDir, 'app.apk');

      if (_isGithubReleaseDownloadUrl(apkUrl)) {
        await smartDownload(apkUrl, apkFilePath);
      } else {
        final response = await fetch(apkUrl);
        await File(apkFilePath).writeAsBytes(response.body);
      }

      OpenFile.open(apkFilePath);
    } catch (e) {
      logger.e(e);
      showErrorToast(t.update.apkDownloadFailed);
    }
  } else {
    showErrorToast(t.update.installPermissionRequired);
  }
}

Future<bool> _requestInstallPackagesPermission() async {
  if (!Platform.isAndroid) return false;
  try {
    final status = await Permission.requestInstallPackages.status;
    if (status.isGranted) {
      return true;
    } else if (status.isDenied) {
      final requestResult = await Permission.requestInstallPackages.request();
      return requestResult.isGranted;
    }
  } on PlatformException catch (e) {
    // 用户取消安装权限弹窗属于预期情况。
    logger.w('请求安装权限失败', error: e);
  }
  return false;
}

bool _isGithubReleaseDownloadUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') {
    return false;
  }

  final host = uri.host.toLowerCase();
  if (host != 'github.com' && host != 'www.github.com') {
    return false;
  }

  final segments = uri.pathSegments;
  if (segments.length < 6) {
    return false;
  }

  return segments[2] == 'releases' && segments[3] == 'download';
}

Future<void> checkUpdate(BuildContext context) async {
  // fork 构建默认跳过（见 `GlobalSettingState.skipUpdateCheck`）：本仓版本号永远
  // 低于上游，弹出来的只会是 deretame/Breeze 的安装包。
  if (globalSetting.skipUpdateCheck) {
    logger.d('已开启「跳过更新检查」，本次不请求上游版本');
    return;
  }

  if (!context.mounted) return;
  // 静默期只抑制弹窗，仍然检测版本，好让「更新日志」保留 NEW 徽标。
  final snoozed = await isUpdateReminderSnoozed();
  final temp = await getCloudVersion();
  final cloudVersion = temp.tagName;
  final releaseInfo = temp.body;
  final String localVersion = await getAppVersion();
  final url =
      'https://github.com/breeze-project-org/Breeze/releases/tag/$cloudVersion';
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  String arch = t.update.unknownArch;
  try {
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      List<String> abis = androidInfo.supportedAbis;
      if (abis.isNotEmpty) {
        arch = abis.first;
        logger.d(arch);
      }
    }
  } catch (e) {
    return;
  }

  if (!isUpdateAvailable(cloudVersion, localVersion)) {
    pendingAppUpdate.value = null;
    return;
  }

  // 已看过该版本的更新日志就不再挂徽标，避免同一版本反复提示。
  final changelogSeen = await isChangelogSeen(cloudVersion);
  pendingAppUpdate.value = changelogSeen ? null : temp;

  if (snoozed) {
    logger.d('更新提醒处于静默期，跳过本次弹窗');
    return;
  }

  if (!context.mounted) return;
  final releaseNotes = releaseInfo;
  final releasePageUrl = url;

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(t.update.newVersion),
        content: SingleChildScrollView(
          child: MarkdownBlock(data: releaseNotes),
        ),
        actions: [
          TextButton(
            child: Text(t.update.snoozeWeek),
            onPressed: () async {
              context.pop();
              if (await snoozeUpdateReminderForWeek()) {
                showSuccessToast(t.update.snoozeWeekSuccess);
              }
            },
          ),
          TextButton(
            child: Text(t.common.cancel),
            onPressed: () => context.pop(),
          ),
          TextButton(
            child: Text(t.update.goToGitHub),
            onPressed: () {
              launchUrl(Uri.parse(releasePageUrl));
              context.pop();
            },
          ),
          if (Platform.isAndroid)
            TextButton(
              child: Text(t.update.downloadInstall),
              onPressed: () async {
                context.pop();
                for (var apkUrl in temp.assets) {
                  if (apkUrl.browserDownloadUrl.contains(arch) &&
                      !apkUrl.browserDownloadUrl.contains("skia")) {
                    await installApk(apkUrl.browserDownloadUrl);
                  }
                }
              },
            ),
        ],
      );
    },
  );
}
