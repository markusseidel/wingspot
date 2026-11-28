# UX rules audit: iOS and Android

This plan checks the Wingspotted iPhone app (`ios/Wingspot/`, SwiftUI) and Android app (`android/app/`, Jetpack Compose) against 15 common mobile UX rules. It lists what each app does today and what to change. No app code has been changed yet.

Code names stay `Wingspot`. Line numbers are from `main` at commit `ef56b05`.

Status words:

- **Yes**: the rule is followed.
- **Partly**: the rule is followed in some places, or only in part.
- **No**: the rule is not followed.
- **Not verified**: there is no app code for it, and it depends on system behaviour that still needs a check on a device.

## Summary

| # | Rule | iOS | Android |
|---|---|---|---|
| 1 | Pull to refresh reloads | Partly | No |
| 2 | Swiping from the left edge goes back | Yes | Yes |
| 3 | "Create" sits in the middle of the tab bar | Yes | Partly |
| 4 | Home far left, Profile far right | Yes | Yes |
| 5 | At most 5 tabs | Yes | Yes |
| 6 | X closes a sheet or flow; left arrow goes back | Partly | No |
| 7 | No empty screens: empty states say what to do next | Partly | Partly |
| 8 | Important buttons in the lower half | Partly | Partly |
| 9 | Tap targets at least 44 × 44 pt / 48 dp | Partly | Partly |
| 10 | Tapping the active tab again scrolls to the top | Not verified | No |
| 11 | Standard symbols only (magnifier, gear, bell) | Partly | Partly |
| 12 | Every action gets immediate feedback | Partly | Partly |
| 13 | Red only for delete and errors; Undo after deleting | Partly | Partly |
| 14 | Ask for permissions only when needed, with a reason | Yes | Partly |
| 15 | Sign in with Apple or Google, not only email | Yes | Yes |

The biggest gaps:

1. **No Undo after deleting**, on either app (rule 13).
2. **Android has no pull to refresh** (rule 1), **no back arrow or close X icons** (rule 6), **no haptics** (rule 12) and **no scroll to top** (rule 10).
3. **Android asks for notifications right after sign-in**, with no reason given (rule 14). iOS does this well.
4. **Android's middle tab opens a page with a second "Check in" button.** iOS opens the form straight away (rule 3). This is also a parity gap.
5. **iOS has several tap targets below 44 pt** in the Feed (rule 9).

## Findings per rule

### 1. Pull to refresh reloads

**iOS: Partly.** `.refreshable` is on the Feed (`ios/Wingspot/Features/Feed/FeedScreen.swift:223`), Badges (`ios/Wingspot/Features/Badges/BadgesScreen.swift:82`), Activity (`ios/Wingspot/Features/Social/Inbox.swift:158`), People (`ios/Wingspot/Features/Social/PeopleView.swift:145`), the check-in page (`ios/Wingspot/Features/Feed/CheckInDetailView.swift:168`), alert rules, spot review and release notes. It is missing on Explore, Profile, a person's page, Collections and Check-in history.

**Android: No.** There is no pull to refresh anywhere. Lists end with a "Refresh" text button instead: Feed (`android/app/src/main/kotlin/site/wingspot/app/SocialScreens.kt:172`), Badges (`BadgeScreens.kt:127`), Activity (`InboxScreens.kt:52`, only after an error).

### 2. Swiping from the left edge goes back

**iOS: Yes.** Every tab has its own `NavigationStack`, so the system edge swipe works. The back button is hidden only on the result screen after saving a check-in (`ios/Wingspot/Features/CheckIn/AirportCheckInView.swift:56`, `FlownCheckInView.swift:118`, `SpottedCheckInView.swift:48`). That is on purpose: going back would reopen a form that was already saved.

**Android: Yes.** The system back gesture is handled for pages and for the check-in form (`android/app/src/main/kotlin/site/wingspot/app/AppScreen.kt:103-104`).

### 3. "Create" sits in the middle of the tab bar

**iOS: Yes.** "Check in" is the middle of five tabs (`ios/Wingspot/App/RootView.swift:32`). Tapping it opens the check-in sheet straight away and does not switch tabs (`RootView.swift:101-112`).

