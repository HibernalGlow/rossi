allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Gradle 9 移除了 Project.buildDir，统一改用 layout.buildDirectory（Provider API）
rootProject.layout.buildDirectory.set(file("../build"))
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.application") || plugins.hasPlugin("com.android.library")) {
            // AGP 9 移除了旧的 BaseExtension，改用统一的 CommonExtension DSL
            extensions.configure<com.android.build.api.dsl.CommonExtension> {
                // 与 :app 保持一致，避免插件模块用低版本 SDK 编译时
                // 触发 androidx.core 1.19.0 的 AAR metadata 校验失败
                compileSdk = 37
            }
        }
    }
}
subprojects {
    layout.buildDirectory.set(rootProject.layout.buildDirectory.dir(project.name))
}
subprojects {
    evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

apply(plugin = "com.github.ben-manes.versions") // 应用插件
