allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 修复 isar_flutter_libs 等旧插件缺少 namespace 报错的问题
subprojects {
    afterEvaluate {
        val androidExtension = project.extensions.findByName("android")
        if (androidExtension != null) {
            val isarNamespace = "dev.isar.isar_flutter_libs"
            val flutterNamespace = "io.flutter.plugins.pathprovider"
            
            if (project.name == "isar_flutter_libs") {
                val extension = androidExtension as com.android.build.gradle.LibraryExtension
                extension.namespace = isarNamespace
                extension.compileSdk = 34
            } else if (project.name == "path_provider_android") {
                val extension = androidExtension as com.android.build.gradle.LibraryExtension
                extension.namespace = flutterNamespace
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
