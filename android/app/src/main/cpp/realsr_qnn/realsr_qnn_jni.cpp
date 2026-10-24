// Rossi 侧 QNN 推理的 JNI 表面。
//
// 结构移植自 HaoweiLi97/mihon_img_upscale (Apache License 2.0) 的
// app/src/main/cpp/waifu2x_jni.cpp —— 上游把 QNN / Vulkan-ncnn / MediaTek
// 三条后端混在同一个 `waifu2x-jni` 库里；Rossi 的 Vulkan 路线是外部
// waifu2x CLI 进程，本库只保留 QNN 部分，ncnn / litert / anime4k 一概不带。
//
// 语义与上游保持一致的部分：
// - 输入 Bitmap 先拷成紧凑 RGBA 缓冲，解锁后再推理（Bitmap 锁不跨推理持有）；
// - 单色源检测（monochrome_guard）+ 网点纹理分析（periodic_texture_guard），
//   Real-CUGAN Pro 且单色源才启用 75% 收缩还原方案；
// - 推理成功且源为单色时，对输出强制去色 —— 上游的共享输出边界保证；
// - 推理持锁串行；abort 标志跨 init/process 生效。

#include "monochrome_guard.h"
#include "periodic_texture_guard.h"
#include "qnn_backend.h"

#include <android/bitmap.h>
#include <android/log.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <jni.h>
#include <mutex>
#include <vector>
#if defined(__ARM_NEON)
#include <arm_neon.h>
#endif

#define TAG "RealSrQnn"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

namespace {

std::mutex g_lock;
std::atomic<int> g_progress{0};
std::atomic<bool> g_abort_processing{false};

// The DSP loads Skel itself, following ADSP_LIBRARY_PATH. The first dlopen of
// libQnnHtp.so fixes that lookup for the whole process: setting the variable
// later leaves every retry failing with "Failed to load skel" / 4000, and the
// QNN context creation then reports 14001.
std::string own_library_dir() {
  Dl_info info{};
  if (dladdr(reinterpret_cast<void *>(&own_library_dir), &info) != 0 &&
      info.dli_fname != nullptr) {
    const std::string path(info.dli_fname);
    const size_t slash = path.find_last_of('/');
    if (slash != std::string::npos) return path.substr(0, slash);
  }
  return {};
}

void ensure_dsp_path(const char *preferred_dir) {
  std::string directory = preferred_dir != nullptr ? preferred_dir : "";
  if (directory.empty()) directory = own_library_dir();
  if (directory.empty()) {
    LOGE("Unable to locate the native library dir; ADSP_LIBRARY_PATH untouched");
    return;
  }
  const std::string dsp_paths =
      directory +
      ";/vendor/dsp/cdsp;/vendor/lib/rfsa/cdsp;/system/vendor/lib/rfsa/cdsp";
  setenv("ADSP_LIBRARY_PATH", dsp_paths.c_str(), 1);
  LOGD("QNN ADSP_LIBRARY_PATH=%s", dsp_paths.c_str());
}

void set_adsp_library_path(JNIEnv *env, jstring native_library_dir) {
  if (native_library_dir == nullptr) return;
  const char *chars = env->GetStringUTFChars(native_library_dir, nullptr);
  if (chars != nullptr) {
    ensure_dsp_path(chars);
    env->ReleaseStringUTFChars(native_library_dir, chars);
  }
}

// 与上游 force_monochrome_output 相同：仅对被判定为单色的源运行，
// 彩色页不付全图成本。
void force_monochrome_output(unsigned char *rgba, int width, int height,
                             int stride) {
  if (!rgba || width <= 0 || height <= 0 || stride < width * 4) return;

  for (int y = 0; y < height; ++y) {
    unsigned char *row = rgba + static_cast<size_t>(y) * stride;
    int x = 0;
#if defined(__ARM_NEON)
    for (; x + 8 <= width; x += 8) {
      uint8x8x4_t pixels = vld4_u8(row + static_cast<size_t>(x) * 4);
      uint16x8_t luma = vmull_u8(pixels.val[0], vdup_n_u8(77));
      luma = vmlal_u8(luma, pixels.val[1], vdup_n_u8(150));
      luma = vmlal_u8(luma, pixels.val[2], vdup_n_u8(29));
      luma = vaddq_u16(luma, vdupq_n_u16(128));
      const uint8x8_t gray = vshrn_n_u16(luma, 8);
      pixels.val[0] = gray;
      pixels.val[1] = gray;
      pixels.val[2] = gray;
      vst4_u8(row + static_cast<size_t>(x) * 4, pixels);
    }
#endif
    for (; x < width; ++x) {
      unsigned char *pixel = row + static_cast<size_t>(x) * 4;
      const unsigned char luma = static_cast<unsigned char>(
          (77 * pixel[0] + 150 * pixel[1] + 29 * pixel[2] + 128) >> 8);
      pixel[0] = luma;
      pixel[1] = luma;
      pixel[2] = luma;
    }
  }
}

}  // namespace

