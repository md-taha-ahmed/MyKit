import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (local) or the CI workflow writes it
// from GitHub secrets. Without it, release builds fall back to the debug key.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.mdtaha.mykit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    defaultConfig {
        applicationId = "com.mdtaha.mykit"
        // 26: required by the manga extension host (same as Mihon).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

android {
    lint {
        // Release "lint vital" analyzes Kotlin with AGP's bundled 2.2 compiler, which
        // can't read the Kotlin 2.4 libraries the manga host needs. It only logs
        // "incompatible version" noise (the build still succeeds), so skip it.
        checkReleaseBuilds = false
    }
    packaging {
        resources {
            excludes += setOf(
                "META-INF/*.kotlin_module",
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
            )
        }
    }
}

// Runtime that Mihon/Tachiyomi extensions (lib 1.4 / 1.6) are compiled against.
// Versions follow keiyoushi/extensions-source; extensions get these from the host app.
dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.4.10")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json-okio:1.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-protobuf:1.12.0")
    implementation("com.squareup.okhttp3:okhttp:5.4.0")
    implementation("com.squareup.okhttp3:okhttp-brotli:5.4.0")
    implementation("com.squareup.okhttp3:okhttp-zstd:5.4.0")
    implementation("com.squareup.okhttp3:okhttp-dnsoverhttps:5.4.0")
    implementation("org.jsoup:jsoup:1.22.2")
    implementation("io.reactivex:rxjava:1.3.8")
    implementation("com.github.null2264.injekt:injekt-core:4135455a2a")
    implementation("com.github.zhanghai.quickjs-java:quickjs-android:547f5b1597")
    implementation("androidx.preference:preference-ktx:1.2.1")
    implementation("androidx.webkit:webkit:1.18.0")
}

// Movies & Series: torrent streaming engine (libtorrent via libtorrent4j).
dependencies {
    implementation("org.libtorrent4j:libtorrent4j:2.1.0-39")
    implementation("org.libtorrent4j:libtorrent4j-android-arm64:2.1.0-39")
    implementation("org.libtorrent4j:libtorrent4j-android-arm:2.1.0-39")
}
