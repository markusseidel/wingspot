# TestFlight and release material (Milestone 9)

Texts and answers to paste into App Store Connect and the Supabase dashboard. Anything in `[brackets]` needs your input. Prepared on 8 Nov 2026 for version 0.2.0.

## 1. TestFlight texts

Used under TestFlight > Test Information. The feedback email must be an address you read.

**Beta app description (English)**

> Wingspot is a logbook for planespotters. Check in aircraft you see, airports you visit and flights you take, collect badges, and follow friends. Check-ins work offline and upload later.

**Beta app description (German)**

> Wingspot ist ein Logbuch für Planespotter. Checke Flugzeuge ein, die du siehst, Flughäfen, die du besuchst, und Flüge, die du machst, sammle Abzeichen und folge Freunden. Check-ins funktionieren offline und werden später hochgeladen.

**What to test (English)**

> Thank you for testing Wingspot! Please try:
> 1. Sign in with your email (you get a link) and set your name.
> 2. Check in an aircraft you spot, an airport visit and a flight (you can scan a boarding pass; the name and booking code are never read). Add a photo.
> 3. Turn on airplane mode, check in, turn it off again: the check-in should upload by itself.
> 4. Profile tab: stats, collections, badges and the airports map. Tap an airport to see its page.
> 5. Settings (in the Profile tab): who sees your check-ins. It starts as "Only me". Switch to "Friends" or "Everyone" with a second account and look at People and Feed. Try salutes and comments.
> 6. Report something, block someone, and export your data.
> Tell us what is confusing, slow or broken: [feedback email].

**What to test (German)**

> Danke fürs Testen von Wingspot! Bitte probiere aus:
> 1. Melde dich mit deiner E-Mail an (du bekommst einen Link) und wähle deinen Namen.
> 2. Checke ein Flugzeug, einen Flughafenbesuch und einen Flug ein (du kannst eine Bordkarte scannen; Name und Buchungscode werden nie gelesen). Füge ein Foto hinzu.
> 3. Schalte den Flugmodus ein, checke ein und schalte ihn wieder aus: der Check-in sollte von allein hochgeladen werden.
> 4. Tab „Profil“: Statistik, Sammlungen, Abzeichen und die Flughafenkarte. Tippe einen Flughafen an, um seine Seite zu sehen.
> 5. Einstellungen (im Tab „Profil“): wer deine Check-ins sieht. Am Anfang steht „Nur ich“. Stelle mit einem zweiten Konto auf „Freunde“ oder „Alle“ und sieh dir Personen und Feed an. Probiere Salutes und Kommentare.
> 6. Melde etwas, blockiere jemanden und exportiere deine Daten.
> Sag uns, was unklar, langsam oder kaputt ist: [Feedback-E-Mail].

## 2. Notes for App Review

Paste into App Store Connect > App Review Information > Notes. Add a demo account (an email address that can receive the sign-in link, or a second one the reviewer can use) in the sign-in fields.

> Wingspot is a logbook for aircraft spotting. Sign-in uses an email link; there are no passwords. [Demo account and how the reviewer gets the link.]
>
> User-generated content (guideline 1.2): check-ins can be shared with friends or everyone (the default is "Only me"); comments and photos can be added. The user must accept the community rules before using any social feature (Feed tab, People, sharing). Comments pass a word filter.
> - Report: on a person's page, in the "..." menu of a feed card, with a long press on a photo, and by swiping a comment. Reports go to a table that is read daily; content that breaks the rules is removed within 24 hours.
> - Block: on a person's page ("Block"). Blocking ends follows both ways and hides both people's check-ins and comments from each other.
> - Account deletion (guideline 5.1.1(v)): Profile tab > Delete account, with two confirmations. It removes the account, its check-ins and its photos. Users can also export their data (Profile tab > Export my data).
> - The app asks for location only while checking in, to suggest a nearby airport; the position is not shown to others. The camera is used only to scan a boarding pass, on the device.

## 3. App Privacy answers

App Store Connect > App Privacy. Nothing is used for tracking, and everything is linked to the user.

| Data type | Used for | Collected? |
|---|---|---|
| Contact Info: Email Address | App functionality | Yes |
| Identifiers: User ID | App functionality | Yes |
| Contact Info: Name (the display name) | App functionality | Yes |
| User Content: Photos or Videos | App functionality | Yes (check-in photos) |
| User Content: Other User Content | App functionality | Yes (check-ins, comments, reports) |
| Location: Precise or Coarse | App functionality | Only if you sync the position of a check-in. Check [PRIVACY-DRAFT.md](PRIVACY-DRAFT.md) and answer the same way as the privacy policy |
| Identifiers: Device ID (the push token) | App functionality | Yes, if the person allows notifications. Apple does not always count push tokens as Device ID; declaring it is harmless |
| Diagnostics | | No, until crash reporting or analytics goes beyond Apple's own |

## 4. Sign-up emails in the user's language

The app sends the language (`de` or `en`) with the sign-in request, and Supabase stores it in the user's metadata. Supabase email templates can read it as `{{ .Data.language }}` and can use `{{ if eq ... }}` (checked in the Supabase documentation). The templates for the hosted project are set in the dashboard (Authentication > Email Templates); the local config doesn't touch them.

Use this body for both "Confirm signup" and "Magic Link", with the subject `Wingspot` for both:

```html
{{ if eq .Data.language "de" }}
<h2>Willkommen bei Wingspot</h2>
<p>Tippe auf den Link, um dich anzumelden:</p>
<p><a href="{{ .ConfirmationURL }}">Anmelden</a></p>
<p>Wenn du das nicht angefordert hast, kannst du diese E-Mail ignorieren.</p>
{{ else }}
<h2>Welcome to Wingspot</h2>
<p>Tap the link to sign in:</p>
<p><a href="{{ .ConfirmationURL }}">Sign in</a></p>
<p>If you didn't request this, you can ignore this email.</p>
{{ end }}
```

Anyone whose language is not `de`, or who has none stored, gets English. Test with a German and an English phone before the friends test.

## 5. Crash reporting and usage

Default for the friends test: **Apple's own crash reports** (TestFlight crash feedback and Xcode Organizer). They need no code, no extra privacy text and no agreement with another company. Look at them in App Store Connect > TestFlight > Crashes. Sentry or analytics can follow after the friends test, together with an update of the privacy policy.

## 6. Hosted project check (8 Nov 2026)

Supabase security and performance checks on the hosted project:

- **Security, expected:** tables with row security and no policies (`blocked_words`, `registration_prefixes`, `reports`, `store_events`) are meant to be closed to the app; the `SECURITY DEFINER` functions that signed-in users can call are the ones listed in `access_test.sql`; `get_profile` is open to anonymous visitors on purpose (public profile page).
- **Security, to do:** leaked password protection is off. It needs the Pro plan, and the app has no passwords, so it only matters if password sign-in is ever turned on.
- **Performance:** 20 unused indexes. They cover columns that later features will query and the tables are tiny, so they stay.