// System.loadLibrary() runs this before any QNN entry point, so the DSP path
// is already in place when qnn_backend::probe()/architecture() first dlopen.
extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *, void *) {
  ensure_dsp_path(nullptr);
  return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_zephyr_breeze_realsr_RealSrQnn_nativeIsRuntimeAvailable(JNIEnv *,
                                                                 jobject) {
  return qnn_backend::is_runtime_loadable() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_zephyr_breeze_realsr_qnn_QualcommHtp_nativeArchitecture(
    JNIEnv *env, jobject, jstring native_library_dir) {
  set_adsp_library_path(env, native_library_dir);
  return static_cast<jint>(qnn_backend::architecture());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_zephyr_breeze_realsr_RealSrQnn_nativeInit(JNIEnv *env, jobject,
                                                   jstring context_path,
                                                   jstring native_library_dir,
                                                   jint padding) {
  std::lock_guard<std::mutex> lock(g_lock);
  set_adsp_library_path(env, native_library_dir);
  const char *context_path_chars = env->GetStringUTFChars(context_path, nullptr);
  const bool initialized = qnn_backend::initialize(
      context_path_chars ? context_path_chars : "", static_cast<int>(padding));
  if (context_path_chars != nullptr) {
    env->ReleaseStringUTFChars(context_path, context_path_chars);
  }
  return initialized ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_zephyr_breeze_realsr_RealSrQnn_nativeIsInitialized(JNIEnv *, jobject) {
  return qnn_backend::is_initialized() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_zephyr_breeze_realsr_RealSrQnn_nativeScale(JNIEnv *, jobject) {
  return static_cast<jint>(qnn_backend::scale());
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_zephyr_breeze_realsr_RealSrQnn_nativeProcess(JNIEnv *env, jobject,
                                                      jobject bitmap,
                                                      jboolean is_pro) {
  std::lock_guard<std::mutex> lock(g_lock);
  g_progress.store(0);
  jobject outBitmap = nullptr;

  if (!qnn_backend::is_initialized()) return nullptr;

  AndroidBitmapInfo info{};
  if (AndroidBitmap_getInfo(env, bitmap, &info) < 0) return nullptr;
  if (info.format != ANDROID_BITMAP_FORMAT_RGBA_8888) return nullptr;

  void *pixels = nullptr;
  if (AndroidBitmap_lockPixels(env, bitmap, &pixels) < 0) return nullptr;

  const int w = static_cast<int>(info.width);
  const int h = static_cast<int>(info.height);
  const int stride = static_cast<int>(info.stride);

  // 紧凑 RGBA 副本：Bitmap 锁不跨推理持有，QNN 分块读取需要连续行。
  std::vector<unsigned char> packed(static_cast<size_t>(w) * h * 4);
  if (packed.empty()) {
    AndroidBitmap_unlockPixels(env, bitmap);
    return nullptr;
  }
  for (int y = 0; y < h; y++) {
    memcpy(packed.data() + static_cast<size_t>(y) * w * 4,
           static_cast<const unsigned char *>(pixels) +
               static_cast<size_t>(y) * stride,
           static_cast<size_t>(w) * 4);
  }
  AndroidBitmap_unlockPixels(env, bitmap);

  const int scale = qnn_backend::scale();
  if (scale < 2) return nullptr;

  const bool is_monochrome_input =
      monochrome_guard::is_neutral_rgba(packed.data(), w, h);
  // Real-CUGAN Pro 的 75% 收缩还原方案只对「Pro + 单色源」启用（上游同口径）。
  periodic_texture_guard::Analysis texture_analysis(
      packed.data(), w, h, w * 4, is_pro == JNI_TRUE && is_monochrome_input);

  jclass bitmapClass = env->FindClass("android/graphics/Bitmap");
  jmethodID createBitmapMethod = env->GetStaticMethodID(
      bitmapClass, "createBitmap",
      "(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;");
  jclass configClass = env->FindClass("android/graphics/Bitmap$Config");
  jfieldID configField = env->GetStaticFieldID(
      configClass, "ARGB_8888", "Landroid/graphics/Bitmap$Config;");
  jobject config = env->GetStaticObjectField(configClass, configField);
  outBitmap = env->CallStaticObjectMethod(bitmapClass, createBitmapMethod,
                                          w * scale, h * scale, config);
  if (outBitmap == nullptr) return nullptr;

  void *outPixels = nullptr;
  if (AndroidBitmap_lockPixels(env, outBitmap, &outPixels) != 0) {
    env->DeleteLocalRef(outBitmap);
    return nullptr;
  }
  AndroidBitmapInfo outInfo{};
  AndroidBitmap_getInfo(env, outBitmap, &outInfo);

  const auto start = std::chrono::steady_clock::now();
  const int ret = qnn_backend::process_rgba(
      packed.data(), w, h, w * 4, static_cast<uint8_t *>(outPixels),
      static_cast<int>(outInfo.stride), texture_analysis, &g_progress,
      &g_abort_processing);
  const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                      std::chrono::steady_clock::now() - start)
                      .count();
  LOGD("QNN HTP processing %s in %lld ms", ret == 0 ? "completed" : "failed",
       static_cast<long long>(ms));

  if (ret == 0 && is_monochrome_input) {
    force_monochrome_output(static_cast<unsigned char *>(outPixels),
                            static_cast<int>(outInfo.width),
                            static_cast<int>(outInfo.height),
                            static_cast<int>(outInfo.stride));
  }

  AndroidBitmap_unlockPixels(env, outBitmap);

  if (ret != 0) {
    // 失败产物不得进入缓存：调用方保留原图。
    env->DeleteLocalRef(outBitmap);
    return nullptr;
  }
  return outBitmap;
}

extern "C" JNIEXPORT void JNICALL
Java_com_zephyr_breeze_realsr_RealSrQnn_nativeAbort(JNIEnv *, jobject) {
  g_abort_processing.store(true);
}

extern "C" JNIEXPORT void JNICALL
Java_com_zephyr_breeze_realsr_RealSrQnn_nativeClearAbort(JNIEnv *, jobject) {
  g_abort_processing.store(false);
}

extern "C" JNIEXPORT void JNICALL
Java_com_zephyr_breeze_realsr_RealSrQnn_nativeShutdown(JNIEnv *, jobject) {
  g_abort_processing.store(true);
  std::lock_guard<std::mutex> lock(g_lock);
  qnn_backend::shutdown();
  g_abort_processing.store(false);
  g_progress.store(0);
}
