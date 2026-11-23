# Collections: drill-down per entry and a flights tab: plan for issue #274

Issue by vogtim. Part A: tapping an aircraft, type or airport in the profile's collections shows all your check-ins that contain it. Part B: a fourth tab "Flights" lists all your flights. Both can be sorted by the date of the flight or by the date of the check-in, ascending or descending (default: flight date, newest first). Status: plan only, nothing built.

## What exists today

- **The collections are worked out on the phone** from the check-ins saved there (`CheckInCollections` on iPhone, `Collections` on Android, "with the same rules as the stats"). Nothing comes from the server, so a reinstall gets them back through the restore of your check-ins.
- **What is counted:** every check-in of the signed-in person and those made before signing in, without rejected ones (`CheckInStats.counted`). An aircraft entry counts check-ins with that registration (sightings and flights), a type entry the ones with that type code, an airport entry every check-in that is not a flight and has that airport. A flight has no airport of its own; its two airport visits are check-ins of their own, so they count (this is the issue's "airport visits created by flights").
- **iPhone:** the airport and type rows open the page for that airport or type, which lists everybody's check-ins you may see, not your own. The aircraft rows do nothing. **Android:** no row does anything. So Tim's "can't be opened" is exactly true on Android and half true on iPhone.
- **The rows in the history** ("Check-in history") are not tappable either; they only show the sync state.
- **A local check-in has a flight date but no entry date.** `occurredAt` is the date of the sighting or flight (the person can pick it). The id is made from that date too, so it tells nothing about when the check-in was entered. The server has `created_at`, but that is when it first arrived, and the phone does not keep it.
- **Opening a check-in:** the check-in page loads a check-in from the server by id (as the inbox and push do). A check-in that is only on the phone (waiting or refused) has no server page.
- **Android loses its place:** the collections page keeps its tab in a `remember` that is gone when another page is pushed on top, so going back would start on the first tab at the top.

## Recommendations

1. **One shared rule for "which check-ins belong to this entry".** A function next to the collections code, used by both the count and the list, so "the number of listed check-ins matches the ×N count" cannot drift apart. Tested with the same fixtures on both platforms.
2. **Part A, one generic screen** with a kind (aircraft, type, airport) and a key. Header: the entry (registration and type name; type code and name; airport name with codes), the count, first and last seen. List: compact rows like the history (route or aircraft, detail, date), newest first. The header also links to the page everybody sees for it (registration, type or airport page), so the existing iPhone navigation to the public airport and type pages is not lost.
3. **Part B, a "Flights" tab** with all flown check-ins: route, flight number, aircraft, date, distance. The distance is worked out from the airports on the phone like the stats do, shown when both airports are known.
4. **Sorting:** a menu with "Flight date" and "Check-in date" and a direction, default flight date newest first, on the drill-down list and the flights tab. The choice is remembered (like the feed sort).
5. **Check-in date = when it was saved on this phone.** A new field `savedAt` is set when a check-in is created. For check-ins that already exist it falls back to the time they reached the server (`syncedAt`), and if that is missing too, to the flight date. So for old check-ins the two sorts can look alike. The honest alternative, the server's `created_at`, would mean sending a second timestamp through the restore and the upload for little gain; this is cheaper and exact for everything made from now on.
6. **Tapping a row:** an uploaded check-in opens its check-in page. One that is only on the phone shows its sync state (waiting or not accepted) and does not open, because there is no page for it yet. Going back returns to the same tab, sort and scroll position (on Android the tab, sort and list position are kept in the view model).
7. **Tabs on small screens and big text:** four segments do not fit at large text sizes. A row of chips that scrolls sideways (like the Android tabs today), or a menu when it does not fit on iPhone.

## Build, both apps (same changes)

| Step | Content | Size |
| --- | --- | --- |
| 1 | The shared rule and the sort, the `savedAt` field (SwiftData and SQLite columns, set on create, kept on restore), unit tests on both platforms | medium |
| 2 | Part A: the drill-down screen and the taps in the collections, both apps | medium |
| 3 | Part B: the flights tab and the sorting menu, both apps | medium |

No backend change, no deploy. Strings in German and English. A click-through on both apps with check-ins that have flights, sightings, visits created by flights, waiting and refused ones.

## Risks

- **Counts and lists must agree.** Covered by building both from one rule and a test that compares them for every entry in a mixed fixture.
- **A big list:** hundreds of check-ins for one airport are fine in a lazy list; the sort works on what is already in memory.
- **The new column on an old database:** both platforms already add columns to old databases (a test exists on Android, SwiftData handles optional properties).

## Decisions needed (owner)

1. **Check-in date** as the time it was saved on this phone (recommended), with the fallback for old check-ins as above?
2. **Check-ins only on the phone** are shown but do not open (recommended)?
3. **Keep a link to the public page** in the drill-down header (recommended), so the page everybody sees stays reachable?
4. **Remember the sort** between visits (recommended), or start on the default every time?

## As built

Decisions as recommended (check-in date = saved on this phone, phone-only rows shown but not opened, link to the public page kept, sort remembered). No backend change.

- **Shared logic** (`CheckInCollections` in Persistence, `Collections` in Android core): one private rule says which entries a check-in belongs to, used by the counts, by `checkIns(of:key:)` and by the tests that compare the list with the count of every entry; `flights`, `DateKind` and `ordered` (the chosen date, then the other date, then the id, so equal dates never flicker). `LocalCheckIn.savedAt` is set when a check-in is created (spotted, airport visit, flight and the visits it creates); `enteredAt` is saved here, else uploaded, else the flight date. A new nullable `savedAt` (SwiftData) / `saved_at` (SQLite, added to old databases) column.
- **iPhone:** the collections screen has four chips (Aircraft, Types, Airports, Flights) that scroll sideways, entries open `CollectionDetailView` (header with the count, first and last date and a link to the public page; the list of check-ins; the sort menu), the flights tab lists all flights with the distance from the airports on the phone. A row opens the check-in page when the server has the check-in (`CheckInLoaderView` fetches it by id); one that is only on the phone shows its sync state.
- **Android:** the same, with the tab, the place in the list and the place in each detail list kept in the view model (going back from a detail page or a check-in shows the same tab and position), the sort kept in the preferences.
- **Tests:** Persistence and Android core tests for the list matching the count of every entry, the airport list with the visits a flight created and without refused check-ins, the flights list, both sorts in both directions, the check-in date fallbacks.
- **Checked on the Android emulator and the iPhone simulator** with the local test check-ins: tabs, the detail page, the flights tab and the sort menu. Not tried: a long list scrolling back to the same place, and opening a check-in that is on the server (the test check-ins are all waiting to upload).
