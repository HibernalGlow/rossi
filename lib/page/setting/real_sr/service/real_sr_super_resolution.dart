import 'dart:io';
import 'dart:ui' as ui;

import 'package:coreml_upscale/coreml_upscale.dart';
import 'package:zephyr/util/coreml_model_loader.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_log.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';
import 'package:uuid/uuid.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_info/method/export_comic.dart';
import 'package:zephyr/page/setting/real_sr/service/android_ncnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/android_qnn_engine.dart';
import 'package:zephyr/page/setting/real_sr/service/android_qnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/android_sr_engine.dart';
import 'package:zephyr/page/setting/real_sr/service/android_upscale_engines.dart';
import 'package:zephyr/page/setting/real_sr/service/desktop_ncnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_book_scope.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/image_denoise_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/image_denoise_pipeline.dart';
import 'package:zephyr/page/setting/real_sr/service/upscaled_image_cache.dart';
import 'package:zephyr/page/setting/real_sr/service/mimage_onnx_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_policy_service.dart';
import 'package:zephyr/page/setting/real_sr/service/sr_session_guard.dart';
import 'package:zephyr/reader/page_animation.dart';
import 'package:zephyr/src/rust/api/image.dart';
import 'package:zephyr/src/rust/api/mimage_onnx.dart';
import 'package:zephyr/src/rust/api/simple.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// Breeze 内置 RealSR / Real-CUGAN / CoreML 超分封装
///
/// - Android：调用 bundled 的 waifu2x-ncnn CLI
/// - iOS / macOS：Breeze 原生 Swift/CoreML 与 mImage ONNX/CoreML 可切换
/// - Windows / Linux：从 `deretame/breeze-binary` 下载模型后，
///   调用 `getFilePath()/super_resolution/` 下的 waifu2x-ncnn-vulkan
///   或 realcugan-ncnn-vulkan
class RealSrSuperResolution {
  RealSrSuperResolution._();

  /// GitHub 上存放桌面端模型压缩包的仓库。
  static const String _binaryRepoBaseUrl =
      'https://github.com/deretame/breeze-binary/raw/main';

  /// 最大并发超分任务数。
  ///
  /// - 桌面端（Windows / Linux / macOS）默认 2，高端显卡可设更高。
  /// - 移动设备（Android / iOS）默认 1，避免 OOM / 发热。
  ///
  /// 修改后会立即影响新任务，已在执行的任务不受影响。
  static int get maxConcurrency {
    if (_maxConcurrency != null) return _maxConcurrency!;
    return RealSrSettings.defaultConcurrency;
  }

  static set maxConcurrency(int value) {
    if (value < 1) {
      throw ArgumentError.value(value, 'maxConcurrency', 'must be >= 1');
    }
    _maxConcurrency = value;
    _pool = Pool(value);
  }

  static int? _maxConcurrency;
  static Pool _pool = Pool(maxConcurrency);

  /// 桌面端模型下载/解压目录：`<getFilePath()>/super_resolution`
  static Future<String> get _modelDirectory async {
    return p.join(await getFilePath(), 'super_resolution');
  }

  /// 当前设备是否支持内置超分（包含模型/可执行文件是否已就绪）。
  ///
  /// - Android：按**当前选中的引擎**判据 —— Vulkan 看内置 CLI 的 NCNN 模型
  ///   是否下载就绪；QNN NPU 看 HTP 运行时 + 所选 DLC 是否就绪
  /// - 其余平台：按**当前选中的引擎**判据 —— CoreML 看原生模型、mImage ONNX 看
  ///   `.onnx` 文件、桌面 NCNN 看对应可执行文件是否在位
  static Future<bool> get isAvailable async {
    if (Platform.isAndroid) {
      try {
        if (!await isDeviceSupported) return false;
        final engine = await RealSrSettings.loadAndroidEngine();
        if (engine == AndroidSuperResolutionEngine.qnnNpu) {
          final model = await RealSrSettings.loadAndroidQnnModel();
          return await AndroidQnnEngine.isSupported &&
              await AndroidQnnEngine.isModelDownloaded(model);
        }
        return await _isAndroidNcnnAvailable(
          variant: AndroidNcnnModelConfig.variantFor(
            mode: AndroidNcnnModelConfig.defaultMode,
            noise: AndroidNcnnModelConfig.defaultNoise,
          ),
        );
      } catch (_) {
        return false;
      }
    }

    if (hasSuperResolutionEngineChoice) {
      return isProfileAvailable(await RealSrSettings.loadProfile());
    }

    return false;
  }

  /// 当前设备平台是否支持超分（不检查模型是否已下载）。
  ///
  /// 用于在设置页显示入口；Android 仅要求 arm64-v8a，其他平台默认支持。
  static Future<bool> get isDeviceSupported async {
    if (Platform.isAndroid) {
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        return androidInfo.supportedAbis.contains('arm64-v8a');
      } catch (_) {
        return false;
      }
    }

    if (Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux) {
      return true;
    }

