import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:desktop_webview_linux/desktop_webview_linux.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_socks_proxy/socks_proxy.dart';
import 'package:logger/logger.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:worker_manager/worker_manager.dart';
import 'package:zephyr/config/global/global.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/global/theme_shape.dart';
import 'package:zephyr/util/theme/tweakcn_theme.dart';
import 'package:zephyr/config/router/router.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/gpu/page_turn_probe.dart';
import 'package:zephyr/i18n/i18n_helper.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/i18n/system_locale_service.dart';
import 'package:zephyr/network/http/wind_http.dart';
import 'package:zephyr/network/sync/sync_device_id.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/object_box.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/platform/desktop/native_window.dart';
import 'package:zephyr/platform/desktop/system_tray.dart';
import 'package:zephyr/platform/desktop/window_logic.dart';
import 'package:zephyr/service/operation_binding/operation_binding_store.dart';
import 'package:zephyr/service/reader/switch_toast_service.dart';
import 'package:zephyr/service/startup_database_snapshot_service.dart';
import 'package:zephyr/src/rust/api/qjs.dart';
import 'package:zephyr/src/rust/api/simple.dart';
import 'package:zephyr/src/rust/api/system.dart' as rust_system;
import 'package:zephyr/util/debouncer.dart';
import 'package:zephyr/util/error_filter.dart';
import 'package:zephyr/util/font/font_profile.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/util/layout/layout_overflow_guard.dart';
import 'package:zephyr/util/manage_cache.dart';
import 'package:zephyr/util/rust_loader.dart';
import 'package:zephyr/widgets/desktop/desktop_shell_frame.dart';
import 'package:zephyr/widgets/desktop/intent.dart';

export 'package:zephyr/network/http/wind_http.dart'
    show WindHttp, FetchResponse, fetch, fetchDirect;

ObjectBox? _objectbox;
ObjectBox get objectbox => _objectbox!;
set objectbox(ObjectBox value) => _objectbox = value;

final appRouter = AppRouter();

// 全局事件总线实例
EventBus eventBus = EventBus();

var logger = Logger(
  printer: TersePrettyPrinter(),
  // filter: MyAlwaysLogFilter(),
  // output: RemoteOutput(),
);

List<String> cfIpList = [];

final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

final navigatorKey = GlobalKey<NavigatorState>();

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

class RemoteOutput extends LogOutput {
  final String url;

  RemoteOutput(this.url);

  @override
  void output(OutputEvent event) {
    _sendToServer(event.lines.join('\n'), event.level);
  }

