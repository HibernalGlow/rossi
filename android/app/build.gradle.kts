import groovy.json.JsonSlurper
import java.util.Properties
import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

repositories {
    maven {
        url = uri(findRustlsPlatformVerifierProject())
        metadataSources {
            artifact()
            mavenPom()
        }
    }
}

fun findRustlsPlatformVerifierProject(): String {
    val dependencyText = providers.exec {
        workingDir = File(project.rootDir, "../")
        commandLine(
            "cargo",
            "metadata",
            "--format-version",
            "1",
            "--filter-platform",
            "aarch64-linux-android",
            "--manifest-path",
            "rust/Cargo.toml",
        )
    }.standardOutput.asText.get()

    val dependencyJson = JsonSlurper().parseText(dependencyText) as Map<*, *>
    val packages = dependencyJson["packages"] as List<*>
    val manifestPath = packages
        .mapNotNull { it as? Map<*, *> }
        .first { it["name"] == "rustls-platform-verifier-android" }["manifest_path"] as String

    return File(File(manifestPath).parentFile, "maven").path
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// ---------------------------------------------------------------------------
// QNN（Qualcomm HTP NPU）超分后端接线，结构对齐 HaoweiLi97/mihon_img_upscale
// 的 app/build.gradle.kts（Apache License 2.0）。
//
// - QNN 运行时（libQnnHtp*.so / libQnnSystem.so）来自 Maven Central 的
//   qnn-runtime AAR，不需要本地 SDK。
// - DLC→context 的设备端编译器 libQnnModelDlc.so 与编译期头文件来自本地
//   QAIRT SDK 2.49.0.260730：local.properties 的 `qnn.sdk.dir`、Gradle 属性
//   `-PqnnSdkDir=...` 或环境变量 QNN_SDK_ROOT 三选一。
// - 没有 SDK 时：C++ 侧以 stub 形态编译（ROSSI_ENABLE_QNN=0，运行时自报
//   不可用），libQnnModelDlc.so 不打包 —— CI 无凭据也能出完整功能的包，
//   只是 NPU 后端在运行时报「不可用」。发布 NPU 包必须在有 SDK 的机器上构建。
// - Skel 体积裁剪：`-PqnnHtpArchitectures=69,79`（默认 69,79，即骁龙 8+ Gen 1
//   与 8 Elite 两档验证目标；写 `all` 保留全部 v69/v73/v75/v79/v81）。
// ---------------------------------------------------------------------------

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

val qnnSdkDir = providers.gradleProperty("qnnSdkDir").orNull
    ?: localProperties.getProperty("qnn.sdk.dir")
    ?: System.getenv("QNN_SDK_ROOT")
val qnnSdkRoot = qnnSdkDir?.takeIf { it.isNotBlank() }?.let { file(it) }

val generatedQnnJniLibs = layout.buildDirectory.dir("generated/qnnJniLibs")

val stageQnnDlcRuntime = tasks.register<Sync>("stageQnnDlcRuntime") {
    // 有 SDK 时整套暂存 QNN 运行库（Htp / HtpPrepare / ModelDlc / System +
    // 各代际 Skel/Stub），替代 qnn-runtime AAR —— 运行库与 qnn.sdk.dir 的
    // 头文件必须同源同版（混版本会在 contextCreate 报 device config 错）。
    // 无 SDK（CI）时源为空、目录产出为空，APK 不含 QNN 运行库 —— 运行时
    // 如实报 NPU 不可用；若 AAR 依赖在场则仍由 AAR 提供（stub 兜底）。
    if (qnnSdkRoot != null) {
        val sdkRoot = qnnSdkRoot!!
        val libraries = listOf(
            "libQnnHtp.so",
            "libQnnHtpPrepare.so",
            "libQnnModelDlc.so",
            "libQnnSystem.so",
            "libQnnHtpV69Skel.so",
            "libQnnHtpV69Stub.so",
            "libQnnHtpV79Skel.so",
            "libQnnHtpV79Stub.so",
        )
        from(libraries.map { sdkRoot.resolve("lib/aarch64-android/$it") }) {
            into("arm64-v8a")
        }
        doFirst {
            libraries.forEach { library ->
                check(sdkRoot.resolve("lib/aarch64-android/$library").isFile) {
                    "QNN runtime not found: $library under ${sdkRoot.absolutePath}"
                }
            }
        }
    } else {
        doLast { logger.lifecycle("QAIRT SDK not configured; skipping QNN runtime staging") }
    }
    into(generatedQnnJniLibs)
}

// HTP Skel/Stub 裁剪：每个架构约 13-19 MB，全部打包约 +55 MB。
// v68 不在受支持列表（QualcommHtp 只认 69/73/75/79/81），同样进裁剪候选。
val qnnHtpArchitectures = providers.gradleProperty("qnnHtpArchitectures").orNull ?: "69,79"
val qnnAllHtpArchitectures = listOf(68, 69, 73, 75, 79, 81)
val qnnKeptHtpArchitectures = if (qnnHtpArchitectures.trim().equals("all", ignoreCase = true)) {
    qnnAllHtpArchitectures
} else {
    qnnHtpArchitectures.split(',').mapNotNull { it.trim().toIntOrNull() }
}
val qnnTrimmedLibraries = buildList {
    // 只用 HTP 一条后端：DSP（v66）与 GPU 后端的库整组剔除（约 -13 MB）。
    addAll(
        listOf(
            "lib/**/libQnnDsp.so",
            "lib/**/libQnnDspV66Skel.so",
            "lib/**/libQnnDspV66Stub.so",
            "lib/**/libQnnGpu.so",
        ),
    )
    addAll(
        qnnAllHtpArchitectures
            .filter { it !in qnnKeptHtpArchitectures }
            .flatMap { listOf("lib/**/libQnnHtpV${it}Skel.so", "lib/**/libQnnHtpV${it}Stub.so") },
    )
}

android {
    namespace = "com.zephyr.breeze"
    compileSdk = 36
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_21.toString()
    }

    java {
        toolchain {
            languageVersion.set(JavaLanguageVersion.of(21))
        }
    }

    defaultConfig {
        // sentry v10 原生层要求 API 26+，Flutter 默认 24 会导致 release 构建失败
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                if (qnnSdkRoot != null) {
                    arguments += "-DQNN_SDK_DIR=${qnnSdkRoot.absolutePath}"
                }
            }
        }
    }

    // QNN 编译器 so 的暂存目录（无 SDK 时目录为空，不影响构建）。
    // 用 task provider 派生的路径挂 srcDir，Gradle 会自动带上任务依赖
    // （手写 dependsOn 名字匹配会被任务图校验拒绝：用了输出却没声明边）。
    sourceSets["main"].jniLibs.srcDir(stageQnnDlcRuntime.map { it.destinationDir })

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/realsr_qnn/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // release 签名可用性：key.properties（git-crypt）未解锁 / 属性缺失时回退
    // debug 签名 —— 本机验收包可装可跑；CI 解密后属性齐全，行为不变。
    val releaseSigningAvailable = keystorePropertiesFile.exists() &&
        keystoreProperties.getProperty("keyAlias") != null &&
        keystoreProperties.getProperty("storeFile") != null

    signingConfigs {
        create("release") {
            if (releaseSigningAvailable) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { project.file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseSigningAvailable) {
                signingConfigs["release"]
            } else {
                logger.lifecycle("release signing unavailable (key.properties missing/unlocked?); falling back to debug signing")
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        jniLibs {
            // 未选中的 HTP 架构整组剔除（Skel + Stub）。
            excludes += qnnTrimmedLibraries
            // keep 逻辑不需要：qnn-runtime AAR 的其余 so 全部保留。
        }
    }
}

flutter {
    source = "../.."
}

//configurations.all {
//    resolutionStrategy {
//        force("androidx.core:core:1.16.0")
//        force("androidx.core:core-ktx:1.16.0")
//    }
//}

dependencies {
    // 添加核心库脱糖依赖
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("rustls:rustls-platform-verifier:0.1.1")
    // QNN 运行库不来自 AAR：与 qnn.sdk.dir 头文件同源同版由 stageQnnDlcRuntime
    // 整套暂存（头/库混版本会在设备端 contextCreate 报 INVALID_CONFIG）。
    // 无 qnn.sdk.dir 的构建（CI）APK 不含 QNN 运行库，运行时如实报不可用。
}
