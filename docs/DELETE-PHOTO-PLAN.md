# Delete a single photo of a check-in: plan for issue #272

Issue by vogtim: a single photo (for example a duplicate) cannot be removed. The only way is to delete the whole check-in, which also loses its salutes and comments. Status: plan only, nothing built.

## What the issue asks for

Delete single photos from your own check-in; the check-in, its other photos, salutes and comments stay. A confirmation or undo first. The file is removed from storage for good, not just the link, and the photo disappears from the check-in, the feed and the detail view. Deleting the last photo keeps the check-in. Only the owner can do it.

## What exists today

- **Rows and files are separate.** A photo is a row in `checkin_photos` (id, check-in, `storage_path`, size, `position`) and a file in the private `photos` bucket, named `<user>/<check-in>/<photo id>.jpg`. A phone uploads with `PUT /v1/checkins/{id}/photos/{photo id}` (the `checkins` function), which stores the file and calls `register_photo`.
- **Nothing deletes a single photo**, on the server or in the apps.
- **No file is ever removed except by deleting the account.** `delete_checkin` deletes the check-in and its photo rows by cascade, and its own comment says "the photo files in storage are not touched here". Only `DELETE /v1/me` removes the files. So a deleted check-in leaves its files in storage. Nobody else can read them (the read rule needs a row), and the app never lists them, but the file is there, which is exactly what the issue's privacy point is about. The same gap exists today for deleted check-ins.
- **Deleting a database row cannot remove the file.** A SQL `delete` on `storage.objects` only removes the listing, not the stored object, so the file has to be removed through the Storage API from a function that holds the service key (as `DELETE /v1/me` does).
- **Apps:** the check-in page shows the photos and has a context menu per photo with "Report photo" for other people's photos (iPhone, and a Report button on Android). For your own photos there is no entry. A phone keeps each photo as a local entry with the same id as the server photo.
- **A small bug the delete would trigger:** `register_photo` gives a new photo `position = number of photos`. After deleting one of three (positions 0, 1, 2), the next photo would get position 2 again and the order would be wrong. It must be the highest position plus one.

## Decisions

1. **Remove the row first, then the file, through a queue.** A trigger on `checkin_photos` (after delete) writes the file path into a small queue table. A function empties the queue with the service key. So the photo is gone for everybody the moment the row goes, and a failed file removal is retried, not lost. The same queue then also covers deleting a check-in (rows go by cascade), which fixes the gap above. The other order (file first) could leave a row that points at a missing file and shows a broken image.
2. **Confirmation, not undo.** The file is removed for good, so "Delete this photo? It is removed for good." with Delete and Cancel. An undo would mean keeping the file for a while, which is the opposite of the issue.
3. **Where:** the check-in page, next to "Report photo": "Delete photo" in the photo's context menu on iPhone and a Delete button on Android (the Report button's place), only on your own check-ins. The edit screens stay as they are (they add photos; showing server photos there is a bigger change that can come later).
4. **Online only.** Deleting asks the server and shows an error if there is no connection. A queue of offline deletions is more work and not needed for a first version. A photo that is still only on the phone (not uploaded yet) is removed locally at once.
5. **Old orphans:** a one-time step puts the files of already deleted check-ins (listed in `storage.objects` with no row) into the queue, so they are removed too.

## Backend (one migration, one function change, one PR)

- Migration: `private.photo_files_to_remove` (path, created_at), trigger after delete on `checkin_photos`, `delete_photo(photo_id)` (security definer: owner only; deletes the row; returns the path or nothing), `register_photo` position fix, a one-time insert of the orphans.
- `checkins` function: `DELETE /v1/checkins/{id}/photos/{photo id}` calls `delete_photo` and then empties the queue (a `remove-photos` step with the service key; the queue is also emptied after `delete_checkin`, and once a day as a safety net).
- Contract (`contracts/openapi`) and api-test; pgTAP tests: owner can delete, someone else cannot, deleting the last photo keeps the check-in, the queue gets the path, cascade from a deleted check-in queues all its paths, position after a delete, repeated delete is harmless.
- Deploy: database first, then the function, then the app builds.

## iOS and Android (same changes on both)

1. The API call `deletePhoto(checkIn, photo)`; on success remove the photo from the check-in page and from the feed state at once (the feed card and the carousel update; a stale signed URL in a cache only works until it expires and no longer points at a row).
2. "Delete photo" with the confirmation, only for your own check-ins; an error message when it fails.
3. Remove the local copy of the photo (its entry on the phone) so the room for photos is counted right and nothing is uploaded again.
4. Strings in German and English, and a click-through on both apps against the local stack.

## Size

| PR | Content | Size |
| --- | --- | --- |
| 1 | Backend: migration, function, tests, contract | medium |
| 2 | Both apps: delete on the check-in page, state updates, strings | medium |

## Risks

- **A retried upload after a delete:** a phone that still holds the deleted photo as pending would upload it again. The local entry is removed on delete, so only a second device could do it, and it cannot, because only the owner's phone has the entry.
- **Reports:** a photo that was reported and then deleted: the report keeps its text target; moderators see a missing photo. Acceptable; the report stays.
- **Queue failure:** if the function is down, files stay in the queue and go with the next run (the daily safety net).

## Open questions (owner)

1. Online only for the first version (recommended)?
2. Delete on the check-in page only (recommended), or also in the edit screens?
3. Include the old orphan files in the clean-up (recommended)?

## As built

Decisions as recommended (online only, the check-in page only, old orphan files included).

- **Migration `20261123100000_delete_photo.sql`:** `private.photo_files_to_remove` (the queue), a trigger on `checkin_photos` that queues the path of every deleted row (a deleted photo or a deleted check-in), `delete_photo(photo)` for signed-in people (owner only), `queued_photo_files()` and `photo_files_removed(paths)` for the service role only (the first drops a path whose photo row is back, so a live file is never removed), the `register_photo` position fix (highest position plus one), and the one-time queueing of stored files without a photo row that are older than an hour.
- **`checkins` function:** `DELETE /v1/checkins/{id}/photos/{photo id}` (204, also when the photo is gone or isn't yours) and `POST /v1/checkins/cleanup-photos`. Both empty the queue through the Storage API, best effort and in batches of 100; a failure leaves the paths queued. No wake-up call from the database and no schedule: the queue is emptied by every photo delete and by every check-in delete from an updated app, and old apps' check-in deletes are picked up by the next one.
- **Apps:** a delete action on your own photos on the check-in page (context menu on iPhone, a button on Android) with a confirmation, an error message if it fails, the photo gone from the page and the feed at once, this device's copy removed so the room for photos is right. Deleting a check-in now asks the server to remove its files too.
- **Tests:** pgTAP (owner only, the queue, a returning photo, positions, cascade from a deleted check-in, who may call what), API tests (the row, the file really gone from storage, someone else's delete does nothing, sign-in needed, the clean-up after a deleted check-in), the iPhone and Android stores, and the local copy of a photo.
- **Not done:** deleting while offline, and removing existing photos in the edit screens (both listed as later).