  Future<void> _sendToServer(String message, Level level) async {
    try {
      await fetch(
        url,
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: {'level': level.name, 'message': '\n$message'},
        timeout: const Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }
}

class MyAlwaysLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => true; // 强制通过所有日志
}

/// 启动失败时把原因落盘。
///
/// 这不是调试残留，是这条路径**唯一**的可观测手段：这个进程属于 GUI 子系统，
/// `print` / `logger` / 未配置 DSN 的 Sentry 都不会把任何东西送到人能看见的地方。
/// 而启动期抛异常的直接后果是**根本不会调用 `runApp`** —— 窗口永远停在一片黑，
/// 看起来像渲染坏了，其实是启动就死在了初始化里。
///
/// 这个坑已经咬过两次，两次都是同一个原因（见下）：仓库里 `rust/target/release/
/// libwindcore.dylib` 与 `frb_generated` 的 content hash 对不上，`RustLib.init()`
/// 抛 `Content hash on Dart side (…) is different from Rust side (…)`
/// —— 从仓库根目录启动时，FRB 的 `ioDirectory: 'rust/target/release/'`
/// 是按**当前工作目录**解析的，于是加载的是仓库里那份旧库、而不是 App 包里那份新的。
/// 修法是 `cd rust && cargo build -p windcore --release` 重新生成它。
/// 但真正要修的是「黑屏且零线索」这件事本身。
Future<void> _writeBootLog(
  String stage, [
  Object? error,
  StackTrace? stack,
]) async {
  try {
    final String text = error == null
        ? '${DateTime.now().toIso8601String()} [$stage]\n'
        : '${DateTime.now().toIso8601String()} [$stage] $error\n$stack\n\n';
    await File(
      '/tmp/breeze_boot.log',
    ).writeAsString(text, mode: FileMode.append, flush: true);
  } catch (_) {
    // 连日志都写不出去时不再往上抛。
  }
}

/// 启动失败时的**可见**界面。
///
/// 原来这里是「吞掉异常 + 直接 return」，而 `return` 意味着永远不会调用 `runApp`：
/// 用户看到的是一片永远不动的黑，且没有控制台、没有 Sentry、没有日志 ——
/// 一个本来一行命令就能修的问题，被表现成「渲染坏了」。
/// 宁可显示一个丑但能读的错误页，也不要一片黑。
void _runBootFailureApp(String stage, Object error, StackTrace stack) {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF101014),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.error_outline,
                    color: Color(0xFFFF6B6B),
                    size: 44,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '应用启动失败',
                    style: TextStyle(
                      color: Color(0xFFE6EDF3),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    '阶段: $stage',
                    style: const TextStyle(
                      color: Color(0xFF8B949E),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    '$error',
                    style: const TextStyle(
                      color: Color(0xFFFF9C6B),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    '$stack',
                    style: const TextStyle(
                      color: Color(0xFF6E7681),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> main(List<String> args) async {
  // 框架级错误也落盘：默认的 `presentError` 只往控制台写，而这里没有控制台，
  // 于是「平台视图创建失败」这类错误会彻底消失，表现仍然是一片黑。
  FlutterError.onError = (FlutterErrorDetails details) {
    // 「黄黑溢出斜纹」开关关掉时，溢出类错误整条不上报。
    // 口径与适用范围见 `lib/util/layout/layout_overflow_guard.dart` 顶部。
    if (!shouldReportFlutterError(details)) return;
    FlutterError.presentError(details);
    unawaited(
      _writeBootLog(
        'FlutterError(${details.context ?? '无上下文'})',
        details.exception,
        details.stack,
      ),
    );
  };

  // 1. 基础初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 翻页量具的无人值守模式：设了 `ROSSI_PAGE_TURN_LOG` 就**绕开整个 App 启动**，
  // 只跑 GPU 上屏那条路，把帧时间与分段耗时写成 CSV。
  //
  // 位置是有意的 —— 必须在 `_initServices()` **之前**。量时间的东西不该被数据库
  // 初始化、插件注册、窗口尺寸还原这些东西影响；而且它们跟这条链路本来无关。
  // 判据 C 只在 Release 下成立，而 `flutter test` 只能跑 Debug，
  // 所以量具只能挂在 App 自己身上。见 `lib/gpu/page_turn_probe.dart`。
  if (PageTurnProbe.isRequested) {
    // 量具要用 FRB 打开来源，所以 Rust 侧得先站起来（正常启动里这一步在
    // `_initServices()` 里，这里绕过去了）。
    //
    // 整段包住并把失败落盘：本进程是 GUI 子系统、没有控制台，`print` 与未捕获
    // 异常都不会出现在任何地方，表现成「rc=1、无输出、无文件」，跟「启动崩溃」
    // 分不开（这个坑实际吃过一次）。所以量具的失败路径**只认文件**。
    try {
      await initRustLib();
      runApp(const PageTurnProbeApp());
    } catch (e, stack) {
      await writeProbeBootFailure(e, stack);
      exit(4);
    }
    return;
  }

  // 先生成本地同步设备 ID，后续文件夹/链接的版本向量会使用它
  await ensureSyncDeviceId();

  // desktop_webview_linux 必需的标题栏子进程入口
  // 不添加会导致 Linux 下 WebView 窗口关闭时 segfault 崩溃
  if (!kIsWeb && Platform.isLinux && runWebViewTitleBarWidget(args)) {
    return;
  }

  const sentryDsn = String.fromEnvironment('sentry_dsn', defaultValue: '');

  if (sentryDsn.isEmpty) {
    // 1. 如果是调试模式，配置 logger 捕获全局错误
    if (kDebugMode || sentryDsn.isEmpty) {
      // 捕获 Flutter 框架层错误（如 Widget 构建中的异常）
      FlutterError.onError = (FlutterErrorDetails details) {
        if (!shouldReportFlutterError(details)) return;
        logger.e(
          "Flutter Framework Error",
          error: details.exception,
          stackTrace: details.stack,
        );
      };

      // 捕获异步错误和底层错误（如 Future.error, Timer 等）
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        logger.e("Async/Platform Error", error: error, stackTrace: stack);
        return true; // 表示错误已被处理
      };
    }

    try {
      // 2. 执行业务初始化
      final (globalSettingCubit, pluginRegistryCubit) = await _initServices();

      final comicFollowCubit = ComicFollowCubit();

      runApp(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: globalSettingCubit),
            BlocProvider.value(value: pluginRegistryCubit),
            BlocProvider.value(value: comicFollowCubit),
          ],
          child: const MyApp(),
        ),
      );
    } catch (e, stack) {
      // 捕获初始化阶段（_initServices）可能抛出的异常
      if (kDebugMode || sentryDsn.isEmpty) {
        logger.e("App Setup Failed", error: e, stackTrace: stack);
      }
      await _writeBootLog('initServices（无 Sentry 路径）', e, stack);
      _runBootFailureApp('_initServices（无 Sentry 路径）', e, stack);
    }

    return;
  }

  // 2. 使用 Sentry 包装整个应用生命周期
  await SentryFlutter.init(
    (options) {
      options.dsn = sentryDsn;

      // 开启默认的个人信息采集（IP/Header），有助于分析用户分布
      options.sendDefaultPii = true;

      // 仅在调试模式下打印 Sentry 内部日志
      options.debug = kDebugMode;

      // --- Sentry Sponsored Business 特权配置 ---
      // 性能追踪采样率
      options.tracesSampleRate = 1.0;

      // sentry_flutter 10.0.0-alpha.5 暂不提供 Dart 侧性能剖析采样配置。

      // Android 上暂时关闭 Replay，规避原生侧生命周期卡顿/ANR 风险。
      if (Platform.isAndroid) {
        options.replay.sessionSampleRate = 0.0;
        options.replay.onErrorSampleRate = 0.0;
      } else {
        // 会话回放设置：平时抽样 10%，遇到错误时 100% 录制
        options.replay.sessionSampleRate = 0.1;
        options.replay.onErrorSampleRate = 1.0;
      }

      // 附加线程信息和堆栈，增强原生层（Rust/C++）错误分析
      options.attachThreads = true;
      options.attachStacktrace = true;
    },
    appRunner: () async {
      try {
        final (globalSettingCubit, pluginRegistryCubit) = await _initServices();
        final comicFollowCubit = ComicFollowCubit();

        await addArchitectureTagsToSentry();

        runApp(
          SentryWidget(
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: globalSettingCubit),
                BlocProvider.value(value: pluginRegistryCubit),
                BlocProvider.value(value: comicFollowCubit),
              ],
              child: MyApp(),
            ),
          ),
        );
      } catch (exception, stackTrace) {
        // 这里原来只上报 Sentry 就结束了。没配 DSN 时等于**什么都没发生**，
        // 而代价是 runApp 永远不会被调用 —— 用户看到的是一片永远不动的黑。
        await _writeBootLog('appRunner 启动失败', exception, stackTrace);
        _runBootFailureApp('appRunner / _initServices', exception, stackTrace);
        await Sentry.captureException(exception, stackTrace: stackTrace);
      }
    },
  );
}

