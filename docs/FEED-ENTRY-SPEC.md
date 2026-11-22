# Feed entry: shared spec and plan

Issue [#257](https://github.com/markusseidel/wingspot/issues/257) (Android feed looks different from iOS). One description of a check-in entry for both apps, and the steps to get Android there. The iOS card is the reference ([FeedScreen.swift](../ios/Wingspot/Features/Feed/FeedScreen.swift), `FeedCard`); the Android card is `FeedCard` in [SocialScreens.kt](../android/app/src/main/kotlin/site/wingspot/app/SocialScreens.kt).

The same card is used in three lists on each platform (Feed, a person's check-ins, Explore). One change covers all three.

## Spec

Order of the elements, top to bottom. Every element appears on both platforms.

| # | Element | Rule |
|---|---|---|
| 1 | Header | Avatar (28 pt), name, date, ⋯ menu. The name is **black and bold** (your own entries say "You"). It opens the person's page but is not coloured. The date is small and grey, at the right, before the menu |
| 2 | Kind | A small icon and the label in small grey text: plane "Flown", building "Airport", binoculars "Spotted" |
| 3 | Main line | Monospaced, semibold, title size. Flown: `ORIGIN → DESTINATION`. Airport: the code. Spotted: the registration, otherwise the type. It opens the airport, registration or type page, as today |
| 4 | Detail line | Small grey text, parts joined with " · ", always in this order. Flown: flight number, then the registration (the type name when there is no registration), then the distance. Spotted: type name, airport code. Airport: none |
| 5 | Friends and badges | "With ..." line, then one line per badge: a round 24 pt symbol (a white glyph on a circle whose colour grows with the level, the same glyph per category on both platforms), the badge name in semibold, and "Level n" in grey for a levelled badge. Never an emoji: the glyph is a vector that is part of the app |
| 6 | Photos | One photo: full width, 200 high, rounded corners 10. Several photos: a **carousel**, one photo per page, swipe sideways, a row of dots below with the current dot in the accent colour. All pages have the same height, so the list does not jump. A tap opens the full-screen viewer at that photo |
| 7 | Actions | Salute icon and count, comment icon and count, small, in the accent colour, 20 apart. The salute icon is filled once you have saluted. Each has a 44 pt / 48 dp touch area. The comment icon opens the check-in page |
| 8 | Separator | A thin divider between entries. No card background, no shadow |

Spacing: 6 between the elements inside an entry, 4 above and below the entry (plus the divider).

**Colours:** the accent colour is only for actions (salute, comments, the ⋯ dots, links such as the main line when it opens a page). Names, labels and the detail line are never coloured.

**Menu (⋯):** shown when there is at least one item.
- Edit details: your own flights that can be edited.
- Delete: your own check-ins, with a confirmation.
- Report: other people's check-ins, with the report dialog.
- Photos: a long press on a photo gives "Report photo" for other people's photos.

The check-in page keeps its own menu.

**Date rule (both platforms):** relative for the last 7 days ("3 days ago", "gestern"), after that a short date with the month abbreviated ("15 Sept 2013" / "15. Sept. 2013"). The year is left out when it is the current year. A backdated flight therefore shows its real date, not "13 years ago".

## What differs today

| | iOS | Android |
|---|---|---|
| Container | plain row, list separator hidden | `Card` with 16 dp padding |
| Name | black, bold | accent colour |
| Kind | icon and label | text label |
| Menu | ⋯ on every entry | none (menu only on the check-in page) |
| Actions | icon and count | `OutlinedButton` / `FilledTonalButton` and a text button |
| Photos | strip of all photos | first photo only, full width |

Target on both: the carousel in element 6.
| Date | always relative ("13 years ago") | relative for a week, then a date |
| Detail line (flown) | flight number, registration or type name, distance | type name, flight number, distance |
| Badge symbol | SF Symbol per category, white on a coloured circle | emoji per category on a coloured circle |

The date rule above is what Android does already (Android's relative-time helper). iOS changes to match.

## Plan

Small steps, iOS and Android together as usual, both clicked through. Each step is its own PR.

| PR | Content | Size |
|---|---|---|
| 1 | This spec, the date helper on iOS, and the photo carousel on iOS (replaces the strip) (one function, with tests for "5 minutes", "3 days", "9 days", a date in this year, a date in an earlier year) | small |
| 2 | Android card: detail line in the shared order, badge glyphs as vectors instead of emoji, plain row with divider, black name, kind icon, compact salute and comment icons with counts and 48 dp touch areas, the photo carousel. New vector drawables from Material Symbols (Apache 2.0), not copies of Apple's symbols | medium |
| 3 | Android ⋯ menu on the card. The report dialog, the delete confirmation and the edit start now live in the check-in page; move them into one shared piece that the card and the page both use. Clicked through in all three lists | medium |
| 4 | Side-by-side screenshots against the acceptance criteria in the issue, and a note on the issue | small |

## Acceptance

- Same information in the same order on both platforms (the table above).
- Type icon, compact salute and comment icons and the ⋯ menu on Android.
- One date rule on both platforms.
- An Android entry is about as tall as the same entry on iOS. Without the card padding and the 48 dp button row, a text-only entry gets roughly a third shorter.
- Material details stay on Android: touch feedback, system navigation, touch areas of at least 48 dp.

## Open

- The glyph for each badge category on Android: one white vector per category that looks like the iOS symbol (own drawing or Material Symbols, not a copy of Apple's symbols). The list of categories is the one in `BadgeStyle.swift`.
- The exact icon set for salute on Android (there is no clapping-hands symbol in Material Symbols; a hand or a salute drawn as our own vector).
- Whether the iOS entry should also grow a visible touch area for the name, since it is no longer coloured.
