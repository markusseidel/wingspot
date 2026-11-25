# Home screen shortcuts (long press on the app icon): plan

Idea from the owner: on the iPhone home screen a long press on the app icon opens a small menu with shortcuts. Wingspot should offer the check-in kinds there, and the same on Android. Status: plan only, nothing built. Issue #349.

## Goal

- A long press on the Wingspot icon shows **Spotted**, **Airport** and **Flown**. A tap opens the app on that check-in form, ready to type, with no taps through the Check in tab and the kind list in between. That is the whole point: a spotter at the fence wants the registration field in two seconds.
- While a spotting session runs, a fourth entry **Session at <place>** opens the sighting form of that session.
- It works when the app is closed, in the background, or already on screen, and in German and English.
- Both apps get it (parity), with the same entries in the same order.

## What the two platforms call it

| | iOS | Android |
|---|---|---|
| Name | Home Screen Quick Actions (`UIApplicationShortcutItem`) | App Shortcuts (static and dynamic shortcuts, `ShortcutManager`) |
| Where | Long press on the icon, also on iPad | Long press on the launcher icon; the launcher can also let people drag one to the home screen |
| How many | 4 shown (static first, then dynamic) | Launcher decides, usually 4 or 5; `ShortcutManager.getMaxShortcutCountPerActivity()` |
| Minimum version | all supported versions | API 25; Wingspot's minimum is 26, so no fallback is needed |
| Fixed list | `UIApplicationShortcutItems` in `Info.plist` | `res/xml/shortcuts.xml`, linked from the launcher activity in the manifest |
| Changing list | `UIApplication.shared.shortcutItems` | `ShortcutManagerCompat.setDynamicShortcuts` |

## What exists today

- **iOS:** the Check in tab does not switch tabs; `RootView` presents `CheckInSheet` (a `NavigationStack` with the list Spotted, Flown, Airport) in a sheet. Each row pushes `SpottedCheckInView`, `FlownCheckInView` or `AirportCheckInView`. Notifications already have a router for taps that arrive before any screen is on show (`PushRouter`, read by `FeedScreen`), and a `PushAppDelegate` through `@UIApplicationDelegateAdaptor`. The project uses the generated scene manifest (`INFOPLIST_KEY_UIApplicationSceneManifest_Generation`) and `Wingspot/App/Info.plist` for the rest.
- **Android:** `MainActivity` is `singleTask` and already reads intents in `handle(intent)`, from `onCreate` and `onNewIntent`: notification extras (`Push.destination`) and `wingspot://` links. The check-in screen is `Tab.CHECK_IN` of `AppScreen`, driven by `CheckInViewModel` (`open()`, `chooseKind(Kind)`, `state.kind`, with `Kind.SPOTTED, AIRPORT, FLOWN`). Vector icons for the three kinds exist (`ic_glyph_binoculars`, `ic_glyph_building`, `ic_glyph_plane`).
- **Spotting session:** `SpotSessionStore` (iOS) and `SpotSession` with `SessionStore` (Android) know the running session, its place name, and when it ends (12 hours).
- Check-ins work signed out and offline, so the shortcuts do not need an account.

## Decisions

1. **Entries and order:** 1 Spotted, 2 Airport, 3 Flown, and a dynamic 4 "Session at <place>" only while a session runs. Spotted is first because it is the one done most often. The titles are the words the app already uses ("Spotted", "Airport", "Flown"; German "Gespottet", "Flughafen", "Geflogen"); the subtitle is the existing one ("An aircraft you have seen" and so on).
2. **A shortcut opens the form, not the sheet.** The sheet or tab is skipped: the form is shown straight away, with the registration field focused where the form does that today. Back from the form goes to the Check in list (iOS) or the form's own close (Android), as it would after tapping through.
3. **While a session runs**, "Spotted" already links the sighting to the session (the forms read the running session). The dynamic fourth entry exists for the person who sees the long-press menu and wants to know that the session is still running; it opens the same Spotted form. It is removed when the session ends or runs out, and rebuilt when the app starts or comes back (a session can run out while the app is closed).
4. **Waiting for the app to be ready.** If the shortcut arrives while a full-screen step is up (onboarding, first profile setup, terms), the action is kept and used when the main screen is there, like a tapped notification. It never skips a legal or setup step.
5. **One small router, the same on both apps.** A `QuickAction` value (`spotted`, `airport`, `flown`, `session`) with a stable id string (`site.wingspot.quick.spotted` and so on), parsed by one function with a unit test. It lives in the shared package of each app (`WingspotCore` and `core`) so it can be tested without a phone. The app stores the pending action; the root screen consumes it.
6. **No new permission, no server, no data.** Shortcuts are local. The session entry shows a place name that is already on the phone. Nothing about them is sent anywhere, and nothing sensitive goes into the title (a place name of a spotting location is public data anyway).
7. **Android uses explicit intents** to `MainActivity` with an extra (`quick_action`), not a new `wingspot://` link, so no web page or other app can trigger them through the existing link handling. An explicit intent can still be sent by another app (the activity is exported for the launcher); the worst it does is open the form, which is harmless and needs no data. The static file marks the shortcuts `enabled` and the dynamic one is `setLongLived(false)`.
8. **Icons.** iOS uses SF Symbols (`binoculars.fill`, `building.columns.fill`, `airplane.departure`), the same as the sheet. Android uses the existing vector glyphs in the brand colour on the launcher's own shape (adaptive foreground, 24 dp artwork on a 108 dp canvas), because shortcut icons are drawn by the launcher and must not be too busy.
9. **Not now:** App Intents and Siri phrases ("Hey Siri, log a sighting in Wingspot"), Spotlight entries, home screen widgets and lock screen controls. They share the same `QuickAction` and can be added on top.

