# Friends on flights and airport visits

Issue [#182](https://github.com/markusseidel/wingspot/issues/182) ("Flown with Friends"). You add the friends who were with you when you log a flight or an airport visit. Everyone tagged can see the check-in, get told about it, take themselves off it, and later add the same flight to their own logbook.

## 1. Why

- People fly and spot together. A check-in should say so.
- A tag is a personal reason for a friend to open the app, and each friend who adds the flight logs another check-in.
- It gives the **Wingman** badge in the concept (§5, "check in together with a friend") a rule that needs no guessing from places and times.
- It feeds a later statistic: "most flown with" in [EXTENDED-STATS.md](EXTENDED-STATS.md).

## 2. Rules

These decide what is allowed, and the server enforces all of them, not only the apps.

| Rule | Why |
|---|---|
| Only **mutual friends** (you follow each other) can be tagged | No tagging strangers, no spam |
| At most **8** people per check-in | Keeps lists short and abuse small |
| Only the **author** of a check-in changes its tags | |
| Tagging someone lets **that person see that one check-in**, whatever its visibility. The picker says so ("Anna will see this check-in") | Most accounts default to private. If tagging needed a visible check-in, it would not work for most users |
| A tagged person can **remove themselves** at any time. The author is not told and cannot tag them again on that check-in | Consent: nobody is pinned to a flight they weren't on |
| A person can turn off **being tagged** in Settings. They then don't show in the picker for others | Control |
| **Blocking** removes tags in both directions and blocks new ones. **Unfriending** removes the tags between the two | A tag only lives while it is a friendship |
| Deleting a check-in deletes its tags. Deleting an account deletes the tags it made and the ones on it | |
| Tags are shown to everyone who can see the check-in, as a name that links to the profile | |
| Old app versions ignore tags | Additive change |

## 3. What the user sees

- **Logging a flight or an airport visit:** a "With" row in the form. It opens the friends list with a search field and checkmarks. The row shows the names chosen. The same row is in the edit screens, so tags can be added or changed later.
- **Check-in page:** a "With" line with the names. Each name opens the person's profile. If you are tagged, a "Remove me from this check-in" button.
- **Feed cards and lists:** one line under the title, "With Anna, Max", for check-ins that have tags.
- **Offline:** the friends list is cached after it was loaded. The tags are saved with the check-in on the phone and go up with it.

## 4. Data

### 4.1 Server (migration `20261120400000_friend_tags.sql`)

```
checkin_tags
  checkin_id  uuid  references checkins on delete cascade
  user_id     uuid  references profiles on delete cascade   -- the tagged person
  created_at  timestamptz default now()
  primary key (checkin_id, user_id)
  index on (user_id)

profiles.allow_tags boolean not null default true           -- "friends may tag me"
```

- Row level security: a tag can be read by the author of the check-in, by the tagged person, and by anyone who may see the check-in. Nobody writes tags directly; the functions below do it as the owner of the functions.
- A second read policy on `checkins` lets a tagged person see the check-in they are tagged on, as long as the author is still a friend and not blocked. Every function that reads check-ins as the caller (the check-in page, the feed, lists) then shows it with no further change.
- A trigger removes a person's tags between two people when a follow is deleted or a block is added.

### 4.2 Functions

| Function | Does |
|---|---|
| `sync_checkins(items)` | An item may carry `with`: an array of user ids. For the owner's own check-in it replaces the tag set (ids that are not mutual friends, that don't allow tags, that removed themselves, or more than 8 are ignored). Without the key, tags stay as they are |
| `get_checkin_tags(ids uuid[])` | For check-ins the caller can see: `(checkin_id, user_id, username, display_name)`, in tag order, so lists and pages fetch them in one call |
| `remove_my_tag(checkin uuid)` | The caller leaves a check-in. It remembers the choice, so a later upload by the author does not add them again |
| `get_taggable_friends()` | The caller's mutual friends who allow tags, for the picker |

