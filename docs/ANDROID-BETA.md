# Android beta for friends

How to get the Android app to a few testers. Two ways: a file they install by hand (today, no accounts needed), and Google Play's internal testing (the normal way, needs a Google Play developer account).

Prices and Google's rules change. Check them in the Play Console before you rely on a number here.

## What works and what doesn't yet

Same as iOS: the three check-in kinds with photos, edit and delete, the Feed with salutes and comments, the check-in page, Explore (people, airports, types, registrations, airports near you, busy airports), Badges, Profile with collections, settings, privacy, units, data export and account deletion, alerts (Notify me) and the notification switches, German and English, the iPhone colours.

Not on Android yet:
- Maps (the airports map and the Explore map). Needs a decision: Google Maps (an API key) or MapLibre (a tile provider).
- Boarding pass scan with the camera.
- Sign in with Apple, Google or a password. Android has the email link only.
- Push notifications until the Firebase steps below are done. Everything else about alerts (the rules and switches) already works and is stored on the server.

## Way 1: a file for friends (works today)

1. On GitHub: Actions > **Android beta** > Run workflow.
2. When it is done, open the run and download the artifact **wingspot-debug-apk**. It contains `app-debug.apk`.
3. Send the file to the testers (a link or a chat). They open it on their Android phone and allow "install from this source" when the phone asks. The app is a debug build: bigger and a bit slower than a store build, but the same features.
4. Updates: run the workflow again and send the new file. The new file installs over the old one.

Good for two or three friends. There is no list of testers, no automatic updates and no crash reports.

## Way 2: Google Play internal testing (recommended for more than a few friends)

Internal testing is limited to 100 testers, needs no review from Google, and a new version is available to testers within minutes. Testers get automatic updates from the Play Store.

One-time setup (you):
1. Create a Google Play developer account (play.google.com/console). One-time fee, about 25 USD. Google checks your identity first, which can take a few days.
2. Create an app: name Wingspot, default language English (United Kingdom or United States), free.
3. Fill in **App content** (a requirement even for testing tracks, partly): privacy policy URL, ads (none), app access (a tester needs an email to sign in, say so and give a test email if Google asks), data safety, and the account deletion link. The privacy and terms pages must be live first. They are not yet: `LegalLinks.pagesAreLive` in the iOS app is still false, and the drafts are in `docs/PRIVACY-DRAFT.md` and `docs/TERMS-DRAFT.md`.
4. Make an **upload key**, once, on your Mac. Keep the file and both passwords safe (a password manager); never put them in the repository or in a chat:
   ```bash
   keytool -genkeypair -v -keystore wingspot-upload.jks -alias wingspot -keyalg RSA -keysize 2048 -validity 10000
   base64 -i wingspot-upload.jks | pbcopy
   ```
   Play App Signing is on by default: Google keeps the real signing key, and this upload key can be reset if it is ever lost.
5. In the GitHub repository: Settings > Secrets and variables > Actions, add
   - `ANDROID_KEYSTORE_BASE64`: the base64 text of the `.jks` file,
   - `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (wingspot), `ANDROID_KEY_PASSWORD`.
6. Run **Android beta** again. The artifact **wingspot-release-aab** is the signed bundle.
7. Play Console > Testing > Internal testing > Create release > upload the `.aab` > Save and roll out. The application id is `site.wingspot.android` and cannot be changed after the first upload.
8. Testers > create an email list and add your friends' Google accounts (the Gmail address they use on the phone). Copy the **opt-in link** and send it. Each friend opens the link on their phone, accepts, and installs Wingspot from the Play Store.

Every later version: run the workflow, upload the new `.aab` as a new internal release. The version code goes up by itself (the run number).

Later, for a wider test or the public release: Closed testing needs a review by Google. For a personal developer account created recently, Google asks for a closed test with at least 12 testers over 14 days in a row before the app may go to production. Plan for that early, because it adds two weeks.

## Push notifications (Firebase)

Needed once, by you, for alerts to arrive as notifications:
1. console.firebase.google.com > create a project (Analytics can stay off) > add an Android app with the id `site.wingspot.android` > download `google-services.json`.
2. GitHub secret `GOOGLE_SERVICES_JSON`: the contents of that file. (For a local build, put the file at `android/app/google-services.json`; it is ignored by git.)
3. Firebase console > Project settings > Service accounts > Generate new private key. Put the JSON into the Supabase secret `FCM_SERVICE_ACCOUNT` (`supabase secrets set FCM_SERVICE_ACCOUNT="$(cat key.json)" --workdir backend`). Never paste it into a chat or commit it.
4. Deploy the backend: the migration `20261114200000_android_push.sql` (`supabase db push --remote --yes --workdir backend`) and the function (`supabase functions deploy send-push --yes --workdir backend`).
5. Build a new beta. Testers turn on a switch under Profile > Settings > Notifications, allow notifications when the phone asks, and the phone registers itself.

Until step 4 the Android app works as before and Android phones are simply not notified.

## Checking before you invite people

- Sign in on a real phone with the email link (the link opens the app; the email must be opened on the same phone).
- Check in a flight with a photo, see it in the Feed on another account, salute and comment.
- Follow someone, turn on Notify me, check in something with the other account, and see the notification (after the Firebase steps).
- Delete a check-in; export your data; delete a test account.