## iOS

- `Wingspot/App/Info.plist`: `UIApplicationShortcutItems` with the three static items (`UIApplicationShortcutItemType`, `...IconSymbolName`, `...Title`, `...Subtitle`). Titles and subtitles are localized through `InfoPlist.xcstrings` (English and German); `check-strings.sh` is told about the file if it checks catalogs.
- A scene delegate through the scene configuration of the app delegate (`application(_:configurationForConnecting:options:)`), because SwiftUI apps have no other hook for a shortcut:
  - `scene(_:willConnectTo:options:)` reads `connectionOptions.shortcutItem` for a cold start,
  - `windowScene(_:performActionFor:completionHandler:)` handles a shortcut while the app runs.
  Both pass the type to `QuickActionRouter.shared` (`@Observable`, like `PushRouter`) and complete with `true`.
- `RootView` reads the router: when an action is pending and no setup screen is up, it selects the Feed tab behind, opens the check-in sheet with `initialKind` set, and clears the action. `CheckInSheet` gets `initialKind: CheckInKind?` and starts its `NavigationStack` with that kind pushed.
- The dynamic item: `QuickActionRouter.updateSessionItem(session:)` sets `UIApplication.shared.shortcutItems` to `[session item]` when a session runs and `[]` when not, called on start and end of a session and when the app becomes active.
- Tests (in `WingspotCore` and `Persistence`'s style): parsing of the type strings, an unknown type is ignored, the pending action is consumed once. Click-through in the simulator: `xcrun simctl` cannot press a shortcut, so the check is by hand on a phone, once cold and once warm.

## Android

- `res/xml/shortcuts.xml`: three `<shortcut>` entries (`shortcutId`, `enabled`, `icon`, `shortcutShortLabel`, `shortcutLongLabel`, `shortcutDisabledMessage`), each with an `<intent>` (`android.intent.action.MAIN`, `targetPackage`, `targetClass` = `MainActivity`, extra `quick_action`). Referenced in the manifest with `<meta-data android:name="android.app.shortcuts" android:resource="@xml/shortcuts" />` on the launcher activity.
- Labels in `values` and `values-de` (short label up to 10 characters is the safe length: "Spotted", "Airport", "Flown", "Gespottet", "Flughafen", "Geflogen"; the long label is the full line).
- `MainActivity.handle(intent)` reads `quick_action`, calls `QuickAction.parse`, and stores the pending action in the `CheckInViewModel` (survives rotation); `AppScreen` consumes it when the main screen is visible: `social.tab = Tab.CHECK_IN`, `checkIn.open()`, `checkIn.chooseKind(...)`.
- The dynamic shortcut `session`: `ShortcutManagerCompat.setDynamicShortcuts` with a label "Session at <place>", set when a session starts, removed when it ends or has run out, refreshed in `onCreate`/`onResume` (a session can run out while the app is closed).
- Tests: `QuickAction.parse` in `core`; a unit test that every `shortcutId` in the static file is one `QuickAction` knows (reads the XML in the test); a Compose test that the pending action opens the right form.

## Order of work

1. One PR per platform (the parity rule), merged together: the shared `QuickAction`, the static entries, the routing, the dynamic session entry, strings in both languages.
2. Both builds with the tester text and the release note for each platform ("Long press the app icon: Spotted, Airport, Flown").
3. Click-through on a phone each: cold start, app in the background, app in the check-in sheet already, with a session running (the dynamic entry), signed out, and with the onboarding screen up (the action waits).

## Risks

- **iOS gives one hook for a cold start and another for a running app**; testing only one of them is the usual bug. Both are in the checklist.
- **Android launchers differ.** Some show fewer entries, some order differently; the static list is therefore the three kinds only, and the session entry is optional.
- **A stale dynamic entry.** A session that ended while the app was closed leaves its shortcut on the icon until the app runs again. The entry opens the normal Spotted form, which is harmless, and the next start removes it.
- **Titles are long in German.** "Flughafen" and "Gespottet" fit; if a launcher cuts a label, the long label is shown elsewhere.

## Open questions for the owner

1. Are these entries right: Spotted, Airport, Flown, plus the session entry while one runs? Or also "Feed" or "Inbox"?
2. Spotted first (the plan) or the same order as the sheet (Spotted, Flown, Airport)?
3. Should the shortcut open the form with the keyboard ready (the plan), or the kind list like the tab does?