**Android: Partly.** "Check in" is in the middle (`AppScreen.kt:111-114`), but it is a normal tab. It shows a page with another "Check in" button and the recent check-ins (`AppScreen.kt:177-184`). That is one extra tap, and it does not match iOS.

### 4. Home far left, Profile far right

**iOS: Yes.** Feed is first, Profile is last (`RootView.swift:26-40`).

**Android: Yes.** Same order (`AppScreen.kt:110-114`). Note: the `Tab` enum lists them in a different order (`SocialViewModel.kt:23`), but only the list in `AppScreen.kt` sets what is shown.

### 5. At most 5 tabs

**iOS: Yes.** Five tabs: Feed, Explore, Check in, Badges, Profile (`RootView.swift:5-7`).

**Android: Yes.** The same five (`AppScreen.kt:111-114`).

### 6. X closes a sheet or flow; a left arrow goes back one screen

**iOS: Partly.** Going back uses the system back chevron. Sheets and flows close with a "Cancel" text button, not an X: the check-in sheet (`ios/Wingspot/Features/CheckIn/CheckInSheet.swift:83-84`), edit views (`ios/Wingspot/Features/Feed/CheckInEditView.swift:108`, `FlownEditView.swift:119`), boarding pass scanner (`BoardingPassScanning.swift:51-52`), report sheet, terms, backups, KML import. "Cancel" fits Apple's guidelines when it throws away input. An X fits better where nothing is lost, such as the check-in type picker. The photo viewer already uses an X (`PhotoViewer.swift:39`).

**Android: No.** There is no top app bar, and no arrow or X icon exists in `res/drawable`. Back is a text button "‹ Back" (`ProfileScreens.kt:472`, copied in `CompareScreens.kt:51`, `InboxScreens.kt:43`, `InviteScreens.kt:67`, `LeaderboardScreens.kt:56`, `PeopleScreens.kt:93`, `SpotScreens.kt:281`, `SocialScreens.kt:450`). The check-in form closes with a "Cancel" text button at the bottom (`CheckInScreen.kt:772`). The photo viewer closes with a "Close" text button (`SocialScreens.kt:840`).

### 7. No empty screens: empty states say what to do next

**iOS: Partly.** Most screens use `ContentUnavailableView`, and the empty Feed has a "Find people" button (`FeedScreen.swift:157-163`). Gaps:

- Signed out, Feed and Badges only say "Sign in from the Profile tab". There is no button (`FeedScreen.swift:137-141`, `BadgesScreen.swift:20-24`).
- Check-in history says "Your check-ins will appear here", with no button to check in (`ios/Wingspot/Features/CheckIn/CheckInHistoryView.swift:21-25`).

**Android: Partly.** `EmptyState` (`Theme.kt:143`) with a button is used only when signed out (`AppScreen.kt:215`, `BadgeScreens.kt:67`, `ProfileScreens.kt:127`). Signed in, the empty states are plain text with no button:

- Empty Feed: "Nothing here yet. Follow people…" (`SocialScreens.kt:165`). iOS has a "Find people" button here.
- Badges filter: "No badges here yet" (`BadgeScreens.kt:124`).
- Activity: title and text only (`InboxScreens.kt:54-56`).
- The Check in tab with no check-ins shows only the button, which is fine.

### 8. Important buttons in the lower half of the screen

**iOS: Partly.** Starting a check-in is in the tab bar, at the bottom. But:

- The "Check in" button that saves is the last row of a scrolling form, so it is often off screen (`AirportCheckInView.swift:111`, `FlownCheckInView.swift:269`, `SpottedCheckInView.swift:111`).
- "Save" in the edit views and the profile editor is at the top right (`CheckInEditView.swift:109-110`, `FlownEditView.swift:120-121`, `ProfileEditorView.swift:139-140`).

**Android: Partly.**

- The "Check in" button on the Check in tab is at the top of the page (`AppScreen.kt:179`).
- "Save" is at the end of the scrolling form (`CheckInScreen.kt:769-773`), so it is also often off screen.

