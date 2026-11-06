# Wingspot to-do list

Last updated: 2026-11-06. Tick items off as you finish them.

## Do next

- [x] Send the licensing email to ICAO (draft at the end of this file)
- [x] Start Phase 1 (iOS MVP)
- [x] Finish Milestone 2: add Apple sign-in (code merged, switch it on in Supabase, see below)

## Your tasks

Only you can do these, because they need your accounts, money or judgement.

### Licensing

- [ ] Get ICAO's written answer on commercial use of the aircraft type data
- [ ] If ICAO hasn't answered two weeks after the email, send a short reminder
- [ ] Optional: get a short opinion from a German IT or copyright lawyer, including the EU database right
- [ ] Before adding a national registry, check that registry's terms

### Accounts and services

- [x] Buy the domain `wingspot.site`
- [x] Set up custom email sending (SMTP). Supabase's built-in email only reaches project team addresses and is heavily rate-limited. Use a service such as Resend, Postmark or Brevo, and enter its details in Supabase under Auth > SMTP
- [x] Join the Apple Developer Program (before Milestone 2)
- [x] Choose the final app ID: `site.wingspot.ios`
- [ ] Switch on Sign in with Apple in Supabase: Authentication > Sign In / Providers > Apple. Enable it and enter `site.wingspot.ios` as the Client ID. The iPhone app needs no Services ID or key. Those are only for sign-in on the web and on Android (Phase 2b)
- [ ] Test Sign in with Apple on your iPhone with the next TestFlight build, including signing out and in again. The name field in the profile setup should be prefilled with your Apple name
- [x] Add `wingspot://auth-callback` to the redirect URLs in Supabase's Auth settings on hosted (before testing sign-in on hosted)
- [ ] Publish a privacy policy and Impressum on `wingspot.site`, in German and English (before Milestone 9)
- [ ] Create Google sign-in credentials (after the first TestFlight)

### First TestFlight install on your iPhone

For sign-in to work in this build, also do the SMTP and redirect URL tasks above.

- [x] Confirm your Apple Developer membership shows as active
- [x] Sign in to Xcode with your Apple ID (Settings > Accounts)
- [x] Commit the publishable key (done), so every build can sign in
- [x] Create the app in App Store Connect, with the bundle ID `site.wingspot.ios`. The ID can't be changed afterwards. Check that the name "Wingspot" is free; the primary language is English
- [x] Pick "Any iOS Device (arm64)", then archive in Xcode (Product > Archive) and upload with Distribute App. Build 1 went up as "TestFlight Internal Only", which can never go to external testers or the App Store. For external testing, upload with "TestFlight & App Store"
- [x] Fill in App Privacy in App Store Connect (app > General > App Privacy), before external testers or the App Store, and publish it. For the current build, declare only email address and user ID (and the name if you count the username), for app functionality, linked to the user, not used for tracking. Location stays on the phone until sync exists
- [x] When sync (Milestone 3) ships, update App Privacy: check-ins with their location, and any other user content, are then sent to the server
- [x] Create an internal testing group in App Store Connect, then add yourself and the build
- [x] Install the TestFlight app on your iPhone and install Wingspot

### External TestFlight testers

- [x] Upload build 2 (version bump is in the repo) with Distribute App > TestFlight & App Store
- [x] Fill in Test Information in App Store Connect (TestFlight > Test Information): beta app description, feedback email, contact details
- [ ] Publish a privacy policy on `wingspot.site` if Apple asks for its URL
- [x] Add build 2 to your external group and submit it for Beta App Review (usually a day or less)
- [ ] Add testers to the external group, by email or public link

### Build 3: the first build with sync

In this order:

- [x] Deploy sync to hosted, so the endpoint exists before testers use it (done 2026-11-05)
- [x] Update App Privacy in App Store Connect: check-ins with their location now reach the server
- [x] Archive build 3 (the version bump is in the repo) and upload it with Distribute App > App Store Connect
- [ ] Test on your iPhone: make a check-in in airplane mode, switch the network back on, and check that it arrives once (Supabase table `checkins`)

### Build 5: badges and levels

