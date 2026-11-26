# Minimum age 16: plan

Question from the owner: does the age of the people using Wingspot matter? It does: plane spotting draws many teenagers, Wingspot has public content, comments, following, photos and locations, and the drafts of the privacy policy and the terms say "not aimed at children under [16]" without the app asking anything. The owner decided: **the minimum age for an account is 16.** Status: decided, being built. This is not legal advice; the texts get a lawyer's look before the public launch.

## 1. Why 16

- **GDPR Art. 8:** where processing relies on consent (push notifications, location), consent of a child needs the parents below 16 in Germany (other EU countries set 13 to 16). With 16, no parental consent process is needed anywhere in the EU.
- **App stores:** Wingspot has user content, comments, following and locations, so its store rating is a teen rating or higher anyway. A 16+ rating matches the rule.
- **Simple:** one age for the whole app, no special settings for younger users.

## 2. Decisions

1. **What needs 16:** an **account**. Signed out, Wingspot is a logbook on the phone: nothing goes to the server, nobody sees anything, so it stays open to everyone, like a notebook. The age question comes where data starts going to the server and to other people: signing in.
2. **How it is asked: a confirmation, not a proof.** The community rules screen that every account already sees once after signing in (iOS `TermsGate`, Android `TermsScreen`) gets a second point: a switch **"I am 16 or older"**. "I agree" stays disabled until it is on. No date of birth is asked: Wingspot does not need it, and a birthday is personal data that would have to be stored and protected. An ID check is not proportionate for a hobby app and is not required.
3. **Recorded on the server.** Today the agreement is kept only on the phone (per account, `TermsStore` with a version). It moves to the account: a new column `profiles.terms_accepted` (version) and `profiles.age_confirmed_at` (timestamp), set by one RPC `accept_terms(p_version int)` that also records the age confirmation. So a second phone or a reinstall does not ask again, and there is a record of when the person confirmed. The phone keeps its local copy for offline use.
4. **Existing accounts are asked once.** The rules version goes from 1 to 2. Everyone sees the screen again with the new switch at their next start; until they confirm, the social parts stay behind the gate as for a new account (the logbook keeps working, check-ins are kept and sent later).
4a. **Old app versions.** A build from before this change never shows the question, so an existing account could keep using it without confirming. The server already holds a minimum version per platform (`app_config.min_version_ios` / `min_version_android`, sent by `/v1/config`), but **neither app enforces it today**: iOS only logs it, Android does not read it. So this release also adds the **update screen**: when the installed build is below the minimum, the app shows "Please update Wingspot" with a button to TestFlight / the App Store or the Android download, and the social parts stay closed (the logbook keeps working, as with the age gate). After the release is out, the minimum is raised to it. Builds older than this release cannot be stopped this way; today they are a few known testers, who are asked to update in the release note. For later, stronger: the server refuses social writes (follow, comment, salute, sharing check-ins with others) from accounts without `age_confirmed_at`, which also covers old and modified apps.
4b. **Accounts that do not come back.** An existing account whose owner never opens a new build never confirms; its profile and public check-ins stay visible. **For now nothing happens to them**: the accounts are a small group of known testers. **Once Wingspot is public**, accounts without a confirmation after a deadline (3 months from the release that asks) are hidden from search, the Feed, Explore and the leaderboard until they confirm. Nothing is deleted, and confirming shows them again at once. The deadline and the hiding are a separate small step, decided before the public launch.
5. **Someone younger.** A second button **"I'm younger than 16"** explains: "Wingspot accounts are for people 16 and older. You can keep using Wingspot without an account: your check-ins stay on this phone." with **Sign out** and **Delete my account** (the existing deletion). Nothing is reported or stored about the answer.
6. **Reports about age.** The report reasons get "This person seems to be younger than 16". A confirmed case leads to the existing account deletion, by hand, after a look at the account. The terms say so.
7. **Texts.** Terms: a new point "**Age.** You must be 16 or older to have a Wingspot account." Privacy policy: the placeholder becomes "Wingspot accounts are for people 16 and older. If we learn that an account belongs to someone younger, we delete it." Both in German and English, and the `[16]` placeholders in both drafts are filled in.
8. **Stores.** App Store Connect: age rating questionnaire answered for user content, social features, location and unrestricted comments; Apple's 16+ rating. Google Play: content rating questionnaire (IARC) the same way, target audience **16 and older**, not part of the Families programme. No ads, so no ad settings for minors are needed.
9. **Not now:** the age signals of the stores (Apple Declared Age Range, Google Play Age Signals). They matter for US states that require them (Utah, Texas) and for a store launch there; the plan records it as a check before publishing in the US store.

## 3. Work

| Part | What |
|---|---|
| Backend | Migration: `profiles.terms_version int`, `profiles.age_confirmed_at timestamptz`; RPC `accept_terms(p_version)` (sets both for the caller); `get_my_terms()` or the fields in the existing own-profile read; pgTAP (only the caller, the version only goes up, anon refused). The account export includes both fields. |
| iOS | `TermsGate`: the switch, "I agree" disabled until on, the "younger" path; read and write the server fields, local copy as fallback; version 2. Strings EN/DE. |
| Android | `TermsScreen` and `TermsStore` the same; strings EN/DE. |
| Update screen | Both apps compare their build with `min_version` from `/v1/config` and show the update screen; tested with a raised minimum on a local backend. After the release: the minimum is raised (one SQL update, done by the owner's yes). |
| Reports | New reason `underage` in both apps and the review list (moderation). |
| Docs | TERMS-DRAFT.md and PRIVACY-DRAFT.md updated; a line in the App Store and Play checklists. |
| Stores | Questionnaires done by the owner in App Store Connect and the Play Console before the next public release. |

One PR for the backend (deploy first, old apps ignore the new fields), then one PR per app, merged together, then both builds with the release note "Wingspot accounts are for people 16 and older: please confirm once."

## 4. Tests

- Backend: `accept_terms` sets the caller's row only; a lower version does not overwrite a higher one; anon is refused; the export carries the fields.
- Apps: "I agree" stays off until the switch is on; an account with version 1 sees the screen again; an account confirmed on another phone does not; offline the local copy lets the app start; the "younger" path signs out and keeps the local check-ins.
- By hand on both phones: new account, existing account, second phone, the younger path, the new report reason.

## 5. Decided by the owner (2026-11-26)

1. Signed-out use stays open to everyone (decision 1): **yes**.
2. Confirmation switch without a date of birth (decision 2): **yes**.
3. The "younger" path offers **Delete my account** directly, next to **Sign out**.
