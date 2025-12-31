plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")         // modern plugin id
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "name.dhdsoftware.cashsenseflutter"

    // Values provided by the Flutter Gradle plugin
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "name.dhdsoftware.cashsenseflutter"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Use debug signing so `flutter run --release` works until you add a real one
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Match your Gradle JDK (you’re on 17)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // Needed if your styles.xml uses Theme.Material3.*
    implementation("com.google.android.material:material:1.12.0")

    // Google Mobile Ads SDK (18.1.0 or later)
    implementation("com.google.android.gms:play-services-ads:22.6.0")
}

flutter {
    source = "../.."
}