Future<(GlobalSettingCubit, PluginRegistryCubit)> _initServices() async {
  // 初始化rust
  await initRustLib();

  // 初始化 i18n：先设置默认中文，待 GlobalSettingCubit 加载后再根据用户设置或系统语言切换。
  LocaleSettings.setLocale(AppLocale.enUs);
  I18nHelper.setRustErrorLanguage(AppLocale.enUs);

  // 初始化工作线程
  await workerManager.init(isolatesCount: Platform.numberOfProcessors);

  // 关掉rust端，主要是anyhow的堆栈调用信息
  enableStacktrace(enabled: false);

  enableRustLog(enabled: kDebugMode);

  if (kDebugMode) {
    setQjsErrorStackEnabled(enabled: true);
    // 配置http代理，方便开发测试
    await _tryApplyHttpProxyFromEnv();
  } else {
    setQjsErrorStackEnabled(enabled: false);
  }

  // 初始化前台任务
  FlutterForegroundTask.initCommunicationPort();

  // 重采样触控刷新率
  GestureBinding.instance.resamplingEnabled = true;

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ),
  );

  final isWin = Platform.isWindows;
  final cache = PaintingBinding.instance.imageCache;

  // 设置图片缓存数量和内存占用大小（桌面端设置的稍微大点）
  cache.maximumSizeBytes = 200 * 1024 * 1024 * (isWin ? 3 : 1);
  cache.maximumSize = 50 * (isWin ? 3 : 1);

  // 如果是手机的话就固定为只能使用横屏模式
  if (!isTabletWithOutContext()) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  objectbox = await ObjectBox.create();
  // 设置库（Rust `SettingsDb`）的路径也在启动期定好：用它的是工作台里的文件浏览卡片，
  // 卡片在 initState 里就要路径，不该在那里现走一次 path_provider。
  await prepareSettingsDbPath();
  final setting = objectbox.userSettingBox.get(1);
  if (setting == null) {
    objectbox.userSettingBox.put(UserSetting());
  }

  final globalSettingCubit = GlobalSettingCubit();
  await globalSettingCubit.initBox();
  // 操作绑定的出厂表在**这里**播种（不在 cubit 的 fromJson 里）：默认值是引擎生成的
  // 数据（ADR-0015），而引擎要等 `initRustLib()` 才能问 —— 这一行就是那个时机。
  // 播种失败/表为空时运行时会自动回退到改造前的硬编码分区，阅读器不会因此失灵。
  OperationBindingStore.seedIfNeeded(globalSettingCubit);
  // 「切换提示」运行时（N-17）：只登记一个总线监听，弹不弹、弹什么都在事件时
  // 现读设置，所以放启动期零成本；objectbox 已在上面就绪，读设置是安全的。
  SwitchToastService.instance.start();
  setHttpRequestsBlocked(
    blocked: globalSettingCubit.state.blockRustHttpRequests,
  );

  // 根据用户设置或系统语言初始化应用语言
  if (globalSettingCubit.state.localeFollowsSystem) {
    final systemInfo = await SystemLocaleService.getInfo();
    await globalSettingCubit.setSystemLocale(systemInfo.locale);
  } else {
    await globalSettingCubit.setLocale(globalSettingCubit.state.locale);
  }

  await FontProfileController.instance.init();

  final pluginRegistryCubit = PluginRegistryCubit();

  if (globalSettingCubit.state.needCleanCache) {
    await clearCache(await getCachePath());
  }

  final proxySetting = globalSettingCubit.state.proxySetting;
  if (proxySetting.enabled && proxySetting.address.trim().isNotEmpty) {
    final proxyAddress = proxySetting.address.trim();
    switch (proxySetting.type) {
      case ProxyType.http:
        final proxyUrl =
            proxyAddress.startsWith('http://') ||
                proxyAddress.startsWith('https://')
            ? proxyAddress
            : 'http://$proxyAddress';
        setHttpProxy(proxy: proxyUrl);
        // Dart 侧纯 dart:io HttpClient（如 minio / S3 同步）也走 HTTP 代理
        SocksProxy.initProxy(proxy: 'PROXY ${_stripProxyScheme(proxyUrl)}');
      case ProxyType.socks5:
        SocksProxy.initProxy(proxy: 'SOCKS5 $proxyAddress');
        setSocks5Proxy(proxy: proxyAddress);
    }
  }

  // 设置日志转发（包含flutter和qjs的日志）
  final logAddress = globalSettingCubit.state.logAddress;

  if (logAddress.isNotEmpty) {
    if (!kDebugMode) {
      logger = Logger(
        printer: TersePrettyPrinter(),
        filter: MyAlwaysLogFilter(),
        output: RemoteOutput(logAddress),
      );
    }
    setLogHttpForward(url: logAddress);
    setQjsErrorStackEnabled(enabled: true);
  }

  // 关掉缓存定时清理(rust端)
  setHostCacheGcEnabled(enabled: false);

  setTlsVerifyEnabled(enabled: false);

  // Rust 已在本函数开头初始化；快照查询和 Brotli 压缩均在后台执行。
  unawaited(saveStartupDatabaseSnapshot());

  return (globalSettingCubit, pluginRegistryCubit);
}

