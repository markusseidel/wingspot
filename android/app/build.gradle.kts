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
        versionCode = 1
        versionName = "0.1.0"

        // Both are public: the same address and publishable key the iPhone app ships with. Override with
        // -PwingspotSupabaseUrl=... when pointing at a local stack.
        val url = providers.gradleProperty("wingspotSupabaseUrl").getOrElse("https://gsfeuxowjymdqbopcpdo.supabase.co")
        val key = providers.gradleProperty("wingspotPublishableKey").getOrElse("sb_publishable_lWulnPUXjeRfnM8VNu50lw_A0vESCcF")
        buildConfigField("String", "SUPABASE_URL", "\"$url\"")
        buildConfigField("String", "PUBLISHABLE_KEY", "\"$key\"")
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
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
}
