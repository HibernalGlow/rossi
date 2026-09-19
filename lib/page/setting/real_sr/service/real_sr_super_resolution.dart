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
import 'package:zephyr/page/setting/real_sr/service/desktop_ncnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/upscaled_image_cache.dart';
import 'package:zephyr/page/setting/real_sr/service/mimage_onnx_model_config.dart';
import 'package:zephyr/src/rust/api/image.dart';
import 'package:zephyr/src/rust/api/mimage_onnx.dart';
import 'package:zephyr/src/rust/api/simple.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/get_path.dart';
import 'package:zephyr/widgets/toast.dart';

/// Breeze 内置 RealSR / Real-CUGAN / CoreML 超分封装
///
/// - Android：调用 bundled 的 waifu2x-ncnn CLI
/// - iOS / macOS：Breeze 原生 Swift/CoreML 与 mImage ONNX/CoreML 可切换
/// - Windows / Linux：从 `deretame/breeze-binary` 下载模型后，
///   调用 `getFilePath()/super_resolution/` 下的 waifu2x-ncnn-vulkan
///   或 realcugan-ncnn-vulkan
class RealSrSuperResolution {
  RealSrSuperResolution._();

  static const MethodChannel _channel = MethodChannel(
    'realsr_super_resolution',
  );

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
  /// - Android：arm64-v8a 且 NCNN 模型已下载并解压
  /// - iOS / macOS：当前选择的 mImage ONNX 模型已下载
  /// - Windows / Linux：存在对应平台的 realcugan-ncnn-vulkan 可执行文件
  static Future<bool> get isAvailable async {
    if (Platform.isAndroid) {
      try {
        if (!await isDeviceSupported) return false;
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

    if (Platform.isIOS || Platform.isMacOS) {
      return isAppleProfileAvailable(await RealSrSettings.loadAppleProfile());
    }

    if (Platform.isWindows || Platform.isLinux) {
      final modelRoot = await _modelDirectory;
      final mode = await RealSrSettings.loadDesktopNcnnMode();
      final exeName = DesktopNcnnModelConfig.executableNameFor(mode);
      return File(p.join(modelRoot, exeName)).existsSync();
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

  static Future<bool> isAppleProfileAvailable(
    AppleSuperResolutionProfile profile,
  ) => profile.engine == AppleSuperResolutionEngine.breezeCoreML
      ? CoreMLModelLoader.isModelAvailable(profile.coremlVariant.fileName)
      : isMImageModelAvailable(profile.mimageModel);

  /// 当前平台对应的 7z 压缩包文件名。
  static String? get _assetName {
    if (Platform.isAndroid) return 'realsr-android.7z';
    if (Platform.isWindows) return 'realsr-win.7z';
    if (Platform.isLinux) return 'realsr-linux.7z';
    return null;
  }

  /// 当前平台手动下载模型的直链（可在浏览器中打开）。
  ///
  /// - Android：`realsr-android.7z`
  /// - Windows：`realsr-win.7z`
  /// - Linux：`realsr-linux.7z`
  /// - iOS / macOS：当前选择的 mImage ONNX 模型文件
  static String? get manualDownloadUrl {
    if (Platform.isIOS || Platform.isMacOS) {
      final model = RealSrSettings.currentMImageModel;
      return '${MImageOnnxModelConfig.baseUrl}/${model.fileName}';
    }
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
        '文件名与当前模型不匹配: 期望 ${model.fileName}, 实际 ${p.basename(filePath)}',
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
        throw FormatException('压缩包内容不符合当前平台要求: $missing');
      }

      if (Platform.isIOS || Platform.isMacOS) {
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
          throw FormatException('压缩包缺少 mImage ONNX 模型 ${model.fileName}');
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

  /// 检查解压后的内容是否满足当前平台需求，返回缺失内容描述；null 表示通过。
  static Future<String?> _missingModelFiles(Directory extractedRoot) async {
    if (Platform.isAndroid) {
      final variant = AndroidNcnnModelConfig.variantFor(
        mode: AndroidNcnnModelConfig.defaultMode,
        noise: AndroidNcnnModelConfig.defaultNoise,
      );
      final modelDir = Directory(p.join(extractedRoot.path, variant.modelDir));
      if (!modelDir.existsSync()) {
        return '缺少模型目录 ${variant.modelDir}';
      }
      for (final relative in _androidModelFilesFor(variant)) {
        if (!File(p.join(modelDir.path, relative)).existsSync()) {
          return '缺少模型文件 ${p.join(variant.modelDir, relative)}';
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
        return '缺少 waifu2x / Real-CUGAN 可执行文件';
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
        return '缺少模型目录（models-pro / models-se 等）';
      }
      return null;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      final model = await RealSrSettings.loadMImageModel();
      final path = p.join(extractedRoot.path, model.fileName);
      if (File(path).existsSync()) return null;
      for (final entity in extractedRoot.listSync(recursive: true)) {
        if (entity is File && p.basename(entity.path) == model.fileName) {
          return null;
        }
      }
      return '缺少 mImage ONNX 模型 ${model.fileName}';
    }

    return '当前平台不支持手动导入超分模型';
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
  /// - Android：下载 `realsr-android.7z` 并解压 NCNN 模型。
  /// - iOS / macOS：直接下载当前选择的 mImage ONNX 模型。
  /// - Windows / Linux：下载对应平台的 realcugan-ncnn-vulkan 压缩包。
  ///
  /// [force] 为 true 时，会先删除本地已有模型再重新下载。
  static Future<void> downloadModel({
    MImageOnnxModel? mImageModel,
    void Function(int received, int total)? onProgress,
    bool force = false,
  }) async {
    if (Platform.isIOS || Platform.isMacOS) {
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

    final url = '$_binaryRepoBaseUrl/$assetName';
    final cachePath = await getCachePath();
    final archivePath = p.join(cachePath, assetName);
    final destDir = await _modelDirectory;

    if (force && Directory(destDir).existsSync()) {
      await Directory(destDir).delete(recursive: true);
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
      showSuccessToast('模型下载完成');
    } finally {
      try {
        await File(archivePath).delete();
      } catch (_) {}
    }
  }

  /// 删除当前平台已下载的超分模型。
  ///
  /// - iOS / macOS：删除 `super_resolution/mimage_onnx` 模型目录
  /// - Android / Windows / Linux：删除 `super_resolution` 目录及缓存中的压缩包
  static Future<void> deleteModel([MImageOnnxModel? targetModel]) async {
    if (Platform.isIOS || Platform.isMacOS) {
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
      if (Directory(destDir).existsSync()) {
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
  /// 只读取文件头做判断，返回规范化扩展名；不支持（含动图 WebP）返回 null。
  static Future<String?> _detectUpscalableExtension(File file) async {
    final rawExt = await detectImageExtension(file);
    final normalizedExt = rawExt.toLowerCase();
    if (!_supportedFormats.contains(normalizedExt)) return null;
    if (normalizedExt == '.webp' && await isAnimatedWebP(file)) return null;
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

  /// 判断图片是否需要超分：仅当能解析出横向分辨率且小于阈值时返回 true。
  ///
  /// [knownSize] 给**已经量过这张图尺寸**的调用方（呈现器的超分流水线要先拿尺寸来
  /// 显示「超分后多少」）：同一次判断不该让同一个文件被读第二遍。
  static Future<bool> shouldUpscale(
    String inputPath, {
    RealSrResolutionThreshold? threshold,
    ui.Size? knownSize,
  }) async {
    logger.d('Checking if $inputPath needs to be upscaled...');
    final effectiveThreshold =
        threshold ?? await RealSrSettings.loadResolutionThreshold();
    final size = knownSize ?? await imageSizeOf(inputPath);
    // 量不出尺寸就不超分（沿用旧行为）：对一张不知道多大的图跑几百毫秒推理，
    // 还不如如实跳过 —— 呈现器会把这一页记成「无需超分」，界面上说得清楚。
    if (size == null) return false;
    return size.width < effectiveThreshold.maxWidth;
  }

  static bool _missingModelNotified = false;

  /// 对单张图片做超分放大，成功后再转换为 WebP 以节省空间。
  static Future<void> upscaleAndConvertToWebp(String inputPath) async {
    final autoUpscale = await RealSrSettings.loadAutoUpscale();
    if (!autoUpscale) return;

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
        showErrorToast('模型不完整');
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

    // Windows / Linux：根据用户选择的策略与降噪档位，解析到具体 CLI 与模型。
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

      final upscaled = await upscale(
        inputPath: inputPath,
        outputPath: inputPath,
        executable: variant.displayName,
        modelDir: variant.modelDir,
        scale: variant.scale,
        noiseLevel: noiseLevel,
        tileSize: tileSize,
      );
      if (!upscaled) return;
    } else {
      final noiseLevel = await RealSrSettings.loadNoiseLevel();
      final upscaled = await upscale(
        inputPath: inputPath,
        outputPath: inputPath,
        noiseLevel: noiseLevel,
        tileSize: tileSize,
      );
      if (!upscaled) return;
    }

    // 超分成功后输出的是 PNG，再转换为 WebP 以节省空间
    try {
      await convertImageToWebp(inputPath: inputPath, imageType: 'png');
    } catch (e, s) {
      logger.w('WebP 转换失败，保留超分后的原图: $inputPath', error: e, stackTrace: s);
    }
    // 非 Android 平台（macOS/iOS 走 CoreML，Windows/Linux 走 ncnn CLI）都是把结果
    // **就地写回 [inputPath]**，所以这张图的落点就是原图路径本身。不登记的话，
    // 「打开图片文件夹」只会指向呈现器那条链路的 `rossi_sr_cache`，而日志里说的
    // 图其实在图缓存（或下载）目录里 —— 位置对不上就是这么来的。
    SuperResolutionLog.markOutput(inputPath);
    UpscaledImageCache.notifyReplaced(inputPath);
  }

  /// 对单张图片做超分放大。
  ///
  /// 返回 `true` 的完整含义是：**超分引擎跑完且 [outputPath] 上确实留下了非空的
  /// 产物文件**。图片格式不支持、模型不可用、引擎报错、引擎跑完但没写出文件
  /// 等情况一律返回 `false`。
  ///
  /// 「跑完没报错就算成功」这种宽松返回值会让调用方把"执行过"读成"已产出"，
  /// 进而把没有超分图的一页报成"替换成功" —— 所以这里的判据必须是产物本身。
  static Future<bool> upscale({
    required String inputPath,
    String? outputPath,
    String executable = 'realcugan-ncnn-vulkan',
    String modelDir = 'models-pro',
    int scale = 2,
    RealSrNoiseLevel noiseLevel = RealSrNoiseLevel.conservative,
    int tileSize = 0,
    int syncGapMode = 3,
    AppleSuperResolutionProfile? appleProfile,
    bool Function()? shouldRun,
  }) async {
    final profile = (Platform.isMacOS || Platform.isIOS)
        ? appleProfile ?? await RealSrSettings.loadAppleProfile()
        : null;
    if (!(profile == null
        ? await isAvailable
        : await isAppleProfileAvailable(profile))) {
      logger.d('RealSR 不可用，跳过超分: $inputPath');
      SuperResolutionLog.add(
        '模型不可用：${profile?.engine.label ?? executable}，请先在超分设置中下载模型。',
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

    if (normalizedExt == '.webp' && await isAnimatedWebP(inputFile)) {
      logger.w('RealSR 不支持动图 WebP，跳过超分: $inputPath');
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

      try {
        if (Platform.isAndroid) {
          final variant = AndroidNcnnModelConfig.variantFor(
            mode: AndroidNcnnModelConfig.defaultMode,
            noise: AndroidNcnnModelConfig.defaultNoise,
          );
          await _upscaleAndroidCli(
            inputPath: pngInputPath,
            outputPath: out,
            variant: variant,
            tileSize: tileSize,
          );
        } else if (Platform.isIOS || Platform.isMacOS) {
          SuperResolutionLog.add(
            '开始推理：引擎=${profile!.engine.label}；原生 ${profile.scale}×',
          );
          if (profile.engine == AppleSuperResolutionEngine.breezeCoreML) {
            final variant = profile.coremlVariant;
            final modelPath = await CoreMLModelLoader.prepareModel(
              variant.fileName,
            );
            SuperResolutionLog.add('Breeze 原生 CoreML 模型=$modelPath');
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

  /// Android 通过 bundled waifu2x CLI 超分。
  static Future<void> _upscaleAndroidCli({
    required String inputPath,
    required String outputPath,
    required NcnnModelVariant variant,
    required int tileSize,
  }) async {
    final exePath = await _prepareAndroidCli();
    final modelRoot = await _modelDirectory;
    final modelPath = p.join(modelRoot, variant.modelDir);

    final result = await Process.run(
      exePath,
      [
        '-i',
        inputPath,
        '-o',
        outputPath,
        '-s',
        variant.scale.toString(),
        '-n',
        variant.noise.toString(),
        '-m',
        modelPath,
        '-g',
        '0',
        '-t',
        tileSize.toString(),
      ],
      runInShell: false,
      workingDirectory: modelRoot,
    );

    if (result.exitCode != 0) {
      throw StateError(
        'waifu2x CLI 失败 (exitCode=${result.exitCode})\n'
        'stdout: ${result.stdout}\n'
        'stderr: ${result.stderr}',
      );
    }
  }

  static String? _androidCliPath;

  /// 获取 APK 中 bundled 的 waifu2x CLI 路径（位于 nativeLibraryDir）。
  static Future<String> _prepareAndroidCli() async {
    if (_androidCliPath != null) return _androidCliPath!;

    final path = await _channel.invokeMethod<String>('getWaifu2xCliPath');
    if (path == null || path.isEmpty) {
      throw StateError('getWaifu2xCliPath returned empty path');
    }
    _androidCliPath = path;
    return path;
  }

  /// iOS / macOS 使用 mImageViewer ONNX；ONNX Runtime 优先 CoreML EP。
  static Future<void> _upscaleMImageOnnx({
    required String inputPath,
    required String outputPath,
    required int tileSize,
    MImageOnnxModel? mImageModel,
  }) async {
    final model = mImageModel ?? await RealSrSettings.loadMImageModel();
    final root = Directory(p.join(await _modelDirectory, 'mimage_onnx'));
    final modelPath = await MImageOnnxModelConfig.path(root, model);
    final result = await mimageOnnxUpscale(
      inputPath: inputPath,
      outputPath: outputPath,
      modelPath: modelPath,
      modelId: model.id,
      tileSize: tileSize,
    );
    logger.i('mImage ONNX 超分完成: $result');
    SuperResolutionLog.add('mImage ONNX：$result');
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

/// 检测 WebP 文件是否为动图
/// 返回 true 表示是动图，false 表示静态图或读取失败
Future<bool> isAnimatedWebP(File file) async {
  try {
    // 只需要读取前 20 个字节就够了（实际只需 16 个，读 20 以防万一）
    final bytes = await file.openRead(0, 20).first;

    // 长度不足则判定为非动图
    if (bytes.length < 16) return false;

    // 校验头部是否为 RIFF...WEBP (0x52= R, 0x49=I, 0x46=F)
    // 偏移 0-3: RIFF, 偏移 8-11: WEBP
    if (bytes[0] != 0x52 ||
        bytes[1] != 0x49 ||
        bytes[2] != 0x46 ||
        bytes[3] != 0x46) {
      return false;
    }
    if (bytes[8] != 0x57 ||
        bytes[9] != 0x45 ||
        bytes[10] != 0x42 ||
        bytes[11] != 0x50) {
      return false;
    }

    // 关键判断：偏移 12-15 必须是 'ANIM' (0x41=A, 0x4E=N, 0x49=I, 0x4D=M)
    // 只要是 ANIM，就说明包含动画控制块，必然是动图
    return bytes[12] == 0x41 &&
        bytes[13] == 0x4E &&
        bytes[14] == 0x49 &&
        bytes[15] == 0x4D;
  } catch (_) {
    return true;
  }
}