### 9. Tap targets at least 44 × 44 pt (48 dp on Android)

**iOS: Partly.**

- The three Feed header icons (sort, find people, bell) are 32 × 32 pt (`FeedScreen.swift:114-116`).
- The announcement dismiss X is 32 × 32 pt (`FeedScreen.swift:480-483`).
- Salute and comment on a feed entry are small borderless labels in `.subheadline` (`FeedScreen.swift:325-337`). They are well under 44 pt high. The whole row also opens the check-in, so a near miss opens the page instead.
- "Restore from a backup" on the onboarding screen uses `.controlSize(.small)` (`OnboardingView.swift:35-37`).

**Android: Partly.** Most targets are 48 dp: menu buttons (`SocialScreens.kt:260`, `PeopleScreens.kt:96`), the bell (`SocialScreens.kt:142`), salute and comments (`SocialScreens.kt:288-290`). The announcement dismiss button is set to 40 dp (`AnnouncementsViewModel.kt:93`). Compose may still give it a 48 dp touch area; check this in the Layout Inspector.

### 10. Tapping the active tab again scrolls to the top

**iOS: Not verified.** There is no app code for it (no `ScrollViewReader` or `scrollPosition`). SwiftUI's `TabView` runs on UIKit, which may pop back to the first screen of a tab when it is tapped again. Whether it also scrolls to the top needs a check in the Simulator: scroll the Feed, tap Feed again.

**Android: No.** Tapping a tab only sets it (`AppScreen.kt:116`), so tapping the active tab does nothing. Also, the tab bar is hidden on every page above the tabs (`AppScreen.kt:109`), so a tab tap can never jump back to a tab's first screen. On iOS the tab bar stays visible there.

### 11. Standard symbols only: magnifier = search, gear = settings, bell = notifications

**iOS: Partly.** Search uses a magnifier (`ios/Wingspot/Features/Explore/ExploreScreen.swift:53`), Activity uses a bell (`FeedScreen.swift:57`), and sort and find people use standard SF Symbols. Settings is a text row in Profile (`ios/Wingspot/Features/Account/ProfileScreen.swift:181`), with no gear. Salute uses `hands.clap`, an app-specific idea, but it has a clear accessibility label.

**Android: Partly.** Search uses a magnifier (`ExploreScreens.kt:98`, `AppScreen.kt:305`) and Activity uses a bell (`SocialScreens.kt:142-147`). But:

- The "more" menu is often the text character "⋮" (`PeopleScreens.kt:96`, `CheckInScreen.kt:881`, `SocialScreens.kt:453`, `SocialScreens.kt:687`), even though `ic_glyph_more` exists and is used once (`SocialScreens.kt:261`).
- Back is the text "‹" (rule 6). Sort is the text "▾" (`SocialScreens.kt:154`).
- Settings is a text button in Profile (`ProfileScreens.kt:159`), with no gear.
- The Feed has no "Find people" icon, unlike iOS (`FeedScreen.swift:54`).

### 12. Every action gets immediate feedback

**iOS: Partly.** There is a success haptic after a check-in (`CheckInResultView.swift:54`, `AirportCheckInView.swift:181`, `FlownCheckInView.swift:536`) and for a new badge (`CelebrationView.swift:48`). Salute updates the screen at once (`ios/Packages/Account/Sources/Account/Feed.swift:462`). Loading shows a `ProgressView`. There is no haptic for salute, follow or delete.

**Android: Partly.** Salute updates the screen at once (`SocialViewModel.kt:314-318`). Buttons show a `CircularProgressIndicator` while working (for example `AppScreen.kt:263`). There are no haptics anywhere in the app.

### 13. Red only for delete and errors; offer Undo after deleting

**Red: Partly on both.** Delete buttons and errors are red on both apps. Exceptions:

