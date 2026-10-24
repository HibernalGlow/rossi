import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';
import 'package:path/path.dart' as p;

import 'cargo_target_dir.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final extraCargoEnvironmentVariables = _extraCargoEnvironmentVariables(
      input.config.code,
      input.packageRoot.toFilePath(),
    );

    await useSharedCargoTargetDirectory(input);

    await RustBuilder(
      buildMode: input.config.linkingEnabled
          ? BuildMode.release
          : BuildMode.debug,
      assetName: 'src/rust/frb_generated.dart',
      extraCargoEnvironmentVariables: extraCargoEnvironmentVariables,
    ).run(input: input, output: output);
  });
}

Map<String, String> _extraCargoEnvironmentVariables(
  CodeConfig codeConfig,
  String projectRoot,
) {
  if (codeConfig.targetOS == OS.iOS) {
    return _iosEnvironmentVariables(codeConfig, projectRoot);
  }
  if (codeConfig.targetOS == OS.android) {
    return _androidEnvironmentVariables(codeConfig, projectRoot);
  }
  return _hostEnvironmentVariables();
}

/// 宿主平台（Windows / macOS / Linux）：把**构建前置**显式交给 cargo。
///
/// 为什么必须显式：hook 是 Flutter 工具另起的进程，环境不保证与终端一致。
/// 实测（2026-09-16）：`cargo build -p windcore --target x86_64-pc-windows-msvc`
/// 在终端里编得过，同一命令在 native assets 构建里却挂在 `dav1d-sys` 的 build.rs
/// —— `image` 的 `avif-native` 要经 pkg-config 找 dav1d，而 pkg-config 看不见
/// `PKG_CONFIG_PATH` 就只能失败。**不赌「环境会继承」，把要用的写明白。**
///
/// 变量本身仍由构建环境提供（`docs/windows-build/win-baseline-env.sh` 负责 export），
/// 这里只做透传 —— 仓库里不出现任何机器绝对路径。
Map<String, String> _hostEnvironmentVariables() {
  // `PKG_CONFIG_ALLOW_CROSS` 必须在列：macOS 的 x64 job（Intel runner）上，
  // hook 实际按 aarch64-apple-darwin 出货，dav1d-sys 的 pkg-config 探测因此判定为交叉并直接拒答
  // （PkgConfig(pkg-config has not been configured to support cross-compilation.)）。
  // 而 CI 里把它写进 $GITHUB_ENV 是无效的 —— hook 子进程环境是干净的，只有这里透传得到的才会进 cargo。
  const passthrough = [
    'PKG_CONFIG_PATH',
    'PKG_CONFIG',
    'PKG_CONFIG_ALLOW_CROSS',
    'VCPKG_ROOT',
  ];
  final env = <String, String>{
    // 这一条不是透传，是**注入**：安卓分支那条 `CARGO_PROFILE_DEV_STRIP: 'none'` 的宿主版。
    // cargo 的 release 默认往 rustc 传 `-C strip=debuginfo`，rustc 进程内重写 Mach-O 时会把
    // LINKEDIT 的字符串池落在 4 字节偏移上（`rquickjs-macro` 那个 proc-macro dylib 实测如此），
    // 而 macOS 27 的 dyld 要求 8 字节对齐 —— 拒载之后 rustc 只报一句 `E0463: can't find crate
    // for rquickjs_macro`，看不到 dlopen。2026-10-03 单变量对照（同一 `--package windcore` 图，
    // 只换这个开关）：默认档 stroff mod8=4、编不过；none 后 mod8=0、windcore 编完。
    // 代价是宿主 release 的 Rust 静态库留着符号（`.a` 201MB，dev 是 242MB）。
    'CARGO_PROFILE_RELEASE_STRIP': 'none',
  };
  for (final key in passthrough) {
    final value = Platform.environment[key];
    if (value != null && value.isNotEmpty) {
      env[key] = value;
    }
  }
  if (Platform.isMacOS && !env.containsKey('PKG_CONFIG_PATH')) {
    const brewPkgConfig = '/opt/homebrew/lib/pkgconfig';
    if (Directory(brewPkgConfig).existsSync()) {
      env['PKG_CONFIG_PATH'] = brewPkgConfig;
    }
  }
  // 打点：这个构建前置在 CI 上最容易缺，出问题时要能一眼看出它当时是什么。
  stderr.writeln(
    '[rossi-hook] 构建前置 -> cargo: '
    '${env.isEmpty ? '(全部缺失，涉及 pkg-config 的 crate 会失败)' : env}',
  );
  return env;
}

