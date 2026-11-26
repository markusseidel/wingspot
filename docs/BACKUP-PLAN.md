# Backup and restore of data that lives only on the phone: plan for issue #310

Issue by vogtim: the routes of imported KML flights (and anything else kept only on the phone) are lost when the app is uninstalled, when the person changes phone, and when they switch between Android and iPhone. He asks for one backup file the person can save anywhere and restore later, on either platform. Status: plan agreed with Tim's answers (25 Nov 2026, section 9), nothing built.

## 1. What exists today, and what is really only on the phone

| Data | Where | Lost on reinstall or new phone? |
|---|---|---|
| Check-ins that reached the server (sightings, visits, flights, photos) | Server | No. A signed-in person gets them back (`CheckInRestorer` on iOS, `restore` on Android) |
| **Routes of imported KML flights** | One small file per check-in in `FlightTracks` (iOS, Application Support) and `flight-tracks` (Android, `filesDir`), named by the check-in id, in the same 4-byte-header-plus-16-bytes-per-position layout | **Yes.** By design: the raw route is never uploaded (the Flightradar24 terms, see the KML plan) |
| Check-ins made while signed out, and ones not sent yet (pending or refused) | The phone's check-in database | Yes until they are sent. A person who never signs in keeps their whole logbook only on the phone |
| Photos not sent yet | The phone's database | Yes until they are sent |
| Settings (distance unit, switches), the running spotting session | Phone preferences | Yes, and cheap to set again |
| Sign-in | The phone | Yes, and signing in again fixes it |

The Android beta is already signed with one fixed key (since build 2026112402, see `docs/ANDROID-BETA.md`), so updates keep the data. What is open is the phone change, the platform switch, and the person who uninstalls on purpose.

## 2. Decisions

1. **A file the person owns, not an upload.** The issue and the Flightradar24 terms agree: the backup never goes to the Wingspot server. It is a file saved through the system share sheet (Files, iCloud Drive, Google Drive, mail) and opened through the system file picker. No account is needed, so it works for signed-out people too.
2. **One format on both platforms.** Same schema, same file name rules, same tests on both (shared test vectors in `contracts/test-vectors/backup/`), so a backup made on Android restores on iPhone and the other way round.
3. **What is in version 1:**
   - the **routes** of flights (the thing that can be found nowhere else), and
   - the **check-ins that are only on this phone** (made signed out, or not sent yet), **without their photos**, so a person who never signed in does not lose the logbook.
   Not in version 1: photos (up to 4 per check-in, 3 MB each: the file would grow into the hundreds of megabytes), settings, the sign-in, the reference data (it is downloaded again). The export dialog says what is and is not inside.