- [x] Deploy the badge migration and the `me` function to hosted (done 2026-11-05)
- [x] Archive build 5 and upload it with Distribute App > App Store Connect, then add it to your groups
- [x] Test on your iPhone: make a check-in, wait for the badge celebration ("Abheben"), then look at Badges and Profile (level, rank, XP)
- [ ] Update the test text for your testers: badges, XP and levels are new

### Before real users sign up

- [ ] Turn on leaked password protection in Supabase
- [ ] Click a real confirmation email link from start to finish (not tested yet)
- [ ] Delete the test account you created on hosted

### Testing

- [ ] Try the offline Spotted check-in in real airplane mode on an iPhone, including a first launch with no network
- [ ] Review the German text in each milestone before it merges
- [ ] Try email sign-in on an iPhone against hosted, from the real email to the signed-in app (already works in the Simulator, with Resend and the profile save)
- [ ] Check the dark and tinted app icons on an iPhone Home Screen

### Small housekeeping

- [ ] Add `.claude/settings.local.json` to `.gitignore`
- [x] Archive the finished session "Move Edge Functions off the legacy anon key"

## Decisions still open

### Needed for check-ins (Phase 1)

- [x] Who may change a registration's type or operator once it's entered? Each user's entry stays on their own check-ins at launch
- [x] Do user-entered registrations reach other users' devices? Not at launch. Sharing by agreement can come later
- [x] Who reviews reports at launch? The project owner (concept §16, question 9)
- [ ] What to do about aircraft types if ICAO hasn't answered by Milestone 9, because hosted has only 22

### Needed later

- [ ] Purchases: own webhook handling or RevenueCat? (§16, question 3)
- [ ] ADS-B provider and licence (§16, question 7)
- [ ] Flight lookup provider and cost per lookup (§16, question 8)
- [ ] Android maps: Google Maps or MapLibre? (§16, question 5)
- [ ] Android timing: after the iOS MVP (recommended) or in parallel? (§16, question 2)
- [ ] Kotlin Multiplatform: revisit after Android 1.0 (§16, question 4)
- [ ] Pilot logbook: build it as a separate track? (§16, question 10)
- [ ] Photo platform scope: display size or full resolution, storage cost, licence options, download policy, quality review (§16, question 12)

## Build work

### Reference data

- [ ] Build the Wikidata operator import (the `operators` table is empty)
- [ ] Publish the 2,699 aircraft types, after ICAO answers. Import into Postgres first, then publish the snapshot
- [ ] Fix maker names with wrong capitals, such as `AIR Tractor` and `NEW Zealand`
- [ ] Review about 214 model names that use a military-style prefix
- [ ] Add the missing types `CONC` (Concorde), `C526` and `KODI`. This needs a small generator change
- [ ] Decide on family labels: `777` in the data, `B777` in the concept
- [ ] Curate the remaining type names, as needed

### Backend

