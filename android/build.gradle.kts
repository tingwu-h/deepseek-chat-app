// 根构建脚本：所有子模块共用（Flutter 插件由 settings.gradle.kts 引入）
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
