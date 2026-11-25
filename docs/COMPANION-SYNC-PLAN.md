# Companion Sync: take over a friend's flight: plan for issue #273

Issue by vogtim: friends fly together; today both log the same flight by hand. One person logs it and tags the other, who gets a request, accepts, and has the same flight in their logbook, without a second copy of the data entry. Status: plan only, nothing built.

## 1. What the issue asks for, and what already exists

Most of the building blocks are there since the friend tags ([FRIEND-TAGS.md](FRIEND-TAGS.md), steps 1a to 2). The issue is mostly about turning them into a flow, and about two things that are missing: the duplicate check and a request that can be accepted on any device.

| The issue asks for | Today | Gap |
|---|---|---|
| Tag companions on a flight, when logging it or later | Done: "With" row in the form and the edit screens, max 8, mutual friends only, switch "Friends may tag me" | none |
| A tagged friend gets a notification | Done: push `tagged` ("Jan tagged you on FRA → JFK"), in the inbox | The text says "tagged", not "wants to share this flight" |
| Accept or decline | Half: the tagged person sees the check-in at once (the tag grants viewing it) and can press **Add to my logbook** (accept) or **Remove me** (decline, and it sticks). There is no "request" screen | A clear request with two buttons, and a list of open requests |
| Accept creates the flight in the friend's account with the same flight data | Done on the phone: the app saves a local copy (route, day, flight number, registration, type) with `source_checkin_id`; the server keeps the link only if the caller is tagged and has no copy of it yet | The copy is made by the phone, so a second device, or a phone after a reinstall, does not know it was accepted and offers the button again |
| Decline creates nothing, nothing on the friend's profile before accepting | Done: a tag shows the check-in only to the tagged person; the author's check-in is not on their profile | none |
| Friend already has this flight: keep mine or replace the flight data | Not there. The flight form warns about a duplicate by flight number and day on the phone only, and "Add to my logbook" does not check at all, so a friend who logged the flight already gets a second copy | The detection and the two choices |
| Replace only the flight data, keep photos, notes, salutes, comments | Not there | A server step that changes only the flight columns |
| Both check-ins show each other as companions | The copy and the original are linked (`source_checkin_id`) and the tags show "With …" on the original | The copy should show the original's author as a companion, and the original the people who took it over |
| Notes and seat are not copied | Done | none |
| Only friends can be tagged, switch in Settings | Done | none |
| One feed entry for the whole group | No | See "Not in the first version" |

## 2. Decisions