- iOS draws the arrival marker of a flight route in red (`ios/Wingspot/Features/Feed/CheckInDetailView.swift:729`). This is a clear break of the rule.
- Both apps show a red unread mark on the bell: iOS with `bell.badge.fill` in `.multicolor` (`FeedScreen.swift:57-58`), Android with the error colour (`SocialScreens.kt:149`). This is the normal platform pattern, but it breaks a strict reading of the rule. **The owner decides** whether to keep it red or make it the brand orange.
- Android draws "New invite code" in red (`InviteScreens.kt:134`). It makes the old code stop working, so red is fair here.

**Undo: No on both.** Deleting a check-in, a photo or a comment asks first in a dialog, then deletes at once. iOS: `FeedScreen.swift:74`, `ios/Wingspot/Features/Feed/CheckInDeletion.swift:12`. Android: `CheckInScreen.kt:891-898`, `CheckInViewModel.kt:388-393`, `SocialScreens.kt:281`. There is no Undo.

### 14. Ask for permissions only when needed, with one sentence on why

**iOS: Yes.**

- **Notifications**: asked once, after the first follow, salute or comment (`ios/Packages/Account/Sources/Account/Push.swift:211-218`). An alert explains why before the system asks (`RootView.swift:75-80`).
- **Location**: asked when an airport or spotting check-in opens, to suggest the airport (`AirportCheckInView.swift:57`, `SpottedCheckInView.swift:49`). The reason is in `ios/Wingspot/App/Info.plist:143-144`.
- **Camera**: asked when the boarding pass scanner opens. The reason is in `Info.plist:145-146`.

**Android: Partly.**

- **Camera**: a screen explains why, then asks on tap (`BoardingPassScanner.kt:74-80`). Good.
- **Location**: asked only when "Show airports near me" is tapped, with a note (`ExploreScreens.kt:192-194`). Good.
- **Notifications**: the system prompt appears right after sign-in, with no reason given (`AppScreen.kt:67-78`). This breaks the rule, and it does not match iOS.

### 15. Sign in with Apple or Google, not only email and password

**iOS: Yes.** Sign in with Apple (`ios/Wingspot/Features/Account/AppleSignInButton.swift:13`) is offered in onboarding (`OnboardingView.swift:23`) and in Profile (`ProfileScreen.swift:81`). Email works with a link or a password. There is no Google sign-in.

**Android: Yes.** Sign in with Google (`AppScreen.kt:244-246`) and email with a link or a password. There is no Apple sign-in.

So neither app offers both. Two risks:

- Someone who signed up on iPhone with Apple and "Hide My Email" can't easily sign in on Android. The sign-in link goes to Apple's relay address, and Apple forwards it only if the sending domain is registered with Apple.
- The Google button shows only if `WINGSPOT_GOOGLE_CLIENT_ID` or the Gradle property `wingspotGoogleClientId` is set at build time (`android/app/build.gradle.kts:28-30`, `GoogleSignIn.kt:16`). If a release build is made without it, Android offers email only.

## What to change

Every fix lands on both apps in the same PR, so they stay alike. Effort: **S** = under half a day, **M** = one or two days, **L** = several days or backend work.

### A. Tap targets (rule 9): S

- iOS: make `headerIcon` 44 × 44 (`FeedScreen.swift:115`) and the announcement dismiss button 44 × 44 (`FeedScreen.swift:482`). Give salute and comment a 44 pt high frame with `.contentShape(Rectangle())` (`FeedScreen.swift:325-337`). Drop `.controlSize(.small)` from "Restore from a backup", or give it a 44 pt minimum height.
- Android: set the announcement dismiss button to 48 dp (`AnnouncementsViewModel.kt:93`).

### B. Android notification ask (rule 14): S

- Copy the iOS trigger: ask once, after the first follow, salute or comment.
- Show an `AlertDialog` with the same text as iOS ("Wingspotted can tell you when someone follows you…"), with "Turn on" and "Not now". Only "Turn on" starts the system prompt.
- Remove the ask from the sign-in `LaunchedEffect` (`AppScreen.kt:75-78`). Keep `Push.register` there.
- Add a `socialActionHappened()` call to the follow, salute and comment paths in `SocialViewModel.kt`, keyed on `app.prefs.askedForNotifications`.

### C. Haptics (rule 12): S