- [x] Create `aircraft` rows from `POST /v1/checkins` (apps can't write to `aircraft` today)
- [x] Deploy sync to hosted, with the next approved deploy: the migration `20261105100000_sync_checkins.sql` and the `checkins` function. Until then, a build with sync gets a 404 on hosted and keeps its check-ins waiting
- [x] Change the `aircraft.data_status` default to `user_submitted`
- [x] Add indexes for the 17 unindexed foreign keys
- [x] Deploy that migration to hosted, with the next approved deploy
- [ ] Confirm the live functions use the publishable key, before legacy anon keys end at the end of 2026:
  - [ ] Update the signup test script, which still uses the anon key
  - [ ] Briefly deactivate the anon key and test
  - [ ] Remove the to-do from `backend/README.md`

- [ ] Deploy badges to hosted, with the next approved deploy: the migration `20261105200000_badges.sql` and the changed `me` function. Do this before any build that shows badges
- [ ] Fill in the island flag and runway lengths in the airport data, then switch on `island_hopper` and `short_field` (set their `valid_from` to null)

### TestFlight setup

- [x] Set the Apple Team ID in the iOS project
- [x] Declare standard encryption, so TestFlight doesn't ask for each build. This is your export-compliance declaration, so check that it's true
- [x] Add a privacy manifest that declares the app's use of UserDefaults
- [ ] Before every upload, raise `CURRENT_PROJECT_VERSION` in `ios/project.yml`, because App Store Connect rejects a build number it has seen

### iOS and Android search

- [x] Find hyphenated names when typed without the hyphen, such as `crj900` and `an124`
- [x] Rank large airports first in search, such as `Wien`
- [ ] Handle registrations with no type or airline yet, on check-ins and badges

### German and English

- [x] Add a string catalog and German to the iOS project (start of Milestone 2)
- [x] Translate Milestone 1's text, including plain `String` values that SwiftUI won't translate automatically (start of Milestone 2)
- [x] Store badge names and descriptions by language (Milestone 4, server side)
- [ ] Send sign-up emails in the user's language. The app already stores it as `language` in the user's metadata. First confirm that Supabase email templates can use it (before Milestone 9)
- [ ] Write the TestFlight text in both languages (Milestone 9)
- [ ] Build shared-link pages in both languages (when universal links are built)
- [ ] Write the App Store text in both languages (Phase 2)

### Phase 1: iOS MVP ([PHASE1.md](PHASE1.md))

- [x] Milestone 1: offline Spotted check-in
- [x] Milestone 2: sign-in and profile
- [x] Milestone 3: sync
- [x] Milestone 4: badges and XP
- [ ] Milestone 5: Airport and Flown check-ins, boarding pass scan, one photo
- [ ] Milestone 6: your profile
- [ ] Milestone 7: social
- [ ] Milestone 8: airport page and settings
- [ ] Milestone 9: first TestFlight

### After Phase 1

- [ ] Phase 2: spotter features, Wingspot Pro and App Store 1.0 (tasks below)
- [ ] Phase 2b: Android 1.0
- [ ] Phase 3: growth

### Phase 2: spotter features, Wingspot Pro and App Store 1.0

Spotter features (concept §14):

- [ ] Spotting sessions with a Live Activity, and batch mode
- [ ] Photo import with details filled in from EXIF, and a Share Extension
- [ ] Flight number lookup, with 5 lookups a month on the free plan (needs the provider decision above)
- [ ] Spotting locations added by users, with moderation
- [ ] Public photo galleries per registration, type and airport, and a photo page with a share link (concept §6.5)
- [ ] Airport leaderboards
- [ ] Widgets and App Intents
- [ ] "What's overhead?" and ADS-B verification (needs the provider and licence decision above)

Wingspot Pro (concept §13):

- [ ] Decide the price (€3.99 a month and €29.99 a year suggested) and whether to show ads (no ads recommended)
- [ ] Build purchases with StoreKit 2, server-side entitlements and App Store webhooks (needs the purchases decision above)
- [ ] Pro features: 10 photos per check-in instead of 4, full-resolution photo storage, advanced stats and charts, CSV and JSON export, custom app icons, profile themes, Pro badge frame

App Store 1.0:

- [ ] Submit the app for App Store review

Left for later in Phase 1, with no phase set yet (PHASE1.md, decisions 4 and 6):

- [ ] Push notifications
- [ ] Universal links
- [ ] Weekly reference data updates, instead of full snapshot downloads
- [ ] Full airport outlines for location checks, instead of a simple radius
- [ ] Predicted badge progress while offline

## Draft: email to ICAO

Send to `web@icao.int` or through the Contact ICAO page.

**Subject:** Licensing question: commercial use of Doc 8643 aircraft type designators in a mobile app

```text
Dear ICAO team,

I am developing Wingspot, a planespotting logbook app for iOS and Android. It will be offered commercially, including paid features. If this is not the right address for licensing questions, please forward this message to the responsible office or let me know whom to contact.

I would like to include aircraft type designators in the app so that users can search for and log aircraft types. The app would hold about 2,700 entries in an offline database on each user's device, and in our backend. Each entry would contain:

- the type designator (for example, A388)
- manufacturer and model name
- engine type and number of engines
- wake turbulence category

Our current data was compiled from FAA Order JO 7360.1K, which refers to ICAO Doc 8643 as the source of the designators. Some manufacturer and model names have been edited by us. The data would be available to users only within the app, not as a separate download or data product.

Could you please tell me:

1. Is this use permitted, and does it require a licence from ICAO?
2. If a licence is required, what are the terms and fees, and how do I apply?
3. Do the same terms apply to the bare designators as to the full entries?
4. Is any attribution or copyright notice required in the app?
5. Does using the designators in search and in users' logbook entries need separate permission?

Thank you for your help.

Kind regards,
Markus Seidel
Wingspot
```
