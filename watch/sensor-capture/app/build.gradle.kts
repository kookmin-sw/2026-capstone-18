plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.littlesignals.capture"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.littlesignals.capture"
        minSdk = 30           // Wear OS 3+ (Galaxy Watch 8 ships with Wear OS 5)
        targetSdk = 36        // Required for Sensor SDK 1.4.x's Android-16 permission gating to be honored by Health Platform
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        debug {
            isDebuggable = true
        }
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        viewBinding = false
    }

    packaging {
        resources.excludes += setOf(
            "/META-INF/{AL2.0,LGPL2.1}",
        )
    }
}

dependencies {
    // Samsung Health Sensor SDK (vendored AAR — see ../libs/)
    implementation(files("../libs/samsung-health-sensor-api-1.4.1.aar"))

    // Wear OS + Compose
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui:1.7.5")
    implementation("androidx.compose.material3:material3:1.3.1")
    implementation("androidx.wear.compose:compose-material:1.4.0")
    implementation("androidx.wear.compose:compose-foundation:1.4.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    // Logging
    implementation("com.jakewharton.timber:timber:5.0.1")

    // Wear Data Layer — phone↔watch messaging (path /biosignals/*)
    implementation("com.google.android.gms:play-services-wearable:18.2.0")

    // JVM unit-test infra (watch app had none before Phase 3)
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
    testImplementation("org.json:json:20240303")
}
