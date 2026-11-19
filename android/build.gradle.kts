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
subprojects {
    project.evaluationDependsOn(":app")
}
// geocoding_android's own android/build.gradle hardcodes compileSdk 33,
// which is too old for a transitive dependency (androidx.annotation-
// experimental); force every Android library subproject to at least 34,
// matching :app's own compileSdk -- this doesn't change minSdk/targetSdk.
fun fixCompileSdk(project: Project) {
    project.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let { android ->
        if ((android.compileSdk ?: 0) < 34) android.compileSdk = 34
    }
}
subprojects {
    if (name == "app") return@subprojects
    // afterEvaluate, not plugins.withId: geocoding_android's own
    // android/build.gradle sets compileSdk 33 itself, after applying the
    // plugin -- an override registered at plugin-apply time runs first and
    // gets clobbered. afterEvaluate guarantees this runs last -- except
    // :app's evaluationDependsOn(":app") above (unrelated to this fix)
    // forces app to evaluate eagerly, so already-evaluated subprojects (none
    // expected here besides app, but just in case) are fixed immediately.
    if (state.executed) fixCompileSdk(this) else afterEvaluate { fixCompileSdk(this) }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