`removed` choices are kept in `checkin_tag_removals (checkin_id, user_id)`.

### 4.3 Contract and apps

- `contracts/openapi.yaml`: `with` on `CheckinItem`.
- iOS `LocalCheckIn.taggedIDs: [UUID]?` and Android `checkins.tagged_ids` (comma separated ids). Both open an existing store without a migration step. The outbox sends them as `with`.
- A check-in without tags sends no `with`, so existing uploads don't change.

## 5. Notifications (step 1b)

A new notification kind `tagged`: "Jan tagged you on FRA → JFK" (German: "Jan hat dich bei FRA → JFK markiert"). It follows the existing rules: not for yourself, not between blockers, at most 30 a day, once per person and check-in. A switch in Settings, "Friends tag me", default on. It needs the `send-push` function deployed with the new text, so it ships as its own step after tags are in the apps.

## 6. Steps

| Step | What | Status |
|---|---|---|
| 1a | Tables, rules, functions, sync; picker, display and "Remove me" on iOS and Android; setting "Friends may tag me" | done (#191) |
| 1b | Push notification `tagged` with its Settings switch ("Friends tag me"), `send-push` text | done |
| 2 | "Add to my logbook" for the tagged person, and the Wingman badge | done |
| 3 | "Most flown with" in the extended statistics | later, with the extended statistics |

### Step 1b: the notification

- Migration `20261120500000_tag_notifications.sql`: kind `tagged`, `notification_prefs.tagged` (default on), `queue_notification` knows the kind, and a trigger on new rows in `checkin_tags`. Only newly added tags notify, so uploading the same list again tells nobody again.
- `send-push` writes "Jan tagged you on FRA → JFK." (German: "Jan hat dich bei FRA → JFK markiert."). Tapping it opens the check-in, like the other kinds.

### Step 2: add to my logbook and Wingman

- Migration `20261120600000_tag_copies_and_wingman.sql`: `checkins.source_checkin_id`. The upload may carry `source_checkin_id`. The server keeps it only when the caller is tagged on that check-in and has no copy of it yet; otherwise the check-in is stored without the link, so an upload never fails over it.
- The apps show "Add to my logbook" on a friend's flight or airport visit you are tagged on. It saves a local copy (route, date, flight number, registration, type; for a visit the reason is "Spotting", to be changed in Edit) linked to the original. The button turns into "In your logbook" once the copy exists on the phone. A flight creates its two airport visits as usual.
- Not covered: a copy made on another device, or before a reinstall, is not known to the phone, so the button shows again. The server still refuses a second link, so the copy would be an unlinked duplicate that the person can delete.
- Wingman (`wingman`, levels 1, 5, 10, 25): the check-ins you did together with friends, as the author or as a tagged friend. Like all badges it only goes down when you delete a check-in.

## 7. Tests

- Database: tagging works only for mutual friends; blocked, unfriended and tags-off people are ignored; the limit of 8; replacing the set on a second upload; no `with` keeps the tags; the tagged person sees a private check-in, others still don't; leaving a check-in sticks; blocking and unfriending remove tags; deleting the check-in deletes its tags.
- iOS and Android: the outbox sends `with` only when there are tags; the local store keeps them across edits; the picker's choice round trip; contract test for the new field.

## 8. Risks

- **A private check-in becomes visible to more people.** Only to the people the author picks, and the picker says so. Removing a tag removes the access.
- **Tag spam.** Mutual friends only, limit of 8, a switch to opt out, and "Remove me" that sticks.
- **Offline and unsynced tags.** Tags ride on the check-in upload, so they can't arrive before it.
- **Two apps drift.** Same field names, same rules in the database, same screens.

## 9. Decisions taken

- Tagging grants view access to that check-in (option A).
- Mutual friends only.
- Version 1 was tags with display and "Remove me"; the notification and "Add to my logbook" followed in steps 1b and 2.
- No free-text names for people without the app.