1. **Option A, a copy with a link, stays.** It is what is built; every person owns and edits their own check-in, stats and badges are unchanged. The shared flight record (option C of the issue) is the cleaner model, but it is a rewrite of the check-in tables and belongs with the KML flight tracks, so it is a later step, not this one. Corrections of the original are not pushed to the copies; the "Replace flight data" button is how a friend takes a corrected flight over.
2. **A request is a tag that was not answered.** No new table. A request is: you are tagged on a flight or an airport visit, you have not removed yourself, and you have no check-in of your own with `source_checkin_id` pointing at it. Accepting is making that copy; declining is the existing **Remove me**. So the author is still not told about a decline, and cannot tag the person again on that check-in (the existing rule).
3. **What is taken over:** flight number, route, date and time, aircraft type and registration, distance. **Not taken over:** seat, cabin, notes, photos, salutes, comments, visibility (the friend's own sharing choice applies). The flight track (KML) only if the KML plan stores tracks on the server; until then it stays with the author, and the request page says nothing about it.
4. **The same flight** is, in this order: the same flight number on the same day; or the same route (origin and destination, either way round is a different flight) with a departure within 2 hours; the match works on `occurred_at` in UTC, so a flight around midnight is still found. The rule is one small function with test vectors, written once for the server and once for each app, and it is the rule the KML import's duplicate warning (#237) uses too, so the two never disagree. A flight with no flight number matches on route and time only.
5. **Accepting stays possible offline.** The phone still creates the copy itself (as today). Only the duplicate check needs the server, and without a connection it falls back to the phone's own flights, which cover everything the person logged on this device.
6. **Replace changes the flight columns only** (`flight_number`, `origin_id`, `destination_id`, `occurred_at`, aircraft registration and type, distance), keeps the id, photos, comments, salutes and notes, moves the flight's two airport visits with it (the same rule as editing the day of a flight), and links the check-in to the original. A flight the friend logged and a different one the author means are never merged without the friend choosing.
7. **Keep mine** only links the two check-ins as companions (sets `source_checkin_id` on the friend's existing flight).
8. **Push text:** the `tagged` notification stays, with new wording for flights and visits ("Jan wants to share FRA → JFK with you", German: "Jan möchte FRA → JFK mit dir teilen"). It opens the request.

## 3. What the person sees

- **Requests:** at the top of the inbox (the bell), a card per open request: "Jan flew FRA → JFK on 12 Aug · LH 400", with **Add to my logbook** and **Not me**. The same two buttons are on the friend's check-in page, replacing the single "Add to my logbook" button there. A request that was accepted or declined disappears from the list.
- **Already have it:** pressing **Add to my logbook** when a match exists shows a sheet: "You already logged LH 400 on 12 Aug." with **Keep mine** (link them) and **Replace the flight data** (and a line that photos, notes and comments stay), and Cancel. More than one match: the closest in time is shown.
- **After accepting:** the check-in page shows "With Jan", linking to the original. The original shows the people who took it over as companions, next to the people who were tagged.
- **Offline:** the buttons work; the check is against the phone's own flights, and the link is sent when the copy uploads.

## 4. Backend (one migration, one PR)

- `get_companion_requests()` (authenticated): the open requests as above: `(checkin_id, author id, username, display name, kind, occurred_at, flight number, origin and destination code and id, airport code, distance)`, newest first, at most 50. Reads only check-ins the caller is tagged on.
- `find_matching_flight(p_source uuid)`: the caller's own flights that match the source by the rule in decision 4, with the time difference, best first, at most 3.
- `link_companion(p_mine uuid, p_source uuid)`: sets `source_checkin_id` on the caller's own check-in when the caller is tagged on the source and no other check-in of the caller already points at it. Today the link can only be set when a check-in is first uploaded.
- `replace_flight_data(p_mine uuid, p_source uuid)`: as decision 6, in one transaction, then the link as above; returns the new flight data so the app can update its own copy. Refuses a check-in that is not the caller's flight, a source the caller is not tagged on, and a source that is not a flight.
- `get_checkin_companions(ids uuid[])`: for check-ins the caller can see, the people whose check-in points at it with `source_checkin_id` (the copies' owners who are friends of the caller or the author), so the original can show them. It follows the visibility rules that already decide who sees a check-in.
- `private.flight_match(...)`: the one SQL matching rule, shared by the functions above.
- Contract: the new functions are called through `/rest/v1/rpc` like the others; no change to `CheckinItem`.
- pgTAP: requests list only what the caller is tagged on and has not answered; removed, copied and blocked ones are gone; matching by number and day, by route and time window (±2 h, midnight in UTC), no match for a different route; codeshare found by route and time; link only when tagged and only once; replace changes the flight columns and nothing else (photo, comment, salute stay), moves the airport visits, and refuses a foreign check-in; companions follow visibility; the access test lists the new functions.
- Deploy: database first. Old apps ignore the new functions.

## 5. iOS and Android (one PR each, the parity rule)

- A `FlightMatch` helper with the rule from decision 4 and the same test vectors as the SQL, used by the new request flow and by the KML import warning.
- Requests in the inbox (iOS `InboxView`, Android inbox page), the two buttons on the friend's check-in page, the "already logged" sheet, the "With" line on the copy (link to the author) and the companions line on the original.
- Accepting: as today, a local copy with `source_checkin_id` (so it works offline); with a match and **Keep mine** only the link is saved, with **Replace** the local flight is updated through a new store function (`replaceFlightData`: route, day, number, aircraft, distance, and the airport visits of the flight) and uploaded as an ordinary edit.
- The Wingman badge is unchanged: a copy still counts as a check-in done together.
- Strings in English and German. Tests: the matcher, the store function (photos and notes stay), the inbox rows, the outbox carries the link.

## 6. Order of work

1. Backend PR: migration, functions, pgTAP. Deploy.
2. iOS and Android PRs together, then both builds with the tester text and the release note for each platform.
3. Click-through on both apps with two test accounts that are friends: tag, accept, decline, accept with a match (keep, replace), accept offline, a copy on a second device, a flight around midnight UTC.
4. Use the matcher in the KML import warning (#237) when that part is built.

## 7. Not in the first version

- **One feed entry for a group** ("Jan and Tim flew DOH → FRA"). It needs the feed to know that two check-ins are the same flight (the link exists) and a rule for which one is shown; it is a feed design on its own and is best done after this, with the shared flight record.
- **The shared flight record** (issue option C), with the facts stored once and personal parts per person. Comes with the KML flight tracks.
- **Photos taken over** from the author. They are the author's pictures; a friend adds their own.
- **Taking over the flight track** before tracks are stored on the server.
- **Companion sync for spotting sessions** (#218).
- **Updating the copies when the original is corrected** automatically (option B behaviour). **Replace flight data** covers it by hand.
- **Auto-accept** ("always add flights this friend tags me on").

## 8. Questions for the owner and Tim

1. Is the **Add to my logbook** button of today what Tim means by "accept", or did he not find it? The plan keeps the tagged person's view of the check-in and adds the request card and the duplicate check; is that the right amount?
2. **Decline:** the plan uses the existing "Remove me", which sticks and the author is not told. Fine, or should the author hear it?
3. **Photos** of the author are not taken over (decision 3). Agree?
4. **Same flight rule:** same number and day, or same route within 2 hours. Is 2 hours right (a delayed flight is still the same flight)?
5. **One feed entry for the group** is left for later. OK?