    return false;
  }

  /// 检查 Android NCNN 模型是否已就绪。
  static Future<bool> _isAndroidNcnnAvailable({
    required NcnnModelVariant variant,
  }) async {
    final modelRoot = await _modelDirectory;
    final modelDir = p.join(modelRoot, variant.modelDir);
    final modelFiles = _androidModelFilesFor(variant);
    for (final relative in modelFiles) {
      if (!File(p.join(modelDir, relative)).existsSync()) {
        return false;
      }
    }
    return true;
  }

  /// 返回指定 Android NCNN 变体所需的模型文件相对路径列表。
  static List<String> _androidModelFilesFor(NcnnModelVariant variant) {
    final modelDir = variant.modelDir.toLowerCase();
    final isWaifu2x =
        modelDir.contains('models-cunet') || modelDir.contains('models-upconv');

    if (!isWaifu2x) {
      final suffix = variant.noise == -1
          ? 'conservative'
          : variant.noise == 0
          ? 'no-denoise'
          : 'denoise${variant.noise}x';
      return [
        'up${variant.scale}x-$suffix.param',
        'up${variant.scale}x-$suffix.bin',
      ];
    }

    if (isWaifu2x) {
      if (variant.noise == -1) {
        return ['scale2.0x_model.param', 'scale2.0x_model.bin'];
      }
      if (variant.scale == 1) {
        return [
          'noise${variant.noise}_model.param',
          'noise${variant.noise}_model.bin',
        ];
      }
      return [
        'noise${variant.noise}_scale2.0x_model.param',
        'noise${variant.noise}_scale2.0x_model.bin',
      ];
    }

    return [];
  }

  static Future<bool> isMImageModelAvailable([
    MImageOnnxModel? targetModel,
  ]) async {
    final root = Directory(p.join(await _modelDirectory, 'mimage_onnx'));
    final model = targetModel ?? await RealSrSettings.loadMImageModel();
    final file = File(p.join(root.path, model.fileName));
    return file.existsSync() && await file.length() >= 1024;
  }

  static Future<bool> isDenoiseModelAvailable() =>
      ImageDenoisePipeline.isAvailable();

  static Future<void> downloadDenoiseModel({
    void Function(int received, int total)? onProgress,
    bool force = false,
  }) => ImageDenoisePipeline.download(onProgress: onProgress, force: force);

  static Future<bool> denoise({
    required String inputPath,
    required String outputPath,
    int? tileSize,
    ImageDenoiseOptions? options,
    bool Function()? shouldRun,
  }) => ImageDenoisePipeline.process(
    inputPath: inputPath,
    outputPath: outputPath,
    tileSize: tileSize,
    options: options,
    shouldRun: shouldRun,
    withResource: (work) => _pool.withResource(work),
  );

  static Future<bool> isProfileAvailable(SuperResolutionProfile profile) =>
      switch (profile.engine) {
        SuperResolutionEngine.breezeCoreML =>
          CoreMLModelLoader.isModelAvailable(profile.coremlVariant.fileName),
        SuperResolutionEngine.mimageOnnx => isMImageModelAvailable(
          profile.mimageModel,
        ),
        SuperResolutionEngine.desktopNcnn => _isDesktopNcnnAvailable(),
      };

  /// 桌面 NCNN 路线的就绪判据：所选模式对应的可执行文件在位。
  static Future<bool> _isDesktopNcnnAvailable() async {
    final modelRoot = await _modelDirectory;
    final mode = await RealSrSettings.loadDesktopNcnnMode();
    final exeName = DesktopNcnnModelConfig.executableNameFor(mode);
    return File(p.join(modelRoot, exeName)).existsSync();
  }

  /// 当前选择是否需要「一个 `.onnx` 模型文件」而不是桌面 NCNN 的 7z 包。
  ///
  /// 判据是**引擎**而不是平台：Windows / Linux 现在两种都有。异步路径一律走这个
  /// （真的去读引擎设置）；同步 getter 只能吃 [RealSrSettings.currentEngine] 快照。
  static Future<bool> get _usesOnnxModel async =>
      supportsMImageOnnx &&
      await RealSrSettings.loadEngine() == SuperResolutionEngine.mimageOnnx;

  static bool get _usesOnnxModelFromSnapshot =>
      supportsMImageOnnx &&
      RealSrSettings.currentEngine == SuperResolutionEngine.mimageOnnx;

  /// 当前选择的 Android 引擎是否走 QNN NPU（异步路径，真读引擎设置）。
  static Future<bool> get _usesAndroidQnn async =>
      Platform.isAndroid &&
      await RealSrSettings.loadAndroidEngine() ==
          AndroidSuperResolutionEngine.qnnNpu;

  static bool get _usesAndroidQnnFromSnapshot =>
      Platform.isAndroid &&
      RealSrSettings.currentAndroidEngine ==
          AndroidSuperResolutionEngine.qnnNpu;

  /// 当前平台对应的 7z 压缩包文件名。
  static String? get _assetName {
    if (Platform.isAndroid) {
      // QNN 引擎的模型包与 NCNN 的分开（不同托管仓库、不同内容）。
      return _usesAndroidQnnFromSnapshot
          ? AndroidQnnModelConfig.archiveName
          : 'realsr-android.7z';
    }
    if (Platform.isWindows) return 'realsr-win.7z';
    if (Platform.isLinux) return 'realsr-linux.7z';
    return null;
  }

  static Future<String?> get _assetDownloadUrl async {
    if (await _usesOnnxModel) {
      final model = await RealSrSettings.loadMImageModel();
      return '${MImageOnnxModelConfig.baseUrl}/${model.fileName}';
    }
    if (await _usesAndroidQnn) return AndroidQnnModelConfig.archiveUrl;
    final assetName = _assetName;
    if (assetName == null) return null;
    return '$_binaryRepoBaseUrl/$assetName';
  }

  /// 当前平台手动下载模型的直链（可在浏览器中打开）。
  ///
  /// - mImage ONNX 引擎：当前选择的模型文件（`.onnx`）
  /// - Android QNN 引擎：`realsr-qnn-android.7z`
  /// - Android Vulkan / Windows / Linux 的桌面 NCNN 引擎：对应平台的 7z
  static String? get manualDownloadUrl {
    if (_usesOnnxModelFromSnapshot) {
      final model = RealSrSettings.currentMImageModel;
      return '${MImageOnnxModelConfig.baseUrl}/${model.fileName}';
    }
    if (_usesAndroidQnnFromSnapshot) return AndroidQnnModelConfig.archiveUrl;
    final assetName = _assetName;
    if (assetName == null) return null;
    return '$_binaryRepoBaseUrl/$assetName';
  }

  /// 7z 文件魔数（6 字节）。
  static const List<int> _sevenZSignature = [
    0x37,
    0x7A,
    0xBC,
    0xAF,
    0x27,
    0x1C,
  ];

  /// 校验文件是否为有效的 7z 压缩包（仅检查头部魔数）。
  static Future<bool> isSevenZArchive(File file) async {
    try {
      if (!file.existsSync()) return false;
      final raf = await file.open();
      try {
        final bytes = await raf.read(_sevenZSignature.length);
        if (bytes.length < _sevenZSignature.length) return false;
        for (var i = 0; i < _sevenZSignature.length; i++) {
          if (bytes[i] != _sevenZSignature[i]) return false;
        }
        return true;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// 导入单个 mImage ONNX 模型文件。
  static Future<void> importMImageModel(
    String filePath,
    MImageOnnxModel model,
  ) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('模型文件不存在', filePath);
    }
    if (p.basename(filePath) != model.fileName) {
      throw FormatException(
        t.realSr.modelFileNameMismatch(
          expected: model.fileName,
          actual: p.basename(filePath),
        ),
      );
    }
    final length = await file.length();
    if (length < 1024) {
      throw const FormatException('模型文件损坏或大小异常');
    }

    final destDir = Directory(p.join(await _modelDirectory, 'mimage_onnx'));
    await destDir.create(recursive: true);
    final target = File(p.join(destDir.path, model.fileName));
    final tempTarget = File(
      p.join(destDir.path, '${model.fileName}.tmp_${const Uuid().v4()}'),
    );
    await file.copy(tempTarget.path);
    await tempTarget.rename(target.path);

    await RealSrSettings.modelFileChanged(model);
    _missingModelNotified = false;
  }

  /// 导入本地手动下载的 7z 模型压缩包。
  ///
  /// 会先校验 7z 格式与当前平台所需的模型内容，全部通过后替换本地模型。
  static Future<void> importModelArchive(String archivePath) async {
    final archiveFile = File(archivePath);
    if (!archiveFile.existsSync()) {
      throw FileSystemException('模型压缩包不存在', archivePath);
    }
    if (!await isSevenZArchive(archiveFile)) {
      throw const FormatException('不是有效的 7z 压缩包');
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'breeze_realsr_import_',
    );
    try {
      try {
        await decompress7Z(archivePath: archivePath, destPath: tempDir.path);
      } catch (e, s) {
        logger.w('手动导入：7z 解压失败', error: e, stackTrace: s);
        throw const FormatException('7z 压缩包已损坏或解压失败');
      }

      final missing = await _missingModelFiles(tempDir);
      if (missing != null) {
        throw FormatException(
          t.realSr.archiveContentMismatch(missing: missing),
        );
      }

      if (await _usesOnnxModel) {
        final model = await RealSrSettings.loadMImageModel();
        File? imported;
        for (final entity in Directory(
          tempDir.path,
        ).listSync(recursive: true)) {
          if (entity is File && p.basename(entity.path) == model.fileName) {
            imported = entity;
            break;
          }
        }
        if (imported == null) {
          throw FormatException(
            t.realSr.archiveMissingOnnx(file: model.fileName),
          );
        }
        final destDir = Directory(p.join(await _modelDirectory, 'mimage_onnx'));
        await destDir.create(recursive: true);
        await imported.copy(p.join(destDir.path, model.fileName));
      } else {
        final destDir = await _modelDirectory;
        if (Directory(destDir).existsSync()) {
          await Directory(destDir).delete(recursive: true);
        }
        await Directory(p.dirname(destDir)).create(recursive: true);
        await _moveDirectory(tempDir, Directory(destDir));
      }

      // Linux / macOS 需要给可执行文件授权
      if (Platform.isLinux || Platform.isMacOS) {
        final modelRoot = await _modelDirectory;
        for (final name in ['realcugan-ncnn-vulkan', 'waifu2x-ncnn-vulkan']) {
          final exe = p.join(modelRoot, name);
          try {
            await Process.run('chmod', ['+x', exe], runInShell: false);
          } catch (e, s) {
            logger.w('RealSR 可执行文件授权失败: $exe', error: e, stackTrace: s);
          }
        }
      }

      _missingModelNotified = false;
    } finally {
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  /// 检查解压后的内容是否满足当前**引擎**需求，返回缺失内容描述；null 表示通过。
  static Future<String?> _missingModelFiles(Directory extractedRoot) async {
    // ONNX 判在最前：Windows / Linux 上两条引擎共用这个导入入口，按平台判的话
    // 选了 mImage ONNX 的用户会被要求交出 ncnn 可执行文件，反过来也一样。
    if (await _usesOnnxModel) {
      final model = await RealSrSettings.loadMImageModel();
      final path = p.join(extractedRoot.path, model.fileName);
      if (File(path).existsSync()) return null;
      for (final entity in extractedRoot.listSync(recursive: true)) {
        if (entity is File && p.basename(entity.path) == model.fileName) {
          return null;
        }
      }
      return t.realSr.missingOnnxModel(file: model.fileName);
    }

    if (Platform.isAndroid) {
      // QNN 引擎要的是 `qnn/<model>.dlc` + manifest；Vulkan 引擎要的是 NCNN 模型目录。
      if (await _usesAndroidQnn) {
        final model = await RealSrSettings.loadAndroidQnnModel();
        final dlcPath = p.join(
          extractedRoot.path,
          AndroidQnnModelConfig.dlcDirName,
          '${model.id}.dlc',
        );
        if (!File(dlcPath).existsSync()) {
          return t.realSr.missingQnnModel(file: '${model.id}.dlc');
        }
        if (!File(
          p.join(
            extractedRoot.path,
            AndroidQnnModelConfig.dlcDirName,
            'manifest.json',
          ),
        ).existsSync()) {
          return t.realSr.missingQnnManifest;
        }
        return null;
      }

      final variant = AndroidNcnnModelConfig.variantFor(
        mode: AndroidNcnnModelConfig.defaultMode,
        noise: AndroidNcnnModelConfig.defaultNoise,
      );
      final modelDir = Directory(p.join(extractedRoot.path, variant.modelDir));
      if (!modelDir.existsSync()) {
        return t.realSr.missingModelDir(dir: variant.modelDir);
      }
      for (final relative in _androidModelFilesFor(variant)) {
        if (!File(p.join(modelDir.path, relative)).existsSync()) {
          return t.realSr.missingModelFile(
            file: p.join(variant.modelDir, relative),
          );
        }
      }
      return null;
    }

    if (Platform.isWindows || Platform.isLinux) {
      final suffix = Platform.isWindows ? '.exe' : '';
      const exes = ['realcugan-ncnn-vulkan', 'waifu2x-ncnn-vulkan'];
      final hasExecutable = exes.any(
        (name) => File(p.join(extractedRoot.path, '$name$suffix')).existsSync(),
      );
      if (!hasExecutable) {
        return t.realSr.missingExecutable;
      }
      const modelDirs = [
        'models-pro',
        'models-se',
        'models-upconv_7_anime_style_art_rgb',
      ];
      final hasModelDir = modelDirs.any(
        (name) => Directory(p.join(extractedRoot.path, name)).existsSync(),
      );
      if (!hasModelDir) {
        return t.realSr.missingModelDirs;
      }
      return null;
    }

    return t.realSr.manualImportUnsupported;
  }

  /// 把目录移动到目标位置；跨磁盘/分区失败时退回复制后删除。
  static Future<void> _moveDirectory(Directory from, Directory to) async {
    try {
      await from.rename(to.path);
    } on FileSystemException {
      await to.create(recursive: true);
      await _copyDirectoryContents(from, to);
      await from.delete(recursive: true);
    }
  }

  static Future<void> _copyDirectoryContents(
    Directory from,
    Directory to,
  ) async {
    await for (final entity in from.list()) {
      final targetPath = p.join(to.path, p.basename(entity.path));
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
        await _copyDirectoryContents(entity, Directory(targetPath));
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }

  /// 下载并解压当前平台需要的超分模型。
  ///
  /// - mImage ONNX 引擎：直接下载当前选择的 `.onnx` 模型文件
  /// - Android / 桌面 NCNN 引擎：下载对应平台的 7z 压缩包
  ///
  /// [force] 为 true 时，会先删除本地已有模型再重新下载。
  static Future<void> downloadModel({
    MImageOnnxModel? mImageModel,
    void Function(int received, int total)? onProgress,
    bool force = false,
  }) async {
    if (await _usesOnnxModel) {
      final model = mImageModel ?? await RealSrSettings.loadMImageModel();
      final modelsDir = Directory(p.join(await _modelDirectory, 'mimage_onnx'));
      await modelsDir.create(recursive: true);
      final destination = File(p.join(modelsDir.path, model.fileName));
      if (!force && await isMImageModelAvailable(model)) return;
      final pending = File('${destination.path}.download_${const Uuid().v4()}');
      try {
        await WindHttp().download(
          '${MImageOnnxModelConfig.baseUrl}/${model.fileName}',
          pending.path,
          onReceiveProgress: (received, total) {
            if (total > 0) onProgress?.call(received, total);
          },
        );
        if (await pending.length() < 1024) {
          throw StateError('下载的 mImage ONNX 模型无效（可能是 Git-LFS 指针）');
        }
        await pending.rename(destination.path);
      } finally {
        if (await pending.exists()) await pending.delete();
      }
      _missingModelNotified = false;
      await RealSrSettings.modelFileChanged(model);
      return;
    }

    final assetName = _assetName;
    if (assetName == null) {
      throw UnsupportedError('当前平台不支持下载 RealSR 模型');
    }

    final url = await _assetDownloadUrl;
    if (url == null) {
      throw UnsupportedError('当前平台不支持下载 RealSR 模型');
    }
    final cachePath = await getCachePath();
    final archivePath = p.join(cachePath, assetName);
    final destDir = await _modelDirectory;

    if (force && Directory(destDir).existsSync()) {
      // QNN 引擎的模型住在 `qnn/` 子目录里，强刷只删子目录——`super_resolution/`
      // 根上还有 Vulkan 引擎的 NCNN 模型，整目录删会把另一条引擎一起废掉。
      if (await _usesAndroidQnn) {
        final qnnDir = Directory(
          p.join(destDir, AndroidQnnModelConfig.dlcDirName),
        );
        if (qnnDir.existsSync()) await qnnDir.delete(recursive: true);
      } else {
        await Directory(destDir).delete(recursive: true);
      }
    }

    await Directory(destDir).create(recursive: true);

    try {
      // 强制重新下载时先删掉本地缓存的压缩包
      if (force && File(archivePath).existsSync()) {
        await File(archivePath).delete();
      }

      await WindHttp().download(
        url,
        archivePath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received, total);
        },
      );

      await decompress7Z(archivePath: archivePath, destPath: destDir);

      // Linux / macOS 需要给可执行文件授权
      if (Platform.isLinux || Platform.isMacOS) {
        final modelRoot = await _modelDirectory;
        for (final name in ['realcugan-ncnn-vulkan', 'waifu2x-ncnn-vulkan']) {
          final exe = p.join(modelRoot, name);
          try {
            await Process.run('chmod', ['+x', exe], runInShell: false);
          } catch (e, s) {
            logger.w('RealSR 可执行文件授权失败: $exe', error: e, stackTrace: s);
          }
        }
      }

      _missingModelNotified = false;
      showSuccessToast(t.realSr.modelDownloadDone);
    } finally {
      try {
        await File(archivePath).delete();
      } catch (_) {}
    }
  }

  /// 删除当前平台已下载的超分模型。
  ///
  /// - mImage ONNX 引擎：只删那一个 `.onnx` 文件（Windows/Linux 上 NCNN 的可执行文件
  ///   与模型目录就在同一个 `super_resolution/` 里，整目录删会把另一条引擎一起废掉）
  /// - Android / 桌面 NCNN 引擎：删除 `super_resolution` 目录及缓存中的压缩包
  static Future<void> deleteModel([MImageOnnxModel? targetModel]) async {
    if (await _usesOnnxModel) {
      final model = targetModel ?? await RealSrSettings.loadMImageModel();
      final file = File(
        p.join(await _modelDirectory, 'mimage_onnx', model.fileName),
      );
      if (file.existsSync()) {
        await file.delete();
      }
      _missingModelNotified = false;
      await RealSrSettings.modelFileChanged(model);
      return;
    }

    if (Platform.isAndroid || Platform.isWindows || Platform.isLinux) {
      final destDir = await _modelDirectory;
      if (Platform.isAndroid && await _usesAndroidQnn) {
        // 只删 QNN 的 `qnn/` 子目录与它的压缩包（根上的 Vulkan NCNN 模型不动）。
        final qnnDir = Directory(
          p.join(destDir, AndroidQnnModelConfig.dlcDirName),
        );
        if (qnnDir.existsSync()) await qnnDir.delete(recursive: true);
      } else if (Directory(destDir).existsSync()) {
        await Directory(destDir).delete(recursive: true);
      }

      final assetName = _assetName;
      if (assetName != null) {
        final archivePath = p.join(await getCachePath(), assetName);
        final archiveFile = File(archivePath);
        if (archiveFile.existsSync()) {
          await archiveFile.delete();
        }
      }

      _missingModelNotified = false;
      return;
    }

    throw UnsupportedError('当前平台不支持删除 RealSR 模型');
  }

  static const Set<String> _supportedFormats = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
  };

  /// 检测图片是否可被 RealSR 处理。
  ///
  /// 只读取文件头做判断，返回规范化扩展名；不支持（含任何动图容器）返回 null。
  ///
  /// 动图必须挡在这里：超分是「解成一帧 → 重编码一张 PNG」，动图走到那一步会被
  /// **悄悄拍平**。原先只挡动图 WebP，而且那条判定的偏移是错的（动图 WebP 第一个
  /// 块必须是 VP8X，`ANIM` 不在偏移 12），等于一条都没挡住 —— 改名成 `.png` 的
  /// APNG 更是完全没查。现在统一交给 `page_animation` 的容器嗅探。
  static Future<String?> _detectUpscalableExtension(File file) async {
    final rawExt = await detectImageExtension(file);
    final normalizedExt = rawExt.toLowerCase();
    if (!_supportedFormats.contains(normalizedExt)) return null;
    if (await animatedFileHead(file)) return null;
    return normalizedExt;
  }

  /// 量一张图的像素尺寸；解析不出来返回 `null`（不抛异常）。
  ///
  /// 只做「读头 + 报数」一件事。**判阈值请走 [shouldUpscale]** —— 规则只该有一处；
  /// 这个入口是给界面用的（顶栏要显示「超分后是多少」），以及给
  /// [shouldUpscale] 复用的。
  static Future<ui.Size?> imageSizeOf(String path) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(path);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    } catch (e, s) {
      logger.w('RealSR 无法解析图片尺寸: $path', error: e, stackTrace: s);
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// 判断图片是否需要超分：支持固定分辨率阈值与 neo 条件超分系统裁决。
  ///
  /// [knownSize] 给**已经量过这张图尺寸**的调用方（呈现器的超分流水线要先拿尺寸来
  /// 显示「超分后多少」）：同一次判断不该让同一个文件被读第二遍。
  static Future<bool> shouldUpscale(
    String inputPath, {
    RealSrResolutionThreshold? threshold,
    ui.Size? knownSize,
    String? bookPath,
    String? innerPath,
    SuperResolutionPolicyTrigger trigger = SuperResolutionPolicyTrigger.auto,
    Map<String, dynamic>? metadata,
  }) async {
    logger.d('Checking if $inputPath needs to be upscaled...');
    // 若显式指定了 threshold，说明调用方期望强制使用特定固定阈值（如测试用例或强制回落）
    if (threshold != null) {
      final size = knownSize ?? await imageSizeOf(inputPath);
      if (size == null) return false;
      return size.width < threshold.maxWidth;
    }

    final isConditional = await RealSrSettings.loadConditionalEnabled();
    if (isConditional) {
      final decision = await decidePolicy(
        inputPath: inputPath,
        knownSize: knownSize,
        bookPath: bookPath,
        innerPath: innerPath,
        trigger: trigger,
        metadata: metadata,
      );
      return decision.shouldRun;
    }

    final effectiveThreshold = await RealSrSettings.loadResolutionThreshold();
    final size = knownSize ?? await imageSizeOf(inputPath);
    // 量不出尺寸就不超分（沿用旧行为）
    if (size == null) return false;
    return size.width < effectiveThreshold.maxWidth;
  }

  /// 使用条件超分策略（移植自 neo / Xiranite）裁决是否需要对指定图片执行超分
  static Future<SuperResolutionPolicyDecision> decidePolicy({
    required String inputPath,
    ui.Size? knownSize,
    String? bookPath,
    String? innerPath,
    SuperResolutionPolicyTrigger trigger = SuperResolutionPolicyTrigger.auto,
    Map<String, dynamic>? metadata,
    SuperResolutionPolicyPreferences? policyPreferences,
    bool? autoUpscaleEnabled,
  }) async {
    final size = knownSize ?? await imageSizeOf(inputPath);
    if (size == null) {
      return const SuperResolutionPolicyDecision(
        kind: 'skip',
        reason: 'unresolved-image-size',
      );
    }
    final prefs =
        policyPreferences ??
        await RealSrSettings.loadPolicyPreferences(
          autoUpscaleEnabled: autoUpscaleEnabled,
        );
    final input = SuperResolutionPolicyInput(
      trigger: trigger,
      width: size.width,
      height: size.height,
      bookPath: bookPath ?? inputPath,
      imagePath: inputPath,
      innerPath: innerPath,
      metadata: metadata,
    );
    return SuperResolutionPolicyService(prefs).decide(input);
  }

  static bool _missingModelNotified = false;

  /// 同一路径正在超分时，等待方只等这一份；见 [upscaleAndConvertToWebp]。
  static final Map<String, Future<void>> _upscaleInFlight = {};

  /// 对单张图片做超分放大，成功后再转换为 WebP 以节省空间。
  ///
  /// [bookKey] 是这张图所属的**书**（本地路径 / `插件id:漫画id`，见
  /// `RealSrBookScope.keyFor`）：有书就按那本书自己的开关判（覆盖 ?? 全局），
  /// 拿不到才退回全局 —— 在阅读器里关掉一本书的超分，不该把别的书一起关掉。
  ///
  /// **同一路径在飞时只跑一遍**：阅读器显示与预取会各自请求同一页，去重只合并
  /// 「网络取字节」那一段，超分这一段不合并就会同页并发跑两次 —— 实测日志里
  /// 同一文件两次「推理完成」输出字节数完全相同，而且两次写回同一路径会互相
  /// 踩（PNG 还没转 WebP 就被另一份盖掉，留下十几 MB 的 PNG）。
  static Future<void> upscaleAndConvertToWebp(
    String inputPath, {
    String? bookKey,
  }) async {
    final running = _upscaleInFlight[inputPath];
    if (running != null) {
      await running;
      return;
    }
    final started = _upscaleAndConvertToWebpOnce(inputPath, bookKey: bookKey);
    _upscaleInFlight[inputPath] = started;
    try {
      await started;
    } finally {
      // 只清理自己登记的那一条，避免把后来者的记录误删。
      if (identical(_upscaleInFlight[inputPath], started)) {
        _upscaleInFlight.remove(inputPath);
      }
    }
  }

  static Future<void> _upscaleAndConvertToWebpOnce(
    String inputPath, {
    String? bookKey,
  }) async {
    if (!await RealSrBookScope.enabledFor(bookKey)) return;

    // 先做廉价的文件头格式检测，不支持的格式（如 GIF、动图 WebP）直接跳过，
    // 避免进入分辨率解析、模型检查与超分队列。
    final supportedExt = await _detectUpscalableExtension(File(inputPath));
    if (supportedExt == null) {
      logger.d('RealSR 不支持的图片格式，跳过超分: $inputPath');
      return;
    }

    if (!await isAvailable) {
      if (!_missingModelNotified) {
        _missingModelNotified = true;
        showErrorToast(t.realSr.modelIncomplete);
      }
      return;
    }

    final concurrency = await RealSrSettings.loadConcurrency();
    final targetConcurrency = concurrency == 0 ? 64 : concurrency;
    if (maxConcurrency != targetConcurrency) {
      maxConcurrency = targetConcurrency;
    }

    final threshold = await RealSrSettings.loadResolutionThreshold();
    if (!await shouldUpscale(inputPath, threshold: threshold)) {
      logger.d('Input $inputPath does not need to be upscaled.');
      return;
    }

    final tileSize = await RealSrSettings.loadTileSize();

    // Android NCNN 通过 OpenCV imwrite 写图，只能按扩展名识别格式；
    // 输出路径若带 webp/jpg 等扩展名会崩溃。因此 Android 先写到临时 PNG，
    // 转 WebP 后再覆盖回原路径。
    if (Platform.isAndroid) {
      final tempOutput = p.join(
        p.dirname(inputPath),
        'realsr_output_${const Uuid().v4()}.png',
      );

      try {
        final upscaled = await upscale(
          inputPath: inputPath,
          outputPath: tempOutput,
          tileSize: tileSize,
        );
        if (!upscaled) return;

        // 超分成功后输出的是 PNG，再转换为 WebP 以节省空间
        await convertImageToWebp(inputPath: tempOutput, imageType: 'png');
        await File(tempOutput).rename(inputPath);
        // 引擎产物是那个临时 PNG，且它紧接着就被删掉；**真正的产物是替换后的原图**。
        // 不在这里改口登记，「打开图片文件夹」会指着那个已经不存在的临时文件。
        SuperResolutionLog.markOutput(
          inputPath,
          note: '已就地替换原图（超分结果写回缓存文件）：$inputPath',
        );
        UpscaledImageCache.notifyReplaced(inputPath);
      } catch (e, s) {
        logger.w('Android 超分/WebP 转换失败: $inputPath', error: e, stackTrace: s);
        rethrow;
      } finally {
        try {
          if (File(tempOutput).existsSync()) {
            await File(tempOutput).delete();
          }
        } catch (_) {}
      }
      return;
    }

    // 非 Android：产物先落**同目录**的临时文件，转 WebP 后再改名覆盖原图。
    //
    // 为什么不能再就地覆写：阅读器显示路径现在不等超分（一页 6–22 s），
    // 于是「`Image.file` 正在读这张图」和「超分正在写这张图」会并发；
    // CoreML 与 ncnn 的写出都不是原子的，读到半截文件就是一张坏图。
    // 改名（同目录）是唯一能让读者要么看到旧版、要么看到完整新版的动作。
    // 顺带也消掉「转换失败留下十几 MB PNG 盖在原图上」这种状态 —— 现在失败的
    // 只是临时文件，原图保持不动。
    //
    // Windows/Linux 的 ncnn CLI 按**扩展名**判断输出格式（Android 那条注释同），
    // 所以临时文件必须以 `.png` 结尾。
    final tempOutput = '$inputPath.sr-${const Uuid().v4()}.png';
    final bool upscaled;
    if (Platform.isWindows || Platform.isLinux) {
      final mode = await RealSrSettings.loadDesktopNcnnMode();
      final noise = await RealSrSettings.loadDesktopNcnnNoise();
      final variant = DesktopNcnnModelConfig.variantFor(
        mode: mode,
        noise: noise,
      );
      final noiseLevel = RealSrNoiseLevel.values.firstWhere(
        (e) => e.value == variant.noise,
        orElse: () => RealSrNoiseLevel.conservative,
      );

      upscaled = await upscale(
        inputPath: inputPath,
        outputPath: tempOutput,
        executable: variant.displayName,
        modelDir: variant.modelDir,
        scale: variant.scale,
        noiseLevel: noiseLevel,
        tileSize: tileSize,
      );
    } else {
      final noiseLevel = await RealSrSettings.loadNoiseLevel();
      upscaled = await upscale(
        inputPath: inputPath,
        outputPath: tempOutput,
        noiseLevel: noiseLevel,
        tileSize: tileSize,
      );
    }

    final temporaryFile = File(tempOutput);
    if (!upscaled) {
      try {
        if (temporaryFile.existsSync()) await temporaryFile.delete();
      } catch (_) {}
      return;
    }

    // 超分成功后输出的是 PNG，再转换为 WebP 以节省空间（转不动就保留 PNG，
    // 反正接下来只是把这一份改名到原图路径）。
    try {
      await convertImageToWebp(inputPath: tempOutput, imageType: 'png');
    } catch (e, s) {
      logger.w('WebP 转换失败，保留超分后的原图: $inputPath', error: e, stackTrace: s);
    }

    try {
      await temporaryFile.rename(inputPath);
    } catch (e, s) {
      logger.e('超分产物落回原图失败: $inputPath', error: e, stackTrace: s);
      try {
        if (temporaryFile.existsSync()) await temporaryFile.delete();
      } catch (_) {}
      rethrow;
    }

    // 落点仍然是原图路径本身。不登记的话，「打开图片文件夹」只会指向呈现器那条
    // 链路的 `rossi_sr_cache`，而日志里说的图其实在图缓存（或下载）目录里。
    SuperResolutionLog.markOutput(inputPath);
    UpscaledImageCache.notifyReplaced(inputPath);
  }

  /// 对单张图片做超分放大。
  ///
  /// 返回 `true` 的完整含义是：**超分引擎跑完，且 [outputPath] 上留下了一张
  /// 尺寸等于「输入 × 该引擎实际倍率」的有效图片**。图片格式不支持、模型不可用、
  /// 引擎报错、引擎跑完但没写出文件、产物量不出尺寸、产物尺寸对不上，一律 `false`。
  ///
  /// 「跑完没报错就算成功」这种宽松返回值会让调用方把"执行过"读成"已产出"，
  /// 进而把没有超分图的一页报成"替换成功" —— 所以这里的判据必须是产物本身。
  /// 尺寸断言则是最后一道：分块拼接缺块/截断的产物仍然是个能打开的 PNG，
  /// 只有尺寸能把它和「真的放大过」区分开；判 false 之后阅读器的重试才会接手。
  static Future<bool> upscale({
    required String inputPath,
    String? outputPath,
    String executable = 'realcugan-ncnn-vulkan',
    String modelDir = 'models-pro',
    int scale = 2,
    RealSrNoiseLevel noiseLevel = RealSrNoiseLevel.conservative,
    int tileSize = 0,
    int syncGapMode = 3,
    SuperResolutionProfile? engineProfile,
    ui.Size? knownInputSize,
    bool Function()? shouldRun,
  }) async {
    final profile = hasSuperResolutionEngineChoice
        ? engineProfile ?? await RealSrSettings.loadProfile()
        : null;
    if (!(profile == null
        ? await isAvailable
        : await isProfileAvailable(profile))) {
      logger.d('RealSR 不可用，跳过超分: $inputPath');
      SuperResolutionLog.add(
        t.realSr.modelUnavailableHint(
          engine: profile?.engine.label ?? executable,
        ),
      );
      return false;
    }

    final inputFile = File(inputPath);
    if (!inputFile.existsSync()) {
      throw ArgumentError.value(
        inputPath,
        'inputPath',
        'Input file does not exist',
      );
    }

    // 在占用超分并发池之前先判断格式，避免不支持的图片占着任务槽。
    final rawExt = await detectImageExtension(inputFile);
    final normalizedExt = rawExt.toLowerCase();
    if (!_supportedFormats.contains(normalizedExt)) {
      logger.w('RealSR 不支持的图片格式，跳过超分: $inputPath ($rawExt)');
      return false;
    }

    if (await animatedFileHead(inputFile)) {
      logger.w('RealSR 不支持动图容器，跳过超分: $inputPath');
      return false;
    }

    return _pool.withResource(() async {
      if (shouldRun != null && !shouldRun()) return false;
      final startAt = DateTime.now();
      logger.d('Upscaling $inputPath to $outputPath');

      final out =
          outputPath ??
          p.join(
            p.dirname(inputPath),
            '${p.basenameWithoutExtension(inputPath)}_sr.png',
          );

      // 超分引擎统一按 PNG 输入处理，先转换到临时 PNG。
      String pngInputPath = inputPath;
      File? tempPngFile;
      if (normalizedExt != '.png') {
        final cacheDir = await getCachePath();
        pngInputPath = p.join(
          cacheDir,
          'realsr_input_${const Uuid().v4()}.png',
        );
        tempPngFile = File(pngInputPath);
        await convertImageToPng(inputPath: inputPath, outputPath: pngInputPath);
      }

      // 尺寸必须在引擎动手**之前**量：就地替换那条链路里 out 就是 inputPath，
      // 跑完之后原图已经被放大图覆盖了。转换出的临时 PNG 与原图同尺寸，
      // 所以调用方已经量过的 [knownInputSize] 可以直接用。
      final inputSize = knownInputSize ?? await imageSizeOf(pngInputPath);

      // 期望倍率要按**该引擎实际吃进去的那份配置**算，不能直接用参数 [scale]：
      // Android 分支的 `-s` 来自内置 variant，CoreML / ONNX 更是各看各的模型。
      int expectedScale;

      try {
        if (Platform.isAndroid) {
          final engine = await RealSrSettings.loadAndroidEngine();
          final modelRoot = await _modelDirectory;
          if (engine == AndroidSuperResolutionEngine.qnnNpu) {
            final model = await RealSrSettings.loadAndroidQnnModel();
            expectedScale = model.scale;
            SuperResolutionLog.add(
              '开始推理：引擎=QNN NPU；模型=${model.label}（原生 ${model.scale}×）',
            );
            // NPU 上下文跨页常驻（原生侧缓存），记一笔账，退出阅读器时由
            // SrSessionGuard 交还。
            SrSessionGuard.markQnnHeld();
            expectedScale = await AndroidUpscaleEngines.upscaleAndroidQnn(
              inputPath: pngInputPath,
              outputPath: out,
              model: model,
              modelRoot: modelRoot,
            );
          } else {
            final variant = AndroidNcnnModelConfig.variantFor(
              mode: AndroidNcnnModelConfig.defaultMode,
              noise: AndroidNcnnModelConfig.defaultNoise,
            );
            expectedScale = variant.scale;
            await AndroidUpscaleEngines.upscaleAndroidVulkanCli(
              inputPath: pngInputPath,
              outputPath: out,
              variant: variant,
              tileSize: tileSize,
              modelRoot: modelRoot,
            );
          }
        } else if (profile != null &&
            profile.engine != SuperResolutionEngine.desktopNcnn) {
          expectedScale = profile.scale;
          SuperResolutionLog.add(
            '开始推理：引擎=${profile.engine.label}；原生 ${profile.scale}×',
          );
          if (profile.engine == SuperResolutionEngine.breezeCoreML) {
            final variant = profile.coremlVariant;
            final modelPath = await CoreMLModelLoader.prepareModel(
              variant.fileName,
            );
            SuperResolutionLog.add('Rossi 原生 CoreML 模型=$modelPath');
            // 即将加载的 MLModel 会常驻插件侧缓存（读书期间跨页复用），
            // 记一笔账，退出阅读器时由 SrSessionGuard 交还。
            SrSessionGuard.markCoremlHeld();
            await CoreMLUpscale.upscale(
              inputPath: pngInputPath,
              outputPath: out,
              modelPath: modelPath,
              modelType: 'multiarray',
              config: Map<String, dynamic>.from(variant.config),
            );
          } else {
            await _upscaleMImageOnnx(
              inputPath: pngInputPath,
              outputPath: out,
              tileSize: tileSize,
              mImageModel: profile.mimageModel,
            );
          }
        } else {
          // 桌面 NCNN 引擎（Windows / Linux 的默认档），以及没有引擎概念的平台上
          // 的兜底 —— 与改动前 Windows/Linux 走的同一条路。
          expectedScale = scale;
          await _upscaleCli(
            inputPath: pngInputPath,
            outputPath: out,
            executable: executable,
            modelDir: modelDir,
            scale: scale,
            noiseLevel: noiseLevel,
            tileSize: tileSize,
            syncGapMode: syncGapMode,
          );
        }
      } finally {
        if (tempPngFile != null && tempPngFile.existsSync()) {
          await tempPngFile.delete();
        }
      }

      // 引擎「跑完了」不等于「成功了」：它可能退出码非 0 却没被上面的分支抓到、
      // 也可能写出一个 0 字节的空壳。这里把契约兑现掉 —— 返回 true 必须意味着
      // **产物在盘上且非空**。否则调用方（超分流水线）会把"跑过一遍"当成
      // "画面已经换成超分图"，这正是虚报的源头之一。
      final outFile = File(out);
      final int outBytes = outFile.existsSync() ? await outFile.length() : 0;
      if (outBytes <= 0) {
        logger.w(
          '超分引擎未产出有效文件: $out'
          '（${outFile.existsSync() ? '$outBytes 字节' : '文件不存在'}）',
        );
        return false;
      }

      // 「非空」只说明写出了个文件，不说明那是一张完整放大的图 —— 缺块的产物
      // 照样打得开。尺寸是这里唯一还能区分两者的证据：量不出来就是无效图片，
      // 量出来对不上就是没按倍率产出，两种都按未产出处理，让调用方的重试接手。
      final outSize = await imageSizeOf(out);
      if (outSize == null) {
        logger.w('超分产物解析不出尺寸，按失败处理: $out（$outBytes 字节）');
        SuperResolutionLog.add('产物校验失败：$out 解析不出图片尺寸（$outBytes 字节），按未产出处理。');
        return false;
      }
      if (expectedScale > 0 && inputSize != null) {
        final wantW = (inputSize.width * expectedScale).round();
        final wantH = (inputSize.height * expectedScale).round();
        if (outSize.width != wantW || outSize.height != wantH) {
          logger.w(
            '超分产物尺寸不符: $out 实际 ${outSize.width.round()}x${outSize.height.round()}，'
            '期望 ${wantW}x$wantH（输入 ${inputSize.width.round()}x${inputSize.height.round()} × $expectedScale）',
          );
          SuperResolutionLog.add(
            '产物校验失败：${p.basename(out)} 实际 ${outSize.width.round()}x${outSize.height.round()}，'
            '期望 ${wantW}x$wantH（输入 ${inputSize.width.round()}x${inputSize.height.round()} × $expectedScale）。'
            '按未产出处理，保留原图。',
          );
          return false;
        }
      }

      final endAt = DateTime.now();
      final duration = endAt.difference(startAt).inMilliseconds;
      logger.d('Upscaling took ${duration}ms, wrote $outBytes bytes');
      // 产物确实落在 [out] 上了。这里是**所有**超分产出的唯一收口（阅读器呈现链路、
      // 就地替换图缓存链路、调试页都经过它），所以默认先登记这一次的落点；调用方若
      // 之后又挪动了文件（阅读器链路会把 `pending_*.png` 改名成 `sr_*.png`），
      // 再用 `outputReady` / `markOutput` 覆盖成最终落点，别让按钮指着中间产物。
      SuperResolutionLog.markOutput(out);
      SuperResolutionLog.add(
        '推理完成：${profile?.engine.label ?? executable}；耗时 ${duration}ms；输出 $outBytes 字节\n$out',
      );
      return true;
    });
  }

  /// mImage ONNX 推理：Apple 走 CoreML EP，Windows 走 DirectML EP，其余平台是
  /// ONNX Runtime 默认的 CPU EP（Rust 侧 `init_ort` 按目标注册，见
  /// `rust/src/api/mimage_onnx.rs`）。
  ///
  /// Windows 上 DirectML 注册失败会**直接抛错而不是退回 CPU**（Rust 侧加了
  /// `error_on_failure()`）：用户选的是 GPU 引擎，悄悄用 CPU 跑的表现是「慢得像
  /// 没开超分」而看不出原因，所以这里把失败如实弹出来，再原样抛给调用方。
  static bool _onnxErrorNotified = false;

  static Future<void> _upscaleMImageOnnx({
    required String inputPath,
    required String outputPath,
    required int tileSize,
    MImageOnnxModel? mImageModel,
  }) async {
    final model = mImageModel ?? await RealSrSettings.loadMImageModel();
    final root = Directory(p.join(await _modelDirectory, 'mimage_onnx'));
    final modelPath = await MImageOnnxModelConfig.path(root, model);
    // 会话将在 Rust 侧建起并常驻（读书期间跨页复用，10 分钟空闲也会被
    // Rust 侧清扫），记一笔账，退出阅读器时由 SrSessionGuard 主动交还。
    SrSessionGuard.markOnnxHeld();
    try {
      final result = await mimageOnnxUpscale(
        inputPath: inputPath,
        outputPath: outputPath,
        modelPath: modelPath,
        modelId: model.id,
        tileSize: tileSize,
      );
      _onnxErrorNotified = false;
      logger.i('mImage ONNX 超分完成: $result');
      SuperResolutionLog.add('mImage ONNX：$result');
    } catch (e) {
      SuperResolutionLog.add(t.realSr.mimageInferenceFailed(error: e));
      logger.w('mImage ONNX 推理失败', error: e);
      if (!_onnxErrorNotified) {
        _onnxErrorNotified = true;
        showErrorToast(t.realSr.mimageInferenceFailed(error: e));
      }
      rethrow;
    }
  }

  /// 桌面端通过 Process.run 调用 waifu2x-ncnn-vulkan / realcugan-ncnn-vulkan。
  static Future<void> _upscaleCli({
    required String inputPath,
    required String outputPath,
    required String executable,
    required String modelDir,
    required int scale,
    required RealSrNoiseLevel noiseLevel,
    required int tileSize,
    required int syncGapMode,
  }) async {
    final modelRoot = await _modelDirectory;
    final exe = p.join(modelRoot, executable);
    final isWaifu2x = executable.toLowerCase().contains('waifu2x');
    final cachePath = await getCachePath();
    final workDir = Directory(
      p.normalize(p.join(cachePath, 'realsr-upscale', const Uuid().v4())),
    );

    try {
      await workDir.create(recursive: true);

      // CLI 根据后缀判断输入格式，用真实扩展名避免格式错配导致花图。
      final rawExt = await detectImageExtension(File(inputPath));
      final inputExt = rawExt.startsWith('.') ? rawExt.substring(1) : rawExt;
      final tempInput = p.join(
        workDir.path,
        'input.${inputExt.isEmpty ? 'png' : inputExt}',
      );
      final tempOutput = p.join(workDir.path, 'output.png');
      await File(inputPath).copy(tempInput);

      final modelPath = p.join(modelRoot, modelDir);
      final args = [
        '-i',
        tempInput,
        '-o',
        tempOutput,
        '-s',
        scale.toString(),
        '-n',
        noiseLevel.value.toString(),
        '-m',
        modelPath,
        '-g',
        '0',
        '-t',
        tileSize.toString(),
        if (!isWaifu2x) ...['-c', syncGapMode.toString()],
      ];
      final result = await Process.run(
        exe,
        args,
        runInShell: false,
        workingDirectory: modelRoot,
      );

      if (result.exitCode != 0) {
        throw StateError(
          '${isWaifu2x ? 'waifu2x' : 'Real-CUGAN'} CLI 失败 '
          '(exitCode=${result.exitCode})\n'
          'stdout: ${result.stdout}\n'
          'stderr: ${result.stderr}',
        );
      }

      await File(tempOutput).copy(outputPath);
    } finally {
      if (workDir.existsSync()) {
        workDir.deleteSync(recursive: true);
      }
    }
  }
}

class RealSrUpscaleResult {
  final bool success;
  final int exitCode;
  final String outputPath;
  final String stdout;
  final String stderr;

  const RealSrUpscaleResult({
    required this.success,
    required this.exitCode,
    required this.outputPath,
    required this.stdout,
    required this.stderr,
  });

  /// 如果成功，返回输出文件；否则抛出异常并附带 stderr。
  File get outputFile {
    if (!success) {
      throw StateError(
        'RealSR upscale failed (exitCode=$exitCode)\nstdout: $stdout\nstderr: $stderr',
      );
    }
    return File(outputPath);
  }

  @override
  String toString() {
    return 'RealSrUpscaleResult(success=$success, exitCode=$exitCode, outputPath=$outputPath)';
  }
}