- Android: add `LocalHapticFeedback.current.performHapticFeedback(HapticFeedbackType.Confirm)` (or `LongPress` on older Compose) after a check-in is saved, when a badge is earned (`CelebrationDialog`), and on salute and follow.
- iOS: add `.sensoryFeedback(.selection, trigger:)` on salute and follow, so both apps give the same feedback.

### D. Red map marker (rule 13): S

- iOS: draw the arrival marker in the brand orange or the tint colour, not red (`CheckInDetailView.swift:729`). Check how Android draws the same route and match it.
- Owner decision: red unread mark on the bell, or orange (`FeedScreen.swift:57-58`, `SocialScreens.kt:149`).

### E. Android Check in tab opens the form directly (rule 3): M

- Tapping the middle tab calls `checkIn.open()` and does not switch tabs, like iOS (`RootView.swift:101-112`).
- Move "Recent check-ins" (`AppScreen.kt:180-183`, `RecentCheckIns` in `CheckInScreen.kt:858`) to a "Check-in history" page opened from Profile, like iOS (`ProfileScreen.swift:175-176`).
- Update the Compose UI tests that use the `open-check-in` and `tab-CHECK_IN` tags.

### F. Pull to refresh (rule 1): M

- Android: wrap the Feed, Badges, Activity, a person's page and Profile in Material 3 `PullToRefreshBox` (in the Compose BOM `2026.09.00` the app already uses). Call the same refresh functions as the "Refresh" buttons today, then remove those buttons.
- iOS: add `.refreshable` to Profile, a person's page, Collections and Check-in history.
- Explore: add it on both, or leave it off on both if its data is all on the phone.

### G. Empty states with a next step (rule 7): S–M

- iOS: add a "Sign in" button to the signed-out Feed and Badges, like Android. It switches to the Profile tab (`FeedScreen.swift:137`, `BadgesScreen.swift:20`). Add a "Check in" button to the empty check-in history (`CheckInHistoryView.swift:21`).
- Android: use `EmptyState` for the signed-in empty Feed, with a "Find people" button like iOS (`SocialScreens.kt:165`). Also use it for empty Activity (`InboxScreens.kt:54`) and for the empty Badges list.
- Use the same titles, texts and buttons on both apps.

### H. Back arrow and close X (rules 6 and 11): M

- Android:
  - Add vector drawables `ic_arrow_back` and `ic_close` (Material symbols).
  - Turn `PageHeader` (`ProfileScreens.kt:470`) into a row with an `IconButton` arrow (48 dp, content description "Back") and the title.
  - Replace the eight copied "‹ Back" rows with `PageHeader`.
  - Give the check-in form, the edit screens and the scanner a top row with an X button that closes them.
  - Replace the text "⋮" with `ic_glyph_more` everywhere, and the text "▾" with a small icon.
- iOS:
  - Where closing loses nothing (the check-in type picker in `CheckInSheet.swift:83`, the photo viewer), use an `xmark` toolbar button with the label "Close". On iOS 26 and newer this can be `Button(role: .close)`. The app targets iOS 18, so wrap it in `if #available`.
  - Keep "Cancel" where it throws away input (edit forms, report).
- Both: put a gear icon at the top right of Profile that opens Settings, and keep the text row as well. Add a "Find people" icon to the Android Feed header, like iOS.

### I. Scroll to top on tab tap (rule 10): M

- First, check iOS in the Simulator. If tapping the active tab already scrolls to the top, mark iOS done.
- iOS, if needed: in the `tabSelection` setter (`RootView.swift:102-112`), when the new value equals `selection`, post a signal (for example a counter in the environment). Each tab's list uses `ScrollViewReader` or `.scrollPosition` to scroll to its first row, and pops its `NavigationStack` to the root if it is deeper.
- Android: in `onClick` (`AppScreen.kt:116`), if `tab == social.tab`, call a `scrollToTop` on that tab's `LazyListState`, or `ScrollState`, with `animateScrollToItem(0)`. The states must be lifted to `AppScreen`, or kept in the view models, so they can be reached.
- Android, optional, bigger: keep the tab bar on pages above the tabs so a tab tap can go back to the tab's first screen, like iOS. This touches the whole page stack in `SocialViewModel`, so do it as its own step.

