group = "net.aotter.trek_ads"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        // Trek artifacts live on Aotter's private Artifactory. Consumers must
        // also declare this repository in their own settings/build script.
        maven { url = uri("https://deps.aotter.net/artifactory/libs-release-local") }
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "net.aotter.trek_ads"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
        // The R8 rules trek-ads needs in a release build.
        consumerProguardFiles("consumer-rules.pro")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    api("com.aotter.android:trek-ads:5.6.6")
    // Pigeon's generated code runs async calls in coroutines.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}
