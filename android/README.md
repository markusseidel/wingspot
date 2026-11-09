# Android

Native Kotlin / Jetpack Compose app, started as the spike described in [docs/ANDROID.md](../docs/ANDROID.md).

- `core/`: plain Kotlin (no Android), tested on the JVM against the same vectors as the iPhone app (`contracts/test-vectors`): boarding pass parser, registration rules, great-circle distance, and email-link sign-in with PKCE against Supabase, and the reference data installer and search (bundled SQLite with FTS5).
- `app/`: the Compose app. So far: email-link sign-in (English and German), reference data download and offline search of airports and aircraft types, a registration check and a boarding pass text reader that use `core/`.

## Building

Needs JDK 17 and the Android SDK (platform 37, build tools 35). On this Mac they come from Homebrew:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools
echo "sdk.dir=$ANDROID_SDK_ROOT" > android/local.properties
cd android
./gradlew :core:test
./gradlew :app:assembleDebug
```

Emulator: `emulator -avd wingspot`, then `adb install -r app/build/outputs/apk/debug/app-debug.apk`.

The app talks to the same Supabase project as the iPhone app. Its address and publishable key are public and set in `app/build.gradle.kts`; override them with `-PwingspotSupabaseUrl=...` and `-PwingspotPublishableKey=...`.

## Not done yet

Check-ins and the outbox, push (Firebase), maps, Sign in with Google and Apple, release signing, token storage in the Android Keystore. See docs/ANDROID.md.
