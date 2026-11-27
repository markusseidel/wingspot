# Automatic backup to iCloud Drive: plan

Follow-up to the backup file (#310, [BACKUP-PLAN.md](BACKUP-PLAN.md), format in [BACKUP-FORMAT.md](BACKUP-FORMAT.md)). Today a person makes a backup by hand: Settings > Backup > Create backup, then the share sheet. The owner asked whether the iPhone app can back up to iCloud on its own. Status: decided (section 7), not built yet.

## 1. What exists, and the gap

| | Covers | Gap |
|---|---|---|
| Backup file by hand (built) | Any phone, both platforms, the person's own storage | The person has to remember it; the routes of a KML import made since the last backup are lost with the phone |
| iPhone iCloud Backup (iOS, built in) | The whole app data, automatically, when the phone has iCloud Backup on | Only to an iPhone, only when the whole phone is restored, and many people have it off (5 GB free) |
| Android Auto Backup (built) | Logbook and routes to a new Android phone of the same Google account | Not to an iPhone; not testable on the emulator yet |

The gap on the iPhone: an up-to-date copy that a person can restore **without restoring the whole phone**, and that an Android phone or a fresh install can read too.

## 2. Goal

- A switch **Back up to iCloud Drive automatically** in Settings > Backup (and on the signed-out Backup page). On: Wingspot keeps the latest backup file in the person's iCloud Drive, in a folder **Wingspot** they can see in the Files app.
- Below the switch: "Last backup: today, 10:42" or why it could not be made ("iCloud Drive is off for Wingspot").
- **Restore from iCloud Drive** on a new or reset iPhone: the restore review offers the file found there, with no searching. The first-start link "Restore from a backup" shows it first.
- The file is the same `.wingspotbackup` as by hand, so it can be copied to an Android phone and restored there.

## 3. Decisions

1. **iCloud Drive, not CloudKit.** A file in the app's iCloud Drive folder (a ubiquity container) needs no schema, no server code and no CloudKit dashboard, is visible to the person in Files, and is the same format as the manual backup. CloudKit sync of routes between devices is a bigger, separate step and not needed while the server already syncs check-ins.
2. **Off until the person turns it on.** The file holds travel history; it goes to the person's iCloud, never to the Wingspot server, so the Flightradar24 terms are kept as with the manual backup. The privacy policy gets one sentence: "If you turn on iCloud backup, Wingspot saves a backup file in your iCloud Drive. Apple stores it; Wingspot cannot read it."
3. **When it writes.** After a KML import (one or several files), after a restore, after the outbox sends or refuses check-ins that were only on the phone, and at most once a day when the app comes to the foreground and something changed since the last backup. Never while the person waits: it runs in the background after the change, debounced by 30 seconds. A change is detected by a small fingerprint (route ids and file sizes, ids and states of the phone-only check-ins), so an unchanged logbook writes nothing.
4. **What it keeps.** The latest file, `Wingspot-backup-<device>.wingspotbackup`, plus the one before it (`Wingspot-backup-<device>-previous.wingspotbackup`), so a damaged or empty write never leaves nothing. It is written to a temporary name and moved over the old one with `NSFileCoordinator`.
5. **Several iPhones on one Apple ID.** Each phone writes its own file, named with a short device label the person sees in Settings (for example "iPhone 16 Pro", changeable), so two phones never overwrite each other. Restore lists the files it finds, newest first.
6. **Restore merges, as today.** The same `BackupService.restore`: nothing is deleted, routes already here are kept unless the person chooses to replace them.
7. **iCloud off or full.** The switch shows why it cannot back up ("iCloud Drive is off", "iCloud storage is full") and the manual backup keeps working. Nothing is retried in a loop; the next trigger tries again.
8. **Android.** Android already has the automatic part through Auto Backup (Google's backup of the logbook and routes). An automatic file in Google Drive would need a Google Drive sign-in and API access for a small gain; it is **not** part of this plan. If parity in the visible switch matters, Android gets the same switch writing the file into a folder the person picks once (Storage Access Framework, persisted permission): a local folder, an SD card, or a cloud app that offers folders (Nextcloud, OneDrive; Google Drive does not offer folder access this way). The owner decided on Auto Backup only (section 7).

## 4. iOS work

- **Capability:** iCloud with iCloud Documents and a container `iCloud.site.wingspot.ios`, in the Apple developer portal and in `project.yml` (`com.apple.developer.icloud-container-identifiers`, `com.apple.developer.icloud-services: [CloudDocuments]`, `com.apple.developer.ubiquity-container-identifiers`), and `NSUbiquitousContainers` in Info.plist with `NSUbiquitousContainerIsDocumentScopePublic` true and the name "Wingspot", so the folder shows in Files. New provisioning profiles follow with `-allowProvisioningUpdates`.
- **`ICloudBackup`** (app target, `@MainActor @Observable`): the switch (UserDefaults), `url(forUbiquityContainerIdentifier:)` read off the main thread, `scheduleBackup()` with the debounce, `backupNow()` using `BackupService.make` and `BackupCodec.encode`, coordinated write and rotation, `lastBackup` and `problem` for the UI, and `availableBackups()` via `NSMetadataQuery` (files not yet downloaded are started with `startDownloadingUbiquitousItem`).
- **Triggers:** the KML import and batch import, `BackupRestoreView` after a restore, the sync coordinator after an upload, `scenePhase == .active` (once a day).
- **UI:** the switch and the last-backup line in `BackupSection`; the restore review gets a list "In iCloud Drive" above "Choose a file…".
- **Strings** in English and German; privacy policy sentence; the App Store privacy answers do not change (data stays with the person).

## 5. Tests

- Unit: the fingerprint changes only when routes or phone-only check-ins change; the rotation keeps the previous file when a write fails; the debounce writes once for a burst of imports. `ICloudBackup` takes the folder as a parameter, so tests use a temporary folder instead of iCloud.
- Device (the simulator's iCloud is unreliable): sign in to iCloud, turn the switch on, import a KML, check the file in Files > iCloud Drive > Wingspot; delete the app, reinstall, restore from the list; turn iCloud Drive off for Wingspot and check the message; two iPhones on one Apple ID write two files.

## 6. Steps

| Step | What | Size |
|---|---|---|
| 1 | Capability and container in the portal and `project.yml`; a build that still uploads to TestFlight | small (needs the owner in the developer portal if automatic signing cannot create the container) |
| 2 | `ICloudBackup` with fingerprint, rotation, tests | medium |
| 3 | Switch, last-backup line, restore list, triggers, strings | medium |
| ~~4~~ | ~~Android folder switch~~: dropped, Android keeps Auto Backup only (section 7) | |

## 7. Decided by the owner (2026-11-27)

1. Android: Auto Backup only. No folder switch, so step 4 is dropped.
2. Keep the latest and the previous file.
3. The switch is off by default; the person turns it on.
