import org.gradle.authentication.http.BasicAuthentication

allprojects {
    repositories {
        google()
        mavenCentral()
        // Mapbox's private Maven repo, needed by mapbox_maps_flutter.
        // Requires a *secret* Mapbox token with the "Downloads:Read" scope
        // (different from the public pk. token used at runtime) to be set as
        // MAPBOX_DOWNLOADS_TOKEN in your Gradle user home's gradle.properties
        // (usually ~/.gradle/gradle.properties) — never commit it to the repo.
        // See the README for details.
        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            authentication {
                create<BasicAuthentication>("basic")
            }
            credentials {
                username = "mapbox"
                password = (findProperty("MAPBOX_DOWNLOADS_TOKEN") as String?) ?: ""
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
