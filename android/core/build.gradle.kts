// The shared logic with no Android in it, so its tests run on a plain JVM in seconds. The test vectors in
// ../contracts/test-vectors are the same files the iOS app is checked against.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(libs.okhttp)
    implementation(libs.serialization.json)
    implementation(libs.coroutines.core)
    // SQLite with FTS5 built in. The phone's own SQLite may lack it, and the search needs it.
    implementation(libs.androidx.sqlite.bundled)

    testImplementation(libs.kotlin.test)
    testImplementation(libs.okhttp.mockwebserver)
}

tasks.test {
    useJUnitPlatform()
}
