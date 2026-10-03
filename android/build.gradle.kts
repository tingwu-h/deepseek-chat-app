// 根构建脚本：所有子模块共用（Flutter 插件由 settings.gradle.kts 引入）
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Standard Flutter output layout, so flutter build can locate the APK.
rootProject.layout.buildDirectory.set(rootProject.layout.projectDirectory.dir("../build"))
subprojects {
    layout.buildDirectory.set(rootProject.layout.buildDirectory.dir(name))
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
