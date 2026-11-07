allprojects {
    // Keep plugin build scripts on the app's toolchain, avoiding several
    // redundant Kotlin compilers and Android Gradle Plugin versions.
    buildscript.configurations.configureEach {
        resolutionStrategy {
            force("org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.20")
            force("com.android.tools.build:gradle:8.11.1")
        }
    }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
