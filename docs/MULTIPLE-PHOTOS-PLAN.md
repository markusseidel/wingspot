# Several photos at once: plan for issue #271

Issue by vogtim: when creating a check-in only one photo can be picked, and more can only be added one at a time in the edit screen. Status: built (see "As built").

## What the issue asks for

Pick several photos at once when creating and when editing a check-in; thumbnails with remove before saving; the first one as the cover; upload that keeps the check-in and the other photos when one fails; a maximum number of photos; one shared component for create and edit.

## What already existed

- **The limit is 4 per check-in**, on the server (`checkin_photos`, the upload refuses the fifth) and on both phones (`maxPhotos`, `MAX_PHOTOS`). It is also what the edit screens use, so the issue's "same limit as in the edit flow" is 4.
- **Every photo is its own entry** (`LocalPhoto` on iPhone, a row in `photos` on Android), kept on the phone with its check-in and uploaded in the background after the check-in is accepted. Failed requests leave a photo waiting and it is tried again; only the server's answer can reject one, and that does not touch the check-in or the other photos. So the "upload robustness" part of the issue already holds.
- **Shrinking and removing metadata** happens on the phone for every photo before it is kept.
- **iPhone had one shared component** (`PhotoSection`) for all create and edit forms, but it held one photo. **Android had one shared `PhotoField`** per file with the same limit of one photo.
- **The feed already shows several photos** as a carousel in upload order, so the first photo is the cover.

## Decisions

1. **Reorder is left out.** Photos keep the order they were picked in (each one millisecond later than the one before, because the id is made from the time and the upload goes oldest first). A reorder needs an order field on the server; it can come later if testers ask.
2. **No per-photo progress bar.** Photos are prepared on the phone and uploaded in the background after saving; a bar would show almost nothing. A photo the server refuses stays marked as refused on the phone and does not block the rest.
3. **Maximum 4, unchanged.** In the edit screens the picker offers only what is left (4 minus the photos the check-in already has).

## As built

No backend change.
- **iPhone:** `PhotoSection` takes a list of photos and a limit. It uses `PhotosPicker` with `maxSelectionCount` and ordered selection, shows thumbnails with a remove button, and skips a picture it cannot read without losing the others. The drafts (`SpottedDraft`, `AirportDraft`, `FlownDraft`) carry `photos`; `CheckInStore.addPhotos` adds several to a saved check-in as far as there is room. All create and edit forms use it.
- **Android:** `PhotoField` takes the list and the limit, uses `PickMultipleVisualMedia` (the single picker for the last free place, because the multiple picker needs a maximum of at least 2), thumbnails with a remove button. The view model's save functions take lists, and photos are added in order.
- **Strings** in German and English. **Tests:** Persistence tests for several photos saved with a check-in in order, the limit, and adding later as far as there is room.
- Not tested yet on a device: the pickers and the thumbnails.
