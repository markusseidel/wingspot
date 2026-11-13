plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "site.wingspot.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "site.wingspot.android"
        minSdk = 26
        targetSdk = 35
        // The beta workflow passes the run number as -PwingspotVersionCode, so every upload to Google Play is higher than the last.
        versionCode = providers.gradleProperty("wingspotVersionCode").map { it.toInt() }.getOrElse(1)
        versionName = "0.2.0"

        // Both are public: the same address and publishable key the iPhone app ships with. Override with
        // -PwingspotSupabaseUrl=... when pointing at a local stack.
        val url = providers.gradleProperty("wingspotSupabaseUrl").getOrElse("https://gsfeuxowjymdqbopcpdo.supabase.co")
        val key = providers.gradleProperty("wingspotPublishableKey").getOrElse("sb_publishable_lWulnPUXjeRfnM8VNu50lw_A0vESCcF")
        // The Google Maps key: restrict it to this app (package name and signing certificate) in Google Cloud. Without a
        // key the app works and the maps explain that they are not set up. Give it with -PwingspotMapsKey=... or the
        // WINGSPOT_MAPS_API_KEY environment variable.
        val mapsKey = providers.gradleProperty("wingspotMapsKey").orElse(providers.environmentVariable("WINGSPOT_MAPS_API_KEY")).getOrElse("")
        manifestPlaceholders["mapsApiKey"] = mapsKey
        // The "Web application" OAuth client id from Google Cloud (not the Android one), which Supabase also has in its
        // Google provider settings. Without it the Google button is hidden.
        val googleClient = providers.gradleProperty("wingspotGoogleClientId").orElse(providers.environmentVariable("WINGSPOT_GOOGLE_CLIENT_ID")).getOrElse("")
        buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", "\"$googleClient\"")
        buildConfigField("boolean", "MAPS_KEY_SET", (mapsKey.isNotBlank()).toString())
        buildConfigField("String", "SUPABASE_URL", "\"$url\"")
        buildConfigField("String", "PUBLISHABLE_KEY", "\"$key\"")
    }

    // The upload key is never in the repository. The beta workflow gives its location and passwords as environment
    // variables; without them the release build is simply unsigned.
    signingConfigs {
        val keystorePath = System.getenv("WINGSPOT_KEYSTORE_PATH")
        if (keystorePath != null) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("WINGSPOT_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("WINGSPOT_KEY_ALIAS")
                keyPassword = System.getenv("WINGSPOT_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(project(":core"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.work.runtime)
    implementation(libs.camerax.core)
    implementation(libs.camerax.camera2)
    implementation(libs.camerax.lifecycle)
    implementation(libs.camerax.view)
    implementation(libs.mlkit.barcode)
    implementation(libs.credentials)
    implementation(libs.credentials.play)
    implementation(libs.google.id)
    implementation(libs.maps.compose)
    implementation(libs.play.services.maps)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
}

// Push needs the Firebase project's google-services.json (not in the repository). Without it the app still builds and
// runs, and just has no push: see docs/ANDROID-BETA.md.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
