# Wingspot to-do list

Last updated: 2026-11-04. Tick items off as you finish them.

## Do next

- [x] Send the licensing email to ICAO (draft at the end of this file)
- [ ] Start Phase 1 (iOS MVP)

## Your tasks

Only you can do these, because they need your accounts, money or judgement.

### Licensing

- [ ] Get ICAO's written answer on commercial use of the aircraft type data
- [ ] Optional: get a short opinion from a German IT or copyright lawyer, including the EU database right
- [ ] Before adding a national registry, check that registry's terms

### Accounts and services

- [x] Buy the domain `wingspot.site`
- [ ] Set up custom email sending (SMTP). Supabase's built-in email only reaches project team addresses and is heavily rate-limited
- [ ] Join the Apple Developer Program (before Milestone 2)
- [ ] Choose the final app ID: `app.wingspot.ios` today, `site.wingspot.ios` suggested (before Milestone 2)
- [ ] Create Apple sign-in credentials
- [ ] Publish a privacy policy and Impressum on `wingspot.site` (before Milestone 9)
- [ ] Create Google sign-in credentials (after the first TestFlight)

### Before real users sign up

- [ ] Turn on leaked password protection in Supabase
- [ ] Click a real confirmation email link from start to finish (not tested yet)
- [ ] Delete the test account you created on hosted

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

- [ ] Create `aircraft` rows from `POST /v1/checkins` (apps can't write to `aircraft` today)
- [x] Change the `aircraft.data_status` default to `user_submitted`
- [x] Add indexes for the 17 unindexed foreign keys
- [ ] Deploy that migration to hosted, with the next approved deploy
- [ ] Confirm the live functions use the publishable key, before legacy anon keys end at the end of 2026:
  - [ ] Update the signup test script, which still uses the anon key
  - [ ] Briefly deactivate the anon key and test
  - [ ] Remove the to-do from `backend/README.md`

### iOS and Android search

- [ ] Find hyphenated names when typed without the hyphen, such as `crj900` and `an124`
- [ ] Rank large airports first in search, such as `Wien`
- [ ] Handle registrations with no type or airline yet, on check-ins and badges

### Phase 1: iOS MVP ([PHASE1.md](PHASE1.md))

- [ ] Milestone 1: offline Spotted check-in
- [ ] Milestone 2: sign-in and profile
- [ ] Milestone 3: sync
- [ ] Milestone 4: badges and XP
- [ ] Milestone 5: Airport and Flown check-ins, boarding pass scan, one photo
- [ ] Milestone 6: your profile
- [ ] Milestone 7: social
- [ ] Milestone 8: airport page and settings
- [ ] Milestone 9: first TestFlight

### After Phase 1

- [ ] Phase 2: spotter features, Wingspot Pro and App Store 1.0
- [ ] Phase 2b: Android 1.0
- [ ] Phase 3: growth

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
