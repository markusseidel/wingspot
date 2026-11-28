# Rename: Wingspot becomes Wingspotted

The name "Wingspot" was already taken in the App Store, so the app is listed as **Wingspotted**. The Instagram handle is
`wingspotted` too. Today the apps, the website, the emails and the docs still say "Wingspot". This plan changes every name
people **see** to Wingspotted, keeps every technical ID, moves the website to a new Wingspotted domain, and then cancels `wingspot.site`.

## 1. Decisions (owner, 2026-11-28)

| # | Question | Decision |
|---|---|---|
| 1 | Spelling | **Wingspotted** (capital W, the rest in lower case). In IDs and handles it is `wingspotted`. |
| 2 | Technical IDs | **Keep them.** Users never see these IDs. Apple and Google don't let an existing app change its bundle ID or applicationId, so changing them would mean a new store entry, and testers would lose their data. |
| 3 | Domain | **A new Wingspotted domain** becomes the only domain. `wingspot.site` is a domain-only STRATO contract (no mail, no webspace) and gets **cancelled**, with no redirect, once the steps in section 8a are done. On 2026-11-28 it served no website (HTTPS doesn't answer) and its MX record was only STRATO's default. |
| 4 | Internal code names | **Keep them.** That covers the repo, the Xcode target, the modules, folders and file names, the Supabase project name and the env var names. |

The rule for every place in this plan: **if a person can see it, it says Wingspotted. If only code or a store backend sees it,
it stays `wingspot`.**

## 2. What stays `wingspot` (and why)

| What | Value | Why it stays |
|---|---|---|
| iOS bundle ID | `site.wingspot.ios` | App Store Connect can't change it. APNs topic, Sign in with Apple and TestFlight hang on it. |
| iCloud container | `iCloud.site.wingspot.ios` | A container can never be renamed or deleted. The existing backups live in it. Only its **display name** changes (section 4.3). |
| Android applicationId | `site.wingspot.android` | Play and Firebase App Distribution tie the app to it. A new ID would be a new app with no update path. |
| Kotlin packages and namespace | `site.wingspot.core`, `site.wingspot.app` | Internal (decision 4). Renaming touches about 300 lines and gives the user nothing. |
| UTType and file extension | `site.wingspot.backup`, `.wingspotbackup` | Existing backup files must keep opening. The extension is short and stays. |
| Quick action types | `site.wingspot.quick.*` | Internal identifiers. |
| URL scheme | `wingspot://` | Invite links and QR codes already shared, and the auth callback `wingspot://auth-callback`, keep working. A second scheme `wingspotted://` is optional (section 4.6). |
| Backup `format` field | `"wingspot-backup"` | It's part of the file format (docs/BACKUP-FORMAT.md). Changing it would break old app versions. |
| Push categories and channel | `WINGSPOT_ACTIVITY`, `WINGSPOT_CHECKIN`, `wingspot_activity` | A changed Android channel ID would reset everybody's notification setting. Only the channel's **visible name** changes. |
| Repo, Xcode, Swift and Gradle names | `markusseidel/wingspot`, `Wingspot.xcodeproj`, `WingspotCore`, `wingspot-android` | Decision 4. |
| Supabase project | `gsfeuxowjymdqbopcpdo`, `project_id = "wingspot"` | Internal. The project ID is in every API URL. |
| Env vars and CI artifacts | `WINGSPOT_*`, `wingspot-debug-apk` | Internal. |
| Graphify, docs file names | `PROTECTING-WINGSPOT-PLAN.md` etc. | Internal. The text inside the docs changes (section 7). |

## 3. Phase 0: before any code (owner)

These steps happen outside the repo. Some of them take days, so they come first.

- [ ] **Domain:** pick and register the domain (for example `wingspotted.app` or `wingspotted.com`), and note it in this file.
  The rest of the plan writes **`<domain>`** for it.
- [ ] **Trademark check:** check "Wingspotted" in the EUIPO and DPMA registers (docs/PROTECTING-WINGSPOT-PLAN.md), and secure the
  name in the same classes as planned for Wingspot.
- [ ] **Handles:** reserve `wingspotted` on the other networks of docs/SOCIAL-PLAN.md (TikTok, YouTube, Threads, X,
  Bluesky, Mastodon) where it is still free. Instagram is done.
- [ ] **Email:** set up `support@<domain>` and `review@<domain>`, plus `planepal@<domain>` for the review seed.
  - A domain alone has no mailboxes. `support@` needs a STRATO mail package, a forward (if the contract offers one) or
    another mail provider whose MX and SPF records are set at STRATO.
  - `review@` and `planepal@` need no mailbox, only the domain.
  - The sign-in mails from Supabase need a separate mail-sending service (docs/WEBSITE-PLAN.md section 7).
- [ ] **Hosting:** serve `<domain>` from a static host, with the DNS records kept at STRATO (docs/WEBSITE-PLAN.md option B).
  No redirect from `wingspot.site`: it gets cancelled (section 8a).

## 4. Phase 1: the apps (one PR, iOS and Android together)

### 4.1 App name on the home screen

- iOS: `INFOPLIST_KEY_CFBundleDisplayName: Wingspotted` in `ios/project.yml`. The name fits under the icon (11 characters).
- Android: `app_name` = `Wingspotted` in `values/strings.xml` and `values-de/strings.xml`.

### 4.2 Texts in the app

- iOS: every "Wingspot" in `ios/Wingspot/Resources/Localizable.xcstrings`, which has 25 entries. The English text is also
  the key, so for each entry change the key, the English text and the German text, and remove the old key. Also change the
  `String(localized:)` and `Text("…")` calls in the Swift files that use those keys.
- iOS `Info.plist`: the permission texts (`NSLocationWhenInUseUsageDescription`, `NSCameraUsageDescription`) and their
  translations in `InfoPlist.xcstrings`, if they exist, plus the UTType description "Wingspot backup".
- Android: the about 15 lines with "Wingspot" in `values/strings.xml` and `values-de/strings.xml`. The notification channel
  name is among them.
- Both: the app line in Settings > About and in the backup header (`"app": "Wingspot 0.3.0"`). Old files keep
  `Wingspot`, and new ones say `Wingspotted`; nobody reads this field.
- Check: `git grep -n '"[^"]*Wingspot[^"]*"' -- ios android | grep -v site.wingspot` shows no visible text with the old name.

### 4.3 iCloud Drive folder and backup files

- `Info.plist` → `NSUbiquitousContainers` → `NSUbiquitousContainerName`: `Wingspotted`. iCloud Drive and the Files app then
  show the folder as "Wingspotted". The container stays the same, so the files in it stay too. The new name only shows once
  the **build number is raised**, because iOS caches this name.
- Backup file names: `Wingspotted-backup-<label>.wingspotbackup`.
  - `BackupFolder.prefix` and the manual backup file name in `BackupViews.swift` change.
  - The Android counterpart changes the same way.
- **Read both prefixes.** `BackupFolder.backups()` lists `Wingspot-backup-*` and `Wingspotted-backup-*`, so the backups of
  older builds still show in the restore list.
- **Clean up the old files.** The first new backup of a device removes that device's old `Wingspot-backup-<label>*` files,
  so the folder doesn't keep four files per iPhone.
- Tests:
  - an old-name file shows in the list;
  - after a new backup only the new names are there;
  - the test vectors stay as they are.
- docs/BACKUP-FORMAT.md: the example file name changes. The `format` field stays `"wingspot-backup"`, with a sentence on why.

### 4.4 Links to the website

- `LegalLinks.swift` and `LegalLinks.kt`: `https://<domain>/privacy`, `/terms`, `/imprint` and `support@<domain>`.
  Only once `<domain>` serves the pages (Phase 0). The old links in today's builds go nowhere today, and nothing will
  redirect them.
- Universal Links and App Links are not built yet (docs/WEBSITE-PLAN.md section 7). When they are built, use **`<domain>`**
  straight away: `applinks:<domain>`, and the intent filter host `<domain>`. Update WEBSITE-PLAN.md now so that work starts
  with the right domain.

### 4.5 Push texts

- `backend/supabase/functions/send-push/apns.ts`: the fallback title `"Wingspot"` becomes `"Wingspotted"`, used when a push has
  no place. Same in `fcm.ts`, if it has one.
- The Android notification channel name (visible in the system settings) changes in strings.xml. The channel **ID** stays.

### 4.6 Optional: a second link scheme `wingspotted://`

- Register it in addition to `wingspot://` (Info.plist `CFBundleURLSchemes`, an Android intent filter), and parse both in
  `InviteLink`.
- New invite links and QR codes keep using `wingspot://` until the website serves invite links on `https://<domain>/invite/…`.
  At that point they move to the web link, not to the new scheme. **Recommendation: skip this step**, because nobody sees the
  scheme.

### 4.7 Release

- iOS build number per the rule (YYYYMMDDBB in `ios/project.yml`; the committed pbxproj keeps `31`), and the Android beta with
  tester text.
- Release notes on both platforms with `post_release_note.sh` (twice, then a read-only check), for example "Wingspot is now
  called Wingspotted".

## 5. Phase 2: backend (migration PR)

- [ ] **Report alert:** `'Wingspot: new report about a ' || …` in the functions of migrations `20261110200000` and
  `20261115200000`. A new migration redefines the function with `Wingspotted:`. Old migrations are never edited.
- [ ] **Welcome message in the review seed:** `backend/scripts/seed-review-account.sh` gets `review@<domain>`,
  `planepal@<domain>`, "Welcome to Wingspotted." and the comment line.
  - Run it once on production after the owner's yes, then store the new demo account in App Store Connect > App Review.
  - The test `AccountStoreTests.swift:425` keeps its value; it only checks the whitespace trim.
- [ ] **Release notes and announcements:** the existing rows stay as they are (history). New rows use the new name.
- [ ] **Auth (Supabase dashboard, owner):**
  - the sender name of the auth emails becomes "Wingspotted";
  - the email templates (confirm, magic link, reset), with the subjects in German and English;
  - Site URL `https://<domain>`;
  - the redirect URL `https://<domain>/auth/callback` replaces the planned `wingspot.site` one (backend/README.md:53);
  - `wingspot://auth-callback` stays.
- [ ] **SMTP sender:** if a custom SMTP is set up, the sender address becomes `…@<domain>`, with SPF, DKIM and DMARC records
  for the new domain.
- [ ] `backend/README.md` and the comment in `post_announcement.sh`: the name in the text.

## 6. Phase 3: stores and outside services (owner, no code)

| Service | What to change |
|---|---|
| App Store Connect | Name is already Wingspotted. Check the subtitle, description, keywords (drop "wingspot"? keep it as a search keyword), what's new, screenshots that show the old name, the support URL, the marketing URL, the privacy URL `<domain>/privacy`, the review demo account (Phase 2), the copyright line. |
| TestFlight | The test information, the beta description, the feedback email `support@<domain>`. |
| Google Play Console (when it is set up) | The app name Wingspotted, the listing in German and English, the developer email and website, the privacy policy URL. |
| Firebase (FCM and App Distribution) | The project's public name and the app nickname shown to testers: "Wingspotted". The project ID stays. |
| Google Cloud OAuth consent screen | The app name "Wingspotted", the logo, the home page, privacy and terms links on `<domain>`, and `<domain>` as an authorized domain. This is the name on Google's sign-in screen. |
| Apple Developer: Sign in with Apple | The Services ID description (if it exists) and the email relay: register `support@<domain>` as a sender domain, otherwise mail to `privaterelay` addresses bounces. |
| Apple Developer: iCloud container | Nothing to change. Its description is internal. |
| Maps API key restrictions | Nothing to change, because they are tied to the app IDs. Add `<domain>` once the website uses maps. |
| GitHub | The repo stays `wingspot` (decision 4). Optionally set the repo description and website to Wingspotted and `<domain>`. |
| Instagram and the other networks | Bio link `<domain>`. |

## 7. Phase 4: docs, legal texts and website

- [ ] **Legal texts first** (docs/PRIVACY-DRAFT.md, docs/TERMS-DRAFT.md, then the published pages):
  - the app name, the domain and the contact email;
  - if the operator (imprint) stays the same, only the name changes;
  - the date of the change in the privacy text.
  - These are live documents, so publish them at the same time as the app build of Phase 1.
- [ ] **Website** (docs/WEBSITE-PLAN.md):
  - name, title, meta tags, the Open Graph image and the favicon text;
  - `<domain>` as the canonical URL;
  - the `/.well-known/apple-app-site-association` and `assetlinks.json` on `<domain>`, with the unchanged app IDs.
- [ ] **Docs in the repo:**
  - "Wingspot" becomes "Wingspotted" in the running text of all about 30 files in `docs/` and in `README` files;
  - `wingspot.site` becomes `<domain>`;
  - code identifiers stay in backticks unchanged (`site.wingspot.ios`, `WingspotCore`, `.wingspotbackup`);
  - file names stay (decision 4);
  - one sentence at the top of docs/CONCEPT.md: "Wingspotted (code name and repo: wingspot)".
- [ ] **contracts/openapi.yaml:** the `title` and `description` change. The server URL stays (Supabase).
- [ ] The test vector `contracts/test-vectors/backup/*` stays as it is (old files are part of the format test).

## 8. Order

1. Phase 0 (owner): domain, emails, hosting. **Phase 1 waits for this**, because the apps link to `<domain>`.
2. Phase 4, legal texts and website live on `<domain>`.
3. Phase 1 app PR and Phase 2 backend PR, merged and built together. Release notes go out.
4. Phase 3 store texts, changed when the build goes out for review.
5. Phase 4 docs PR, at any time; it doesn't touch code.
6. Cancel `wingspot.site` (section 8a), last.

## 8a. Cancelling wingspot.site

Once the domain is cancelled, anyone can register it. So nothing may still point to it at that point.

- [ ] The review demo accounts `review@wingspot.site` and `planepal@wingspot.site` are moved to `<domain>` (Phase 2 seed
  script, run on production after the owner's yes). Otherwise a new owner of the domain could get the password-reset
  mails for them.
  - Check, read-only: `select email from auth.users where email like '%@wingspot.site'` returns no rows.
- [ ] App Store Connect (privacy, support and marketing URL, review contact) and TestFlight (feedback email) use
  `<domain>`.
- [ ] The Supabase Auth site URL and redirect URLs don't name `wingspot.site`.
- [ ] The first iOS and Android build with `<domain>` links is out. Ideally, the TestFlight builds with the old links
  have expired too (90 days after upload; the last one is 0.3.0 2026112702, from 2026-11-27, so it expires around
  2027-02-25). Cancelling sooner only exposes the testers: a new owner of the domain could put a page or a mailbox behind
  the old links.
- [ ] `git grep -n "wingspot\.site"` shows no hits outside the history in docs.
- [ ] Owner: cancel the domain in the STRATO customer login.

## 9. Checks after the change

- `git grep -n 'Wingspot\b' -- ios android backend ':!*.xcstrings'` shows only identifiers like `WingspotCore`, `Wingspot.xcodeproj` or `WINGSPOT_`, never visible text.
- On the iPhone and the Android phone:
  - the home screen name;
  - Settings > About, the legal links (they open on `<domain>`), the contact email;
  - a push without a place shows "Wingspotted".
- iCloud Drive in the Files app shows the folder "Wingspotted":
  - a new backup is named `Wingspotted-backup-…`;
  - an old `Wingspot-backup-…` file shows in the restore list and is removed after the next backup.
- An old invite QR code (`wingspot://invite/…`) still opens the app.
- `curl -sI https://<domain>/privacy` gives a 200, and so do `/terms`, `/imprint` and the two `/.well-known` files.
- The Google and Apple sign-in screens and the auth emails say Wingspotted.

## 10. Open points

- The domain: which TLD (Phase 0).
- Does the App Store keyword field keep "wingspot", so people who heard the old name still find the app?
- Should the app icon or the logo show the name? If so, the icon assets and the website images change too.
