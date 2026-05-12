plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.littlesignals.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.littlesignals.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 26) // Health Connect requires API 26+
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.android.gms:play-services-wearable:18.2.0")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.18.0")
    implementation("androidx.health.connect:connect-client:1.1.0-rc01")
    testImplementation("com.microsoft.onnxruntime:onnxruntime:1.18.0")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

tasks.register<Copy>("syncInferenceAssets") {
    from(rootProject.file("../../AI/checkpoints_final/wesad_w2.0/wesad_mamba_v1.onnx"))
    into(layout.projectDirectory.dir("src/main/assets"))
}

tasks.register<Copy>("syncInferenceFixtures") {
    from(rootProject.file("../../AI/serve/tests/fixtures/synthetic_capture.zip"))
    into(layout.projectDirectory.dir("src/test/resources"))
}

tasks.named("preBuild") { dependsOn("syncInferenceAssets") }
tasks.matching { it.name.endsWith("UnitTestJavaRes") }.configureEach {
    dependsOn("syncInferenceFixtures")
}
