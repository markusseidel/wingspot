# Milestone 9: release, first TestFlight for friends (plan)

Done when: friends can install the app, sign up, check in, follow each other and use it for real, and the legal pages are public ([PHASE1.md](PHASE1.md)).

Items marked **you** can only be done by the project owner.

## 9a. Backend readiness

Ready-to-paste texts, answers and the email template are in [TESTFLIGHT.md](TESTFLIGHT.md). Status: the Supabase checks were looked at on 8 Nov (section 6 there), the email template is written (section 4), and Apple's own crash reports are the default (section 5). Still to do: the items marked **you**.

- Confirm the live functions use the publishable key, then briefly deactivate the legacy anon key and test (**you** approve the deactivation).
- Turn on leaked password protection (**you**: needs the Supabase Pro plan).
- Sign-up emails in the user's language: check that the Supabase email templates can use the stored `language`, or fall back to one bilingual template.
- Decide the aircraft types problem: hosted has 22 types until ICAO answers. Wait, or publish a self-curated list.
- Look at the Supabase security and performance checks and the backups once more.

## 9b. Crash reporting and usage

- Choose Apple's own crash reports (no code, no privacy text change) or Sentry (better detail, needs privacy text changes and a processing agreement).
- Analytics (TelemetryDeck was in the concept) come last, if wanted, with an update of the privacy policy.

## 9c. Legal and store pieces (mostly **you**)

- Fill in and publish the privacy policy, terms of use and Impressum on `wingspot.site`, in German and English ([PRIVACY-DRAFT.md](PRIVACY-DRAFT.md), [TERMS-DRAFT.md](TERMS-DRAFT.md)).
- App Privacy answers in App Store Connect: add Photos or Videos, User Content and Other User Content for the social features.
- Review notes for Apple: a demo account, where reporting and blocking are, how deletion works (guideline 1.2 and 5.1.1(v)).
- The TestFlight text in both languages.

## 9d. Build and device checks

- Raise `CURRENT_PROJECT_VERSION` (and the version if wanted) in `ios/project.yml`, archive, and upload as "TestFlight & App Store".
- The real-iPhone checklist (**you**): boarding-pass scan, photo upload, offline check-in in airplane mode, dark and tinted icons, a two-account social test, deletion, export, and the final sync check against hosted.
- Fix whatever comes out of it as small pull requests.

## 9e. Friends test

- Add testers to the external group, send the text, and set up how they reach you (an email address or form).
- Watch the `reports` table and the crash reports for a week.
