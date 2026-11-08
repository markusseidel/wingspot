# Milestone 10: push notifications (plan)

Done when: a tester gets a notification on their iPhone when someone follows them, salutes their check-in or comments on it; each kind can be turned off; tapping opens the right screen; and nothing is sent to people who blocked each other or switched it off.

Items marked **you** can only be done by the project owner.

## What exists

- Server: `devices` table and `register_device()` (one row per app install with the push token and `sandbox` or `production`), `notification_prefs` (salutes, comments, new followers; friend badges and others for later). The export leaves push tokens out and deleting an account removes its devices.
- App: nothing yet. It never asks for permission, never registers for remote notifications and never sends a token. There is no push entitlement.

## 10a. Apple setup (**you**, about 10 minutes)

1. developers.apple.com > Certificates, Identifiers & Profiles > Keys > **+**. Name it "Wingspot push", tick **Apple Push Notifications service (APNs)**, continue, register, and **download the `.p8` file** (Apple lets you download it once). Note the **Key ID** shown on that page.
2. Keep the file out of the repository and out of chat. The team ID is `Z6K89AW5QT`.
3. After I have built 10b, store the key on the server with these commands (the key never leaves your Mac except to Supabase):

```bash
supabase secrets set APNS_KEY="$(cat ~/Downloads/AuthKey_XXXXXXXXXX.p8)" APNS_KEY_ID=XXXXXXXXXX APNS_TEAM_ID=Z6K89AW5QT --workdir backend
```

The App ID `site.wingspot.ios` gets the Push Notifications capability automatically when the app is archived with the new entitlement (automatic signing). TestFlight builds use Apple's production push service; builds run from Xcode use the sandbox one.

## 10b. Server (built: one migration and one Edge function)

- **Outbox:** a table `notifications` (recipient, type, actor, check-in, created, sent). Database triggers add a row when someone follows you, salutes your check-in or comments on it. No row when the actor is the recipient, when either has blocked the other, or when the recipient has switched that kind off in `notification_prefs`.
- **Sending:** the function `send-push` takes unsent rows, writes the text in the recipient's language (from `devices.locale`; German or English), signs a token with the key from 10a and calls Apple's push service for each of the recipient's iOS devices. It removes a device when Apple says the token is dead, and marks the row sent. It is called by a database trigger right after the insert (`pg_net`), and a minute-by-minute job picks up rows that were missed.
- **Floods:** several salutes on one check-in replace each other on the phone (Apple's collapse ID) instead of piling up; at most 30 notifications a day per person.
- **Content:** names and a short text only: "Anna followed you", "Anna saluted your check-in at FRA", "Anna: [first 80 characters of the comment]". The payload carries the type and an ID so the app can open the right screen. Nothing about a hidden check-in or a sensitive aircraft's registration is ever included.
- **Built as:** migration `20261108100000_push_notifications.sql` (table `notifications`, triggers on `follows`, `salutes` and `comments`, `claim_notifications` and `finish_notification` for the service role only, a `pg_net` call to the function after each insert and a `pg_cron` job every minute for leftovers) and the function `send-push` (`apns.ts` writes the texts, signs the token and sends; `index.ts` checks the secret, claims rows and reports back). A row is tried at most 5 times and dropped after a day. One device that gets it is enough; a dead token removes the device.
- **Deploy steps (after you say so; hosted is production):** push the migration, deploy `send-push`, then create a shared secret and store it twice: as the function secret `PUSH_SECRET`, and in the Vault as `push_secret` next to `push_url` (the function's address). Until both Vault entries exist the database calls nothing.
- **Tests:** database tests for each rule above (self, blocked, switched off, friends-only check-in, comment on a hidden check-in); function tests with a fake Apple server for the text, the language, a dead token, and "no key set" (it must not crash and must leave rows unsent).

## 10c. App

- Ask for permission **in context**, not on launch: after the first follow, salute or comment, or in Settings > Notifications, with a short explanation first. If the user says no in the system dialog, Settings shows a link to the system settings.
- Register for remote notifications, send the token with `register_device` on launch and whenever it changes, and remove it on sign-out (so the next account on the phone doesn't receive the old one's notifications).
- Settings > Notifications: three switches (follows, salutes, comments), stored in `notification_prefs`.
- Tapping a notification opens the check-in's comments, or the person's page for a follow. A notification for something that is gone or no longer visible opens the Feed.
- Strings in English and German. Entitlement `aps-environment` added to the app.

## 10d. Release

- Update the privacy policy (push token, Apple as the delivery service) and the App Privacy answers in [TESTFLIGHT.md](TESTFLIGHT.md). Apple lists the push token under "Device ID" only if it is used for something other than delivery; decide with the privacy text.
- Test on a real iPhone with two accounts (Simulator can't receive real push). Deploy the migration and functions only after you say so; hosted is production.
- Build number up, archive, upload.

## Risks

- **No key, no push:** until you set the secrets, the app and the outbox work but nothing is sent. Rows stay unsent and go out once the key is there; I will cap how old a row may be so an old backlog is not sent at once.
- **Spam and abuse:** blocking removes follows and stops notifications; the daily cap limits harm. Muting a person is not part of this milestone.
- **Privacy:** push goes through Apple. Texts contain a username and a short snippet, so they can show on a lock screen; Settings says so.