Future<void> _tryApplyHttpProxyFromEnv() async {
  if (!kDebugMode) return;

  final rawProxy = await _readProxyFromEnvAsset();
  if (rawProxy == null || rawProxy.isEmpty) return;

  final proxyUrl =
      rawProxy.startsWith('http://') || rawProxy.startsWith('https://')
      ? rawProxy
      : 'http://$rawProxy';

  final reachable = await _probeProxyWithTimeout(proxyUrl);
  if (!reachable) return;

  setHttpProxy(proxy: proxyUrl);
}

/// 去掉代理地址的协议前缀，得到 `host:port`，供 Dart 侧 HttpClient 使用。
String _stripProxyScheme(String url) {
  var value = url.trim();
  for (final prefix in const ['https://', 'http://']) {
    if (value.startsWith(prefix)) {
      value = value.substring(prefix.length);
      break;
    }
  }
  return value;
}

Future<String?> _readProxyFromEnvAsset() async {
  try {
    final content = await rootBundle.loadString('.env.proxy');
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (!line.startsWith('proxy=')) continue;
      final value = line.substring('proxy='.length).trim();
      if (value.isNotEmpty) return value;
    }
  } catch (_) {
    return null;
  }
  return null;
}

Future<bool> _probeProxyWithTimeout(String proxyUrl) async {
  try {
    final response = await WindHttp(
      httpProxy: proxyUrl,
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      followRedirects: false,
    ).fetch('http://www.gstatic.com/generate_204');
    return response.status >= 200 && response.status < 500;
  } catch (_) {
    return false;
  }
}