### J. Primary buttons within thumb reach (rule 8): M

- iOS: pin "Check in" (`AirportCheckInView.swift:111`, `FlownCheckInView.swift:269`, `SpottedCheckInView.swift:111`) to the bottom with `.safeAreaInset(edge: .bottom)`, as `BoardingPassScanning.swift:55` already does. For the edit views, keep "Save" at the top right (the iOS norm), and add the same pinned bottom button.
- Android: make `SaveBar` (`CheckInScreen.kt:769`) a bar pinned to the bottom of the form, outside the scrolling column. Once E is done, the "Check in" button at the top of the Check in tab is gone.

### K. Undo after deleting (rule 13): L

The server deletes a check-in for good, with its photos, salutes and comments (`FeedScreen.swift:74`). So Undo has to hold back the real delete:

- When the person deletes, hide the item at once and show a bar at the bottom: "Check-in deleted · Undo" for about 5 seconds.
- Run the real delete (iOS `CheckInDeletion.delete`, Android `outbox.delete` in `CheckInViewModel.kt:390`) only when the bar goes away.
- If the app goes to the background or closes first, the delete must still happen. Store the pending delete in the outbox, with a "not before" time, so it survives.
- Do the same for comments. Photo deletes in the edit screens run at once (`AppScreen.kt:131-133`). Move them to when the edit is saved, so "Cancel" undoes them.
- Android: use a `SnackbarHost` in the `Scaffold` (`AppScreen.kt:106`). iOS has no system snackbar, so build a small bottom overlay in `RootView` that looks the same.
- With Undo in place, the confirm dialog for a check-in can go. Keep it for deleting the account, which can't be undone.

### L. Both sign-in providers on both apps (rule 15): M per app, plus setup

- Android: add "Sign in with Apple" through Supabase's OAuth web flow in a Custom Tab, with the existing deep link to return. This needs a Services ID and key in the Apple developer account, and the Apple provider set up in Supabase for the web flow.
- iOS: add "Sign in with Google" with the Google Sign-In SDK and Supabase `signInWithIdToken`, like Android. This needs an iOS client ID in Google Cloud.
- Register the Resend sending domain with Apple's private email relay, so sign-in links reach "Hide My Email" addresses.
- Make the Android release build fail if `WINGSPOT_GOOGLE_CLIENT_ID` is empty, so the Google button can't go missing.
- This needs the owner's yes and changes in the Apple, Google and Supabase consoles.

## Proposed order

| Step | What | Rules | Effort |
|---|---|---|---|
| 1 | A. Tap targets | 9 | S |
| 2 | B. Android notification ask | 14 | S |
| 3 | C. Haptics | 12 | S |
| 4 | D. Red map marker, plus the owner's call on the bell mark | 13 | S |
| 5 | E. Android Check in tab opens the form | 3 | M |
| 6 | F. Pull to refresh | 1 | M |
| 7 | G. Empty states | 7 | S–M |
| 8 | H. Back arrow, close X, gear | 6, 11 | M |
| 9 | I. Scroll to top on tab tap (check iOS first) | 10 | M |
| 10 | J. Primary buttons at the bottom | 8 | M |
| 11 | K. Undo after deleting | 13 | L |
| 12 | L. Apple and Google on both apps | 15 | M + setup |

Steps 1–4 are small and can ship in one build. Steps 5–10 change how screens look and work, so each gets its own PR with screenshots from both apps. Steps 11 and 12 need outbox changes or provider setup, and the owner's yes before they start.

## Open questions for the owner

1. Red unread mark on the bell: keep it red (platform norm), or make it orange?
2. Undo: is it all right to drop the confirm dialog for deleting a check-in once Undo is in place?
3. Sign-in: add Apple on Android and Google on iOS, or only make sure email links reach Apple relay addresses?
4. Android: keep the tab bar on pages above the tabs, like iOS (bigger change), or leave it hidden?
