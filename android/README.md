# Android

Native Kotlin / Jetpack Compose app, started as the spike described in [docs/ANDROID.md](../docs/ANDROID.md).

- `core/`: plain Kotlin (no Android), tested on the JVM against the same vectors as the iPhone app (`contracts/test-vectors`): boarding pass parser, registration rules, great-circle distance, and email-link sign-in with PKCE against Supabase, and the reference data installer and search (bundled SQLite with FTS5).
- `app/`: the Compose app. So far: email-link sign-in (English and German), reference data download and offline search of airports and aircraft types, the Spotted, Airport and Flown check-ins with a local database and an upload outbox (WorkManager), photos from the system photo picker (metadata removed on the phone), editing the details of a flight, deleting a check-in, the Feed with photos, salutes and comments, a page for every check-in, people search, follow, block and report, the community rules, choosing a username, and who may see your check-ins. Badges with levels and celebrations, the profile with stats, collections, edit profile, settings (privacy, units), data export and account deletion. Explore (one search for people, airports, aircraft types and registrations, airports near you, busy airports) with airport, type and registration pages. Alerts: "Notify me" per person, notification settings and the list of people you get alerts from, and push through Firebase (FCM) once the build has the Firebase project's `google-services.json`. The colours are the iPhone app's (orange accent, navy, system backgrounds, light and dark), a registration check and a boarding pass text reader that use `core/`.

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

The boarding pass camera scan, Sign in with Apple, Google and password, token storage in the Android Keystore. Push needs the Firebase project, and the maps need a Google Maps key: see [docs/ANDROID-BETA.md](../docs/ANDROID-BETA.md).