4. **Format: one JSON file, compressed.** `Wingspot-backup-2026-11-25.wingspotbackup`, which is a gzip-compressed UTF-8 JSON document (`application/gzip` inside, a custom extension outside so Wingspot can be offered to open it). Open and documented: `manifest` (`format: "wingspot-backup"`, `schema: 1`, `created_at`, app and platform, counts) and then `routes` (one entry per flight: `checkin_id`, plus `flight_number`, origin and destination codes and the day, for the review screen only, and the route as a GeoJSON `Feature` with a `LineString` geometry of `[lon, lat]` pairs, so the `routes` list can be cut out as a GeoJSON `FeatureCollection` and opened in Google Earth, QGIS or geojson.io) and `checkins` (the local-only check-ins as the sync body already has them, `CheckinItem`). A ZIP of many files was considered (the issue suggests it) and not chosen: neither platform has a simple ZIP writer in its standard tools, and one document needs none. Positions are written with 5 decimals (about 1 m), which keeps 50 000 positions near 600 kB compressed.
   **The data outlives the app** (Tim's concern): the format is documented in `docs/BACKUP-FORMAT.md` (every field, the units, an example), and the file is plain gzip, so renaming it to `.json.gz` and unzipping it with any tool gives readable JSON. Nobody needs Wingspot to read their routes and check-ins back.
5. **Versioning.** `schema` is an integer. A newer app reads every older schema. An older app that meets a newer schema says "This backup was made by a newer version of Wingspot. Please update the app." and changes nothing.
6. **Restore merges, by id.** A check-in id is a UUID v7 that is the same on every device, so ids, not flight numbers and days, decide what is a duplicate:
   - a route whose check-in id already has a route on this phone is skipped, unless the person chooses "Replace routes";
   - a local check-in whose id is already here (or already on the server, which the restorer brings back) is skipped;
   - a route for a check-in this phone does not have yet is **kept** and shows up when the check-in arrives (after signing in and the restore of the server's check-ins). A route whose check-in was deleted on the server is dropped the next time the phone cleans up orphans.
   The result screen says what happened: "Restored 12 routes and 3 check-ins. Skipped 4 that were already here."
7. **A different account.** A route belongs to a check-in id, and ids are unique to one person's logbook, so a route can only attach to a check-in the phone has. Restoring into another account does no harm but restores nothing useful; the restore screen warns when it finds none of the backup's check-ins and the person is signed in.
8. **Privacy.** The file holds travel history. The export dialog says so, and the file is written into a temporary folder and removed after the share sheet closes. An optional password (AES-GCM, key from the password with PBKDF2) is possible and not in version 1: people who want it can save into an encrypted place.
9. **Android Auto Backup, as a complement (step 4, Tim: yes).** `allowBackup` is `false` today. Turning it on with explicit `dataExtractionRules` and `fullBackupContent` (include the check-in database and `flight-tracks`, exclude the sign-in, push token and caches) would restore on a new phone of the same Google account without any action. It needs the rules tested with `adb shell bmgr` and the sign-in storage checked first (a restored refresh token for a device that does not exist must not be restored). It is a second, separate step after the backup file, and it does not help when the person switches to an iPhone. iOS already includes the app's data in the device backup and in a phone-to-phone transfer; the file adds the platform switch.
10. **Play internal testing (option 2 of the issue)** is not part of this plan. One date matters for it: if the Android app goes to Google Play, the **upload key must be set as the app signing key during the first Play App Signing setup**, or the current testers have to reinstall once (the backup file is then the way to keep their routes). That decision has to be made before the first Play release.
11. **Where it lives in the app.** Settings, a new section **Backup**: "Create backup" (opens the share sheet), "Restore from backup" (opens the file picker). A file with the backup extension opened from Files or mail (iOS `onOpenURL` with a document type, Android `ACTION_VIEW`/`SEND` filter) starts the same restore. First-start prompt: the sign-in and onboarding screen gets a small link "Restore from a backup", shown only when the phone has no local data. The app does not ask on its own when it starts empty (Tim: the link is enough).

## 3. What the person sees

- **Settings > Backup > Create backup:** a sheet: "The backup holds the routes of your imported flights and the check-ins that are only on this phone. It does not hold photos. It contains your travel history: keep it somewhere private." [Create] opens the share sheet with the file.
- **Restore from backup:** the file picker, then a review: "Backup of 25 Nov 2026 from an Android phone: 42 routes, 3 check-ins that were only on that phone." with [Restore] and a switch "Replace routes I already have". Then the result line.
- **Errors, in words:** "This is not a Wingspot backup.", "This backup was made by a newer version of Wingspot. Please update the app.", "The file is damaged."

## 4. Implementation

- **Shared format, two implementations.** iOS: `Backup.swift` in the `Persistence` package (build from `FlightTrackFiles`, the check-in store, and a restore into both) with `Foundation`'s `NSData.compressed(using: .zlib)` plus a small gzip header, or the `Compression` framework. Android: `Backup.kt` in `core` with `java.util.zip.GZIPOutputStream`. Both pure functions over data, so they are tested without a phone against the shared vectors (a backup file written by one must be read by the other: the test vectors include a made-up backup that both read).
- **Local-only check-ins** are the rows with `syncState` pending or refused, or without an owner. Restore inserts them as pending (so they are sent when a person signs in), keeping the ids.
- **Routes** are written from `FlightTrackFiles` and read back with `save(_:for:)`; the stored files stay in the binary layout, the backup is only the transport.
- **UI:** `BackupSection` (iOS `SettingsView`) and `BackupSettings` (Android settings page); a `.fileExporter`/`ShareLink` on iOS and a `FileProvider` share with the existing `file_paths.xml` on Android; a document type and filter for the extension.
- **Strings** in English and German; the check-strings script passes.

## 5. Steps

| Step | What | Size |
|---|---|---|
| 1 | Format and shared vectors, the two codecs (`Backup`) with tests: write, read, older and newer schema, damaged file, merge rules | medium |
| 2 | Settings section, share sheet and file picker, restore review and result, on both apps | medium |
| 3 | Open the file from Files, mail and the share sheet; the first-start link | small |
| 4 | Android Auto Backup rules and `bmgr` test; the notes for the Play signing decision in `docs/ANDROID-BETA.md` | small |

Each step lands on iOS and Android together.

## 6. Tests

- Codec: a backup written and read back gives the same routes (to the written precision) and check-ins; the made-up vector file reads the same on both platforms; an unknown field is ignored; schema 0, schema 99, a truncated gzip and a JSON that is not a backup give the three error cases.
- Merge: a route for an id that has one is skipped, "Replace routes" overwrites it, a route for an unknown id is kept, a check-in already here is skipped, restoring twice changes nothing the second time.
- Phone: create a backup with three routes, remove the app data, restore, and the flight pages show the routes again; Android to iPhone with the same file.

## 7. Risks

- **Size of a long-haul flight's route.** Rounding to 5 decimals and compression keep it small; a backup of 100 flights stays in the tens of megabytes.
- **A restored check-in with a wrong time zone or id clash.** Ids are unique, so a clash only means the same check-in; restore skips it.
- **The backup is the only copy.** The export dialog and the result line say that the person has to keep the file; nothing reminds them (a "last backup" reminder is a later extra).
- **A hand-edited backup.** The reader checks every field (ranges, counts, the size limit of 100 MB) and ignores what it does not understand; it never runs anything from the file.

## 8. Not in the first version

Photos in the backup; a password; automatic backups to a chosen folder; a "last backup 30 days ago" reminder; backing up settings; restoring into a different account in a useful way.

## 9. Answered by Tim (25 Nov 2026)

1. **No photos.** They are stored on the server, so the backup does not need them. Version 1 as planned.
2. **Format:** what matters to him is that his data survives if Wingspot does not; an open, readable format inside the file is fine. So one gzip JSON file stays, with the routes as GeoJSON and the format documented in `docs/BACKUP-FORMAT.md` (decision 4). No ZIP.
3. **Android Auto Backup: yes**, as step 4.
4. **The restore link on the first-start screen is enough.** No prompt when the app starts empty.
