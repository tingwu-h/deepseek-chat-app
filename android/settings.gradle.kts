pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

// 注意：不要在 settings 脚本顶层写 repositories { google() ... }。
// Gradle 的 Kotlin DSL 里该作用域没有 google()/mavenCentral() 扩展，
// 会报 "Unresolved reference: google" 导致整个构建失败（已实测）。
// 插件仓库写在上面 pluginManagement 里，普通依赖仓库由 android/build.gradle.kts 的
// allprojects { repositories { ... } } 负责。

include(":app")