// ────────────────────────── iOS ──────────────────────────

Map<String, String> _iosEnvironmentVariables(
  CodeConfig codeConfig,
  String projectRoot,
) {
  final sdk = switch (codeConfig.iOS.targetSdk) {
    IOSSdk.iPhoneOS => 'iphoneos',
    IOSSdk.iPhoneSimulator => 'iphonesimulator',
    final other => throw UnsupportedError('Unsupported iOS SDK: $other'),
  };

  final targetTriple = switch ((codeConfig.targetArchitecture, sdk)) {
    (Architecture.arm64, 'iphoneos') => 'aarch64-apple-ios',
    (Architecture.arm64, 'iphonesimulator') => 'aarch64-apple-ios-sim',
    (Architecture.x64, 'iphonesimulator') => 'x86_64-apple-ios',
    final other => throw UnsupportedError(
      'Unsupported iOS target combination: $other',
    ),
  };

  final linker = _runXcrun(['--sdk', sdk, '--find', 'clang']);
  final sdkRoot = _runXcrun(['--sdk', sdk, '--show-sdk-path']);
  final targetTripleEnv = targetTriple.replaceAll('-', '_').toUpperCase();
  final deploymentTarget = codeConfig.iOS.targetVersion.toString();
  final minimumVersionFlag = switch (sdk) {
    'iphoneos' => '-miphoneos-version-min=$deploymentTarget',
    'iphonesimulator' => '-mios-simulator-version-min=$deploymentTarget',
    final other => throw UnsupportedError('Unsupported iOS SDK: $other'),
  };
  final cFlags = '$minimumVersionFlag -isysroot $sdkRoot';
  final rustFlags = '-C link-arg=$minimumVersionFlag';

  final env = <String, String>{
    'SDKROOT': sdkRoot,
    'IPHONEOS_DEPLOYMENT_TARGET': deploymentTarget,
    'CARGO_TARGET_${targetTripleEnv}_LINKER': linker,
    'CARGO_TARGET_${targetTripleEnv}_RUSTFLAGS': rustFlags,
    'RUSTFLAGS': rustFlags,
    'CFLAGS_$targetTripleEnv': cFlags,
    'CXXFLAGS_$targetTripleEnv': cFlags,
    'CC': linker,
    'CXX': linker,
    'LD': linker,
  };

  // dav1d 是给 iOS 交叉编出来的静态库，`image` 的 avif-native 要经 pkg-config 找它。
  // Xcode 的 Run Script 拉起的 hook 子进程环境是干净的，CI 在步骤级 export 的
  // PKG_CONFIG_* 进不来（实测 run 40093260465：dav1d 已装进 ios_sysroot，
  // dav1d-sys 的 build.rs 仍然失败）。与安卓分支同一口径：目录在就把三件写明白。
  final sysrootPkgConfig = p.join(
    projectRoot,
    'third_party',
    'ios_sysroot',
    targetTriple,
    'lib',
    'pkgconfig',
  );
  if (Directory(sysrootPkgConfig).existsSync()) {
    env['PKG_CONFIG_LIBDIR'] = sysrootPkgConfig;
    env['PKG_CONFIG_PATH'] = sysrootPkgConfig;
    env['PKG_CONFIG_ALLOW_CROSS'] = '1';
  }

  // rquickjs-sys 的 bindgen 会把 Rust target triple 直接传给 clang；
  // aarch64-apple-ios-sim 不被 clang 识别，需要额外指定它能识别的 triple。
  if (targetTriple == 'aarch64-apple-ios-sim') {
    env['BINDGEN_EXTRA_CLANG_ARGS'] = '--target=aarch64-apple-ios-simulator';
  }

  return env;
}

String _runXcrun(List<String> arguments) {
  final result = Process.runSync('xcrun', arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      'xcrun',
      arguments,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }

  return (result.stdout as String).trim();
}

// ────────────────────────── Android ──────────────────────────

