


val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// AGP 8+ requires `android.namespace` in every Android module.
// Some older Flutter plugins still only declare `package` in AndroidManifest.xml.
// This fallback derives namespace from the manifest package when missing.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate

        val hasNamespace = runCatching {
            val ns = androidExt.javaClass.getMethod("getNamespace").invoke(androidExt) as? String
            ns != null && ns.isNotBlank()
        }.getOrDefault(false)
        if (hasNamespace) return@afterEvaluate

        val manifestFile = file("src/main/AndroidManifest.xml")
        if (!manifestFile.exists()) return@afterEvaluate

        val pkg = Regex("""package\s*=\s*"([^"]+)"""")
            .find(manifestFile.readText())
            ?.groupValues
            ?.getOrNull(1)
            ?.trim()
            .orEmpty()
        if (pkg.isBlank()) return@afterEvaluate

        runCatching {
            androidExt.javaClass.getMethod("setNamespace", String::class.java).invoke(androidExt, pkg)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    plugins.withId("org.jetbrains.kotlin.android") {
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
            val javaTaskName = name.replace("Kotlin", "JavaWithJavac")
            val javaTask = project.tasks.findByName(javaTaskName) as? org.gradle.api.tasks.compile.JavaCompile
            if (javaTask != null) {
                kotlinOptions.jvmTarget = javaTask.targetCompatibility
            }
        }
    }
}

buildscript {
    repositories {
        google()
        mavenCentral()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