Future<void> addArchitectureTagsToSentry() async {
  try {
    final is64Bit = sizeOf<Pointer>() == 8;
    final appArchitecture = is64Bit ? '64-bit' : '32-bit';

    String deviceSupportedAbis = 'unknown';

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      deviceSupportedAbis = androidInfo.supportedAbis.join(', ');
    } else if (Platform.isIOS) {
      final iosInfo = await DeviceInfoPlugin().iosInfo;
      deviceSupportedAbis = 'arm64 (${iosInfo.utsname.machine})';
    } else if (Platform.isWindows) {
      deviceSupportedAbis =
          Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'unknown';
    } else if (Platform.isLinux) {
      try {
        final result = Process.runSync('uname', ['-m']);
        deviceSupportedAbis = result.stdout.toString().trim();
      } catch (_) {
        deviceSupportedAbis = 'unknown';
      }
    } else if (Platform.isMacOS) {
      final macInfo = await DeviceInfoPlugin().macOsInfo;
      deviceSupportedAbis = macInfo.arch;
    }

    Sentry.configureScope((scope) {
      scope.setTag('app_runtime_arch', appArchitecture);
      scope.setTag('device_supported_abis', deviceSupportedAbis);

      scope.addBreadcrumb(
        Breadcrumb(
          message:
              'Architecture Info - App: $appArchitecture, Device: $deviceSupportedAbis',
          category: 'system.architecture',
        ),
      );
    });
  } catch (e, stack) {
    await Sentry.captureException(e, stackTrace: stack);
  }
}