Map<String, String> _androidEnvironmentVariables(
  CodeConfig codeConfig,
  String projectRoot,
) {
  final ndkVersion = _readNdkVersion(projectRoot);
  final ndkPath = _findNdkPath(ndkVersion);
  final hostPlatform = _hostPlatform();
  final llvmBase = p.join(
    ndkPath,
    'toolchains',
    'llvm',
    'prebuilt',
    hostPlatform,
  );
  final clangBinary = p.join(llvmBase, 'bin', 'clang${_exeSuffix()}');
  final sysroot = p.join(llvmBase, 'sysroot');
  final ndkTargetTriple = _ndkTargetTriple(codeConfig.targetArchitecture);
  final clangVersion = _detectClangVersion(llvmBase);

  final bindgenArgs = [
    '--sysroot=${sysroot.replaceAll('\\', '/')}',
    '-isystem ${p.join(sysroot, 'usr', 'include').replaceAll('\\', '/')}',
    if (ndkTargetTriple case final t?)
      '-isystem ${p.join(sysroot, 'usr', 'include', t).replaceAll('\\', '/')}',
    if (clangVersion case final v?)
      '-isystem ${p.join(llvmBase, 'lib', 'clang', v, 'include').replaceAll('\\', '/')}',
  ].join(' ');

  // 安卓交叉编译额外要交代给 cargo 的三件事。都在**安卓这一支**里给，
  // 宿主分支一个字不动（那三样在那边要么不需要、要么会带歪）。
  final env = <String, String>{
    'CLANG_PATH': clangBinary.replaceAll('\\', '/'),
    'LIBCLANG_PATH': _libClangPath(llvmBase).replaceAll('\\', '/'),
    'BINDGEN_EXTRA_CLANG_ARGS': bindgenArgs,
    'PATH':
        '${p.join(llvmBase, 'bin')}${_pathSep()}${Platform.environment['PATH'] ?? ''}',
    ..._androidExtraCargoEnv(codeConfig, projectRoot),
  };
  return env;
}

/// 安卓构建要额外交代的三件事（2026-10-02 逐条实测出来的代价，见
/// `docs/android-build.md`）：
///
/// 1. **`PKG_CONFIG_LIBDIR` 指向交叉编出来的 dav1d**。`image` 的 `avif-native`
///    经 pkg-config 找 dav1d，而 hook 子进程的环境是干净的（宿主分支那份透传就是
///    为这个存在的），交叉探测还额外要求 `PKG_CONFIG_ALLOW_CROSS` —— 少了任意一个，
///    `dav1d-sys` 的 build.rs 直接 `pkg-config has not been configured to support
///    cross-compilation`。用 `LIBDIR` 而不是 `PATH` 是刻意的：`PATH` 是**追加**系统
///    搜索路径，brew 那份宿主的 `dav1d.pc` 仍会被命中，交叉链接会拿 macOS 的
///    dylib 去喂 ELF 链接器。目录不存在时（没跑过
///    `third_party/build_dav1d_android.sh` 的机器）不设，让失败停在原地。
/// 2. **`CXXFLAGS_<triple>` 里那一个宏**：vendored unrar 的 `ulinks.cpp` 在
///    `__linux` 下用 `lutimes`，而 bionic 没有这个函数；定义 `UNIX_TIME_NS` 就走它
///    自己写好的 `utimensat` 分支。补丁进不了 vendor（那是 submodule）。
/// 3. **关掉 dev profile 的 strip**：`rust-toolchain.toml` 钉的 1.96.1 在这台
///    macOS 27 上会把 `rquickjs-macro` 那个 proc-macro dylib 改写成 dyld 拒载的
///    Mach-O，而 rustc 把它报成 `E0463: can't find crate for rquickjs_macro` ——
///    一句 dlopen 的影子都没有。同工具链 `strip=none` 与 1.98.1 默认都可载。
Map<String, String> _androidExtraCargoEnv(
  CodeConfig codeConfig,
  String projectRoot,
) {
  final triple = _rustAndroidTriple(codeConfig.targetArchitecture);
  final env = <String, String>{
    'CXXFLAGS_${triple.replaceAll('-', '_')}': '-DUNIX_TIME_NS',
    'CARGO_PROFILE_DEV_STRIP': 'none',
    // release 构建要关同一条：`--release` 下 cargo 默认带 `-C strip=debuginfo`，
    // 在这台 macOS 的 1.96.1 上是同一个 Mach-O 改写问题（症状同为 E0463，
    // `dart ./script/build_apk.dart` 与 `flutter build apk --release` 各撞一次）。
    // 只在本机加：CI 的 release 产物在 Linux 上搬，那边 strip 正常，
    // 不为本机把出货的 .so 撑大。
    if (Platform.isMacOS) 'CARGO_PROFILE_RELEASE_STRIP': 'none',
  };
  final sysrootPkgConfig = p.join(
    projectRoot,
    'third_party',
    'android_sysroot',
    triple,
    'lib',
    'pkgconfig',
  );
  if (Directory(sysrootPkgConfig).existsSync()) {
    env['PKG_CONFIG_LIBDIR'] = sysrootPkgConfig;
    env['PKG_CONFIG_PATH'] = sysrootPkgConfig;
    env['PKG_CONFIG_ALLOW_CROSS'] = '1';
  } else {
    stderr.writeln(
      '[rossi-hook] 没找到 $sysrootPkgConfig：dav1d 会退回它自己的 meson 兜底'
      '（那会编出宿主架构，交叉链接时才炸）。先跑 '
      'third_party/build_dav1d_android.sh。',
    );
  }
  return env;
}

