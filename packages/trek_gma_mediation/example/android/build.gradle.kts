allprojects {
    repositories {
        google()
        mavenCentral()
        // Trek SDK artifacts live on Aotter's private Artifactory, not Maven Central.
        maven { url = uri("https://deps.aotter.net/artifactory/libs-release-local") }
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