class MyApp extends StatefulWidget with WindowListener {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp>
    with WindowListener, TrayListener, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.addListener(this);
      _init();
      WindowLogic.initWindow(context).then((_) {
        windowManager.setPreventClose(true);
      });
    }
    trayManager.addListener(this);
    initSystemTray();

    if (Platform.isLinux) {
      _linuxWindowChannel.setMethodCallHandler((call) async {
        if (call.method == 'windowCloseRequested') {
          _handleCloseRequest();
        }
      });
    }

    // 启动命名管道监听，用于接收外部退出信号（仅 Windows）
    if (Platform.isWindows) {
      rust_system.startShutdownListener().listen((shouldExit) {
        if (shouldExit) {
          _performGracefulExit();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowResized() {
    super.onWindowResized();
    WindowLogic.saveWindowState(context);
  }

  @override
  void onWindowMoved() {
    super.onWindowMoved();
    WindowLogic.saveWindowState(context);
  }

  @override
  void onWindowMaximize() {
    super.onWindowMaximize();
    WindowLogic.saveWindowStateImmediately(context);
  }

  @override
  void onWindowUnmaximize() {
    super.onWindowUnmaximize();
    WindowLogic.saveWindowStateImmediately(context);
  }

  /// 应用级退出请求不一定经过窗口关闭回调，退出前补存一次窗口状态。
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await WindowLogic.saveWindowStateImmediately(context);
    }
    return AppExitResponse.exit;
  }

  /// 立即隐藏窗口再退出，让用户感知不到 Dart VM 清理的延迟
  Future<void> _forceExit() async {
    await WindowLogic.saveWindowStateImmediately(context);
    // 强杀，降低延迟
    // nuclearKillProcess();
    if (Platform.isWindows) {
      NativeWindow.hide(); // 同步 Win32 调用，零延迟
    } else {
      windowManager.hide(); // 其他桌面平台
    }
    objectbox.close();
    nuclearKillProcess();
  }

  bool _handlingCloseRequest = false;

  static const MethodChannel _linuxWindowChannel = MethodChannel(
    'breeze/linux/window',
  );

  @override
  void onWindowClose() {
    _handleCloseRequest();
  }

  Future<void> _handleCloseRequest() async {
    if (_handlingCloseRequest) return;
    _handlingCloseRequest = true;
    try {
      final closeBehavior = await WindowLogic.loadCloseBehavior();
      switch (closeBehavior) {
        case DesktopCloseBehavior.hide:
          await _hideWindow();
          return;
        case DesktopCloseBehavior.close:
          await _forceExit();
          return;
        case DesktopCloseBehavior.ask:
          break;
      }

      if (Platform.isLinux) {
        await windowManager.show();
      }
      final dialogContext = appRouter.navigatorKey.currentContext;
      if (dialogContext == null || !dialogContext.mounted) {
        await _forceExit();
        return;
      }
      showDialog(
        context: dialogContext,
        builder: (context) {
          var rememberChoice = false;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('提示'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('隐藏到托盘或关闭程序'),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('记住我的选择'),
                      value: rememberChoice,
                      onChanged: (value) {
                        setDialogState(() {
                          rememberChoice = value ?? false;
                        });
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    child: const Text('取消'),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                  TextButton(
                    child: const Text('关闭'),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      if (rememberChoice) {
                        await WindowLogic.saveCloseBehavior(
                          DesktopCloseBehavior.close,
                        );
                      }
                      await _forceExit();
                    },
                  ),
                  TextButton(
                    child: const Text('隐藏'),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      if (rememberChoice) {
                        await WindowLogic.saveCloseBehavior(
                          DesktopCloseBehavior.hide,
                        );
                      }
                      await _hideWindow();
                    },
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      _handlingCloseRequest = false;
    }
  }

  /// 隐藏窗口到任务栏托盘，不退出程序
  Future<void> _hideWindow() async {
    await WindowLogic.saveWindowStateImmediately(context);
    if (Platform.isWindows) {
      NativeWindow.hide();
    } else {
      windowManager.hide();
    }
  }

  Future<void> _performGracefulExit() async {
    await _forceExit();
  }

  @override
  void onWindowFocus() {
    super.onWindowFocus();
    setState(() {});
  }

  @override
  void onTrayIconMouseDown() {
    showMainWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      showMainWindow();
    } else if (menuItem.key == 'exit_app') {
      // 真正退出：清理资源后退出
      _performGracefulExit();
    }
  }

  void _init() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await windowManager.setPreventClose(true);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return TranslationProvider(
      child: AnimatedBuilder(
        animation: FontProfileController.instance,
        builder: (context, _) {
          final globalSettingState = context.watch<GlobalSettingCubit>().state;

          return DynamicColorBuilder(
            builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
              ColorScheme lightColorScheme;
              ColorScheme darkColorScheme;

              if (globalSettingState.dynamicColor == true) {
                lightColorScheme =
                    lightDynamic ??
                    ColorScheme.fromSeed(
                      seedColor: globalSettingState.seedColor,
                      brightness: Brightness.light,
                    );
                darkColorScheme =
                    darkDynamic ??
                    ColorScheme.fromSeed(
                      seedColor: globalSettingState.seedColor,
                      brightness: Brightness.dark,
                    );
              } else {
                final primary = globalSettingState.seedColor;

                lightColorScheme = ColorScheme.fromSeed(
                  seedColor: primary,
                  brightness: Brightness.light,
                );
                darkColorScheme = ColorScheme.fromSeed(
                  seedColor: primary,
                  brightness: Brightness.dark,
                );
              }

              // 导入的 tweakcn / shadcn 主题：只把**它给了值**的槽位盖上去，
              // 其余仍走上面的 fromSeed / 动态取色。整套换掉 ColorScheme 不可行 ——
              // 全仓组件读的是 M3 角色名，而 shadcn 只有二十来个扁平 token。
              final tweakcn = globalSettingState.tweakcnThemeEnabled
                  ? TweakcnThemeLibrary.decode(
                      globalSettingState.tweakcnThemeJson,
                    ).activeTheme
                  : null;
              if (tweakcn != null) {
                lightColorScheme = tweakcn.apply(
                  lightColorScheme,
                  Brightness.light,
                );
                darkColorScheme = tweakcn.apply(
                  darkColorScheme,
                  Brightness.dark,
                );
              }
              // `--radius` 走 ThemeShapeScope 下去，玻璃与卡片自己按档位取；
              // 主题没给就是接进来之前的 16。
              final themeShapeRadius = tweakcn?.radius ?? kDefaultPanelRadius;

              final isLinuxDesktop = !kIsWeb && Platform.isLinux;
              const linuxFontFamily = 'Noto Sans CJK SC';
              const linuxFontFamilyFallback = <String>[
                'WenQuanYi Micro Hei',
                'Droid Sans Fallback',
              ];

              TextTheme withConfiguredFonts(TextTheme base) {
                var themed = base;
                if (isLinuxDesktop) {
                  themed = themed.apply(
                    fontFamily: linuxFontFamily,
                    fontFamilyFallback: linuxFontFamilyFallback,
                  );
                }
                return FontProfileController.instance.applyToTextTheme(themed);
              }

              return MaterialApp.router(
                routerConfig: appRouter.config(),
                scrollBehavior: const AppScrollBehavior(),
                builder: (context, child) {
                  Widget content = Actions(
                    actions: <Type, Action<Intent>>{
                      EscapeIntent: CallbackAction<EscapeIntent>(
                        onInvoke: (intent) {
                          // 先让当前焦点失焦，避免 pop 时 InputDecorator 才第一次变 dirty；
                          // 再把 pop 推迟到下一帧，让失焦引发的重建在当前帧完成。
                          FocusManager.instance.primaryFocus?.unfocus();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            appRouter.maybePop();
                          });
                          return null;
                        },
                      ),
                    },
                    child: Shortcuts(
                      shortcuts: <ShortcutActivator, Intent>{
                        const SingleActivator(LogicalKeyboardKey.escape):
                            const EscapeIntent(),
                      },
                      child: Focus(autofocus: true, child: child!),
                    ),
                  );

                  content = Listener(
                    onPointerDown: (PointerDownEvent event) {
                      if (event.buttons & kBackMouseButton != 0) {
                        appRouter.maybePop();
                      }
                    },
                    child: content,
                  );

                  if (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS) {
                    // 自制标题栏 + 内容。窗口全屏时标题栏整条让位 ——
                    // 判据是窗口自己的全屏事件，见 DesktopShellFrame。
                    // 透明开关打开后摆放再分两档：独立行（默认）/ 融合浮层。
                    content = DesktopShellFrame(
                      transparentTitleBar:
                          globalSettingState.transparentDesktopTitleBar,
                      titleBarFused:
                          globalSettingState.transparentTitleBarFused,
                      child: content,
                    );
                  }
                  // 第三方依赖仍有 legacy Material widget，需要这个桥接层提供旧主题
                  // 与本地化上下文；待依赖迁移后可移除。
                  // ignore: deprecated_member_use
                  return MaterialUiCompatibilityBridge(
                    // 主题形状放在最外层：玻璃 / 卡片在任意深度都能读到同一个基准圆角。
                    child: ThemeShapeScope(
                      radius: themeShapeRadius,
                      child: content,
                    ),
                  );
                },
                locale: TranslationProvider.of(context).flutterLocale,
                title: appDisplayName,
                themeMode: globalSettingState.themeMode,
                supportedLocales: AppLocaleUtils.supportedLocales,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: ThemeData.light().copyWith(
                  primaryColor: lightColorScheme.primary,
                  colorScheme: lightColorScheme,
                  scaffoldBackgroundColor: lightColorScheme.surface,
                  cardColor: lightColorScheme.surfaceContainer,
                  chipTheme: ChipThemeData(
                    backgroundColor: lightColorScheme.surface,
                  ),
                  canvasColor: lightColorScheme.surfaceContainer,
                  dialogTheme: DialogThemeData(
                    backgroundColor: lightColorScheme.surfaceContainer,
                  ),
                  textTheme: withConfiguredFonts(ThemeData.light().textTheme),
                  primaryTextTheme: withConfiguredFonts(
                    ThemeData.light().primaryTextTheme,
                  ),
                ),
                darkTheme: ThemeData.dark().copyWith(
                  scaffoldBackgroundColor: globalSettingState.isAMOLED
                      ? Colors.black
                      : darkColorScheme.surface,
                  tabBarTheme: const TabBarThemeData(
                    dividerColor: Colors.transparent,
                  ),
                  colorScheme: darkColorScheme,
                  textTheme: withConfiguredFonts(ThemeData.dark().textTheme),
                  primaryTextTheme: withConfiguredFonts(
                    ThemeData.dark().primaryTextTheme,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