/// Rust 侧的安卓三元组。
///
/// 不从 `CodeConfig` 上读：`code_assets`（2.0.0）只给 `targetOS` +
/// `targetArchitecture`，没有现成的三元组字段；这里按 Rust 的命名给
/// （注意 arm 那边是 `armv7-linux-androideabi`，与 NDK 的 `arm-linux-androideabi`
/// **不同名** —— 上面 `_ndkTargetTriple` 给的是 NDK 那一套，两边不能互相代用）。
String _rustAndroidTriple(Architecture architecture) {
  return switch (architecture) {
    Architecture.arm64 => 'aarch64-linux-android',
    Architecture.arm => 'armv7-linux-androideabi',
    Architecture.x64 => 'x86_64-linux-android',
    Architecture.ia32 => 'i686-linux-android',
    _ => throw UnsupportedError('Unsupported Android architecture: $architecture'),
  };
}

String _libClangPath(String llvmBase) {
  if (Platform.isWindows) {
    return p.join(llvmBase, 'bin');
  }
  final lib64 = Directory(p.join(llvmBase, 'lib64'));
  if (lib64.existsSync()) {
    return p.join(llvmBase, 'lib64');
  }
  return p.join(llvmBase, 'lib');
}

String _pathSep() => Platform.isWindows ? ';' : ':';

String? _readNdkVersion(String projectRoot) {
  final gradleFile = File(
    p.join(projectRoot, 'android', 'app', 'build.gradle.kts'),
  );
  if (!gradleFile.existsSync()) return null;
  final match = RegExp(
    r'ndkVersion\s*=\s*"([^"]+)"',
  ).firstMatch(gradleFile.readAsStringSync());
  return match?.group(1);
}

String _findNdkPath(String? ndkVersion) {
  if (ndkVersion != null) {
    final envNdk = Platform.environment['ANDROID_NDK_HOME'];
    if (envNdk != null && Directory(envNdk).existsSync()) return envNdk;

    final sdkRoot =
        Platform.environment['ANDROID_SDK_ROOT'] ??
        Platform.environment['ANDROID_HOME'];
    if (sdkRoot != null) {
      final path = p.join(sdkRoot, 'ndk', ndkVersion);
      if (Directory(path).existsSync()) return path;
    }

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (Platform.isWindows && localAppData != null) {
      final path = p.join(localAppData, 'Android', 'Sdk', 'ndk', ndkVersion);
      if (Directory(path).existsSync()) return path;
    }

    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null) {
      final path = p.join(home, 'Android', 'Sdk', 'ndk', ndkVersion);
      if (Directory(path).existsSync()) return path;
    }
  }

  throw StateError(
    'Cannot find Android NDK. '
    'Set ANDROID_NDK_HOME or ANDROID_HOME environment variable.',
  );
}

String _hostPlatform() {
  if (Platform.isWindows) return 'windows-x86_64';
  if (Platform.isMacOS) return 'darwin-x86_64';
  return 'linux-x86_64';
}

String? _ndkTargetTriple(Architecture arch) {
  return switch (arch) {
    Architecture.arm64 => 'aarch64-linux-android',
    Architecture.arm => 'arm-linux-androideabi',
    Architecture.x64 => 'x86_64-linux-android',
    Architecture.ia32 => 'i686-linux-android',
    _ => null,
  };
}

String? _detectClangVersion(String llvmBase) {
  final clangDir = Directory(p.join(llvmBase, 'lib', 'clang'));
  if (!clangDir.existsSync()) return null;
  for (final entity in clangDir.listSync()) {
    if (entity is Directory &&
        RegExp(r'^\d+').hasMatch(p.basename(entity.path))) {
      return p.basename(entity.path);
    }
  }
  return null;
}

String _exeSuffix() => Platform.isWindows ? '.exe' : '';
