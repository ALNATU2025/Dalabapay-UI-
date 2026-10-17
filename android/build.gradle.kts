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
        // Reflection keeps this independent of AGP classes on the root classpath.
        val android = extensions.findByName("android") ?: return@withId
        val getNs = android.javaClass.getMethod("getNamespace")
        if (getNs.invoke(android) == null) {
            val manifest = file("src/main/AndroidManifest.xml")
            val pkg = if (manifest.exists()) {
                Regex("package=\"([^\"]+)\"").find(manifest.readText())?.groupValues?.get(1)
            } else null
            android.javaClass.getMethod("setNamespace", String::class.java)
                .invoke(android, pkg ?: "dev.dalabapay.${project.name.replace('-', '_')}")
        }
    }
}
// Old plugins compiled against very old SDKs fail resource linking
// (e.g. "android:attr/lStar not found"). Raise their compileSdk.
subprojects {
    val raiseCompileSdk: Project.() -> Unit = {
        val android = extensions.findByName("android")
        if (android != null && plugins.hasPlugin("com.android.library")) {
            val current = android.javaClass.getMethod("getCompileSdkVersion").invoke(android) as String?
            val level = current?.substringAfter("android-")?.toIntOrNull() ?: 0
            if (level in 1..33) {
                android.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                    .invoke(android, 35)
            }
        }
    }
    if (state.executed) raiseCompileSdk() else afterEvaluate { raiseCompileSdk() }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}