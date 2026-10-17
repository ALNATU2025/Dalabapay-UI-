allprojects {
    repositories {
        google()
        mavenCentral()
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
// Older plugins (e.g. flutter_app_badger) don't declare an Android namespace,
// which AGP 8+ requires. Use the package from their manifest.
subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.getByType(com.android.build.gradle.LibraryExtension::class.java)
        if (android.namespace == null) {
            val manifest = file("src/main/AndroidManifest.xml")
            val pkg = if (manifest.exists()) {
                Regex("package=\"([^\"]+)\"").find(manifest.readText())?.groupValues?.get(1)
            } else null
            android.namespace = pkg ?: "dev.dalabapay.${project.name.replace('-', '_')}"
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}